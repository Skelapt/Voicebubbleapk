package com.voicebubble.app

import android.content.Context
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Native counterpart to the Dart `DebugLogService`. Writes into the
 * same SharedPreferences key the Dart side reads from, so the in-app
 * Debug Log screen shows a unified timeline of:
 *   - Application init (MyApplication)
 *   - Bubble service lifecycle (OverlayService)
 *   - Bubble taps + long-presses
 *   - showOverlay invocations + outcomes
 *   - AccessibilityService events / text-injection results
 *
 * Cross-isolate format is a single JSON-encoded array stored as a
 * String — both sides read/write the same key (`flutter.vb_debug_log_json`)
 * without having to wrestle with shared_preferences' StringList
 * encoding.
 *
 * Rolls at 200 entries so we never bloat the prefs file.
 */
object DebugLog {
    private const val PREFS = "FlutterSharedPreferences"
    private const val KEY = "flutter.vb_debug_log_json"
    private const val MAX_ENTRIES = 200
    private const val TAG = "VBDebug"

    private val isoFormat: ThreadLocal<SimpleDateFormat> = ThreadLocal.withInitial {
        SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS", Locale.US)
    }

    @Synchronized
    fun log(context: Context, source: String, message: String) {
        Log.d(TAG, "[$source] $message")
        try {
            val prefs = context.applicationContext
                .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val raw = prefs.getString(KEY, "[]") ?: "[]"
            val arr = try { JSONArray(raw) } catch (_: Throwable) { JSONArray() }
            val entry = JSONObject().apply {
                put("t", isoFormat.get()!!.format(Date()))
                put("s", source)
                put("m", message)
            }
            arr.put(entry)
            // Roll the buffer.
            val rolled = if (arr.length() > MAX_ENTRIES) {
                val out = JSONArray()
                val skip = arr.length() - MAX_ENTRIES
                for (i in skip until arr.length()) out.put(arr.get(i))
                out
            } else arr
            prefs.edit().putString(KEY, rolled.toString()).apply()
        } catch (e: Throwable) {
            Log.e(TAG, "Failed to write debug log entry", e)
        }
    }
}
