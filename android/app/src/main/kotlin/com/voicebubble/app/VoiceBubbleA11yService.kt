package com.voicebubble.app

import android.accessibilityservice.AccessibilityService
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.Settings
import android.text.TextUtils
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityManager
import android.view.accessibility.AccessibilityNodeInfo

/**
 * Accessibility service that enables in-place text injection — the
 * core "type into whatever app you're in" feature.
 *
 * What it does:
 *  1. Tracks the currently-focused editable node + its app package.
 *  2. Exposes [setFocusedFieldText] so the rest of the app can
 *     inject AI-rewritten text directly at the user's cursor.
 *
 * Implementation notes (the hard-won bits):
 *  - ACTION_SET_TEXT REPLACES the entire text of the field. To respect
 *    a user's existing draft, we splice the new text at the current
 *    selection and SET_TEXT the combined string back, then move the
 *    cursor to just after what we inserted.
 *  - Some apps (older WhatsApp, some browsers) reject SET_TEXT. The
 *    fallback path copies our text to the clipboard and performs
 *    ACTION_PASTE on the focused node, which respects the cursor too.
 *  - Stale node references throw IllegalStateException once the window
 *    moves on, so we always re-fetch [rootInActiveWindow] right before
 *    injecting rather than caching nodes across user gestures.
 */
class VoiceBubbleA11yService : AccessibilityService() {

    companion object {
        private const val TAG = "VoiceBubbleA11y"

        @Volatile
        private var instance: VoiceBubbleA11yService? = null

        /** Currently focused app's package name, e.g. `com.whatsapp`. */
        @Volatile
        var lastFocusedPackage: String? = null
            private set

        fun getInstance(): VoiceBubbleA11yService? = instance

        /** Whether the user has enabled this specific service. */
        fun isEnabled(context: Context): Boolean {
            val am = context.getSystemService(Context.ACCESSIBILITY_SERVICE)
                as? AccessibilityManager ?: return false
            val enabled = am.getEnabledAccessibilityServiceList(
                android.accessibilityservice.AccessibilityServiceInfo.FEEDBACK_ALL_MASK
            )
            val pkg = context.packageName
            return enabled.any { it.id.startsWith(pkg) }
        }

        /** Deep-link to the system Accessibility settings. */
        fun openSettings(context: Context) {
            val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
        }
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        Log.d(TAG, "Service connected")
    }

    override fun onUnbind(intent: Intent?): Boolean {
        instance = null
        Log.d(TAG, "Service unbound")
        return super.onUnbind(intent)
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return
        // Track foreground app for the long-press preset hints later.
        when (event.eventType) {
            AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED,
            AccessibilityEvent.TYPE_VIEW_FOCUSED -> {
                event.packageName?.let { pkg ->
                    val newPkg = pkg.toString()
                    if (newPkg != lastFocusedPackage && newPkg != packageName) {
                        lastFocusedPackage = newPkg
                    }
                }
            }
        }
    }

    override fun onInterrupt() {
        // No-op — we don't speak to the user, so nothing to interrupt.
    }

    /**
     * Inject [text] into whatever editable field is currently focused
     * on screen. Returns true on success, false if no editable node
     * was found (caller should fall back to clipboard with a toast).
     */
    fun setFocusedFieldText(text: String): Boolean {
        if (text.isEmpty()) return false

        val node = findFocusedEditable() ?: run {
            Log.w(TAG, "No focused editable node — caller should fall back to clipboard")
            return false
        }

        return try {
            val ok = injectViaSetText(node, text) || injectViaPaste(node, text)
            if (!ok) Log.w(TAG, "Both SET_TEXT and PASTE failed for node $node")
            ok
        } finally {
            try { node.recycle() } catch (_: Throwable) {}
        }
    }

    /** Walks the accessibility tree looking for the focused editable node. */
    private fun findFocusedEditable(): AccessibilityNodeInfo? {
        val root = try {
            rootInActiveWindow
        } catch (e: Throwable) {
            Log.e(TAG, "rootInActiveWindow threw", e)
            null
        } ?: return null

        // First try input focus — this is the keyboard's focus, which is
        // exactly the field the user was typing into.
        val inputFocus = root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
        if (inputFocus != null && inputFocus.isEditable) return inputFocus

        // Fall back to a depth-first search for ANY editable focused node.
        return findEditableRecursive(root)
    }

    private fun findEditableRecursive(node: AccessibilityNodeInfo?): AccessibilityNodeInfo? {
        if (node == null) return null
        if (node.isEditable && node.isFocused) return node
        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            val match = findEditableRecursive(child)
            if (match != null) return match
        }
        return null
    }

    /**
     * Splice [text] into the focused field at the current cursor
     * position and apply with ACTION_SET_TEXT. Then move the cursor
     * to immediately after what we inserted so the user can keep
     * typing if they want.
     */
    private fun injectViaSetText(node: AccessibilityNodeInfo, text: String): Boolean {
        val existing = node.text?.toString() ?: ""
        val selStart = node.textSelectionStart.coerceAtLeast(0).coerceAtMost(existing.length)
        val selEnd = node.textSelectionEnd.coerceAtLeast(selStart).coerceAtMost(existing.length)

        val newText = if (existing.isEmpty()) {
            text
        } else {
            existing.substring(0, selStart) + text + existing.substring(selEnd)
        }

        val args = Bundle().apply {
            putCharSequence(
                AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE,
                newText
            )
        }
        val ok = node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
        if (!ok) return false

        // Move cursor to the end of what we just inserted.
        val newCursor = selStart + text.length
        val selArgs = Bundle().apply {
            putInt(AccessibilityNodeInfo.ACTION_ARGUMENT_SELECTION_START_INT, newCursor)
            putInt(AccessibilityNodeInfo.ACTION_ARGUMENT_SELECTION_END_INT, newCursor)
        }
        // Best-effort — some nodes refuse selection moves but the text
        // is already in, so we still report success.
        try {
            node.performAction(AccessibilityNodeInfo.ACTION_SET_SELECTION, selArgs)
        } catch (_: Throwable) {}

        return true
    }

    /**
     * Fallback: copy the text to the system clipboard and ask the
     * focused node to ACTION_PASTE. Respects the cursor by definition
     * because that's what the OS paste does.
     */
    private fun injectViaPaste(node: AccessibilityNodeInfo, text: String): Boolean {
        return try {
            val cm = getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
                ?: return false
            cm.setPrimaryClip(ClipData.newPlainText("VoiceBubble", text))
            node.performAction(AccessibilityNodeInfo.ACTION_PASTE)
        } catch (e: Throwable) {
            Log.e(TAG, "Clipboard paste fallback failed", e)
            false
        }
    }
}
