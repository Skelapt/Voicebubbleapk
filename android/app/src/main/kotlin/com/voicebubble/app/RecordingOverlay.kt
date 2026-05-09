package com.voicebubble.app

import android.content.Context
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView

/**
 * Pure-native floating overlay that hosts the recording pill / result
 * card. Replaces our entire `flutter_overlay_window` integration —
 * no second Flutter engine, no overlay isolate, no method channel,
 * no FlutterEngineCache plumbing. Same primitive the bubble itself
 * uses: `WindowManager.addView(plainAndroidView, params)`.
 *
 * This is what Wispr / Grammarly / every successful "AI in any app"
 * Android app does. The reason it's bulletproof is that it doesn't
 * cross any Flutter / isolate / plugin boundaries — Android sees
 * it as a regular system overlay window owned by our process.
 *
 * NB1 scope: just prove the overlay paints over the current app
 * with a tappable cancel chip. Recording, AI call, result card,
 * Insert / preset fan come in subsequent commits (NB2-NB5).
 */
object RecordingOverlay {

    private var view: View? = null
    private var wm: WindowManager? = null

    fun isShowing(): Boolean = view != null

    /**
     * Show the recording card centered on the screen, on top of
     * whatever app the user is in. [onDismiss] is called when the
     * user taps the cancel chip on the card.
     */
    fun show(ctx: Context, onDismiss: () -> Unit) {
        if (view != null) return // already up — coalesce duplicate taps

        val windowManager =
            ctx.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        wm = windowManager

        val root = buildCard(ctx, onDismiss)

        val type =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            } else {
                @Suppress("DEPRECATION")
                WindowManager.LayoutParams.TYPE_PHONE
            }

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            type,
            // FLAG_NOT_FOCUSABLE so the user's keyboard / app stays
            // interactive in the background. We only handle taps on
            // our card itself.
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.CENTER
        }

        windowManager.addView(root, params)
        view = root
    }

    fun hide() {
        val v = view ?: return
        try {
            wm?.removeView(v)
        } catch (_: Throwable) { /* already detached, fine */ }
        view = null
        wm = null
    }

    private fun buildCard(ctx: Context, onDismiss: () -> Unit): View {
        // Outer container provides the horizontal margin from the
        // screen edges so the card doesn't paint edge-to-edge.
        val outer = FrameLayout(ctx).apply {
            setPadding(dp(ctx, 16), 0, dp(ctx, 16), 0)
        }

        val card = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(
                dp(ctx, 20),
                dp(ctx, 16),
                dp(ctx, 12),
                dp(ctx, 16)
            )
            background = GradientDrawable().apply {
                cornerRadius = dp(ctx, 28).toFloat()
                setColor(Color.parseColor("#E60D0D1A")) // navy 90%
                setStroke(dp(ctx, 1), Color.parseColor("#1AFFFFFF")) // 10% white border
            }
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.WRAP_CONTENT
            )
        }

        val title = TextView(ctx).apply {
            text = "VoiceBubble — recording (NB1 stub)"
            setTextColor(Color.WHITE)
            textSize = 14f
            layoutParams = LinearLayout.LayoutParams(
                0,
                LinearLayout.LayoutParams.WRAP_CONTENT,
                1f
            )
        }

        val cancel = TextView(ctx).apply {
            text = "✕"
            setTextColor(Color.WHITE)
            textSize = 20f
            setPadding(
                dp(ctx, 14),
                dp(ctx, 8),
                dp(ctx, 14),
                dp(ctx, 8)
            )
            setOnClickListener { onDismiss() }
        }

        card.addView(title)
        card.addView(cancel)
        outer.addView(card)
        return outer
    }

    private fun dp(ctx: Context, value: Int): Int =
        (value * ctx.resources.displayMetrics.density).toInt()
}
