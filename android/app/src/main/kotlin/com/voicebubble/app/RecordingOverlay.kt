package com.voicebubble.app

import android.content.Context
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.media.MediaRecorder
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import java.io.File

/**
 * Pure-native floating overlay that hosts the recording pill /
 * (later) result card. Same primitive the bubble itself uses:
 * `WindowManager.addView(plainAndroidView)`.
 *
 * NB2 scope: live recording UI.
 *   • Adds a [WaveformView] driven by `MediaRecorder.maxAmplitude`
 *     polled on a 80ms Handler tick.
 *   • Big purple stop button; tapping it stops the recorder and
 *     fires `onComplete(audioPath)`.
 *   • Cancel ✕ chip stops the recorder, deletes the file, fires
 *     `onCancel()`.
 *
 * NB3 will wire `onComplete` → AI backend; NB4 will swap the card
 * for the result UI; NB5 adds preset fan; NB6 polish.
 */
object RecordingOverlay {

    private const val TAG = "RecordingOverlay"

    private var view: View? = null
    private var wm: WindowManager? = null
    private var recorder: MediaRecorder? = null
    private var audioFile: File? = null
    private var ampHandler: Handler? = null
    private var ampPoll: Runnable? = null
    private var waveform: WaveformView? = null

    fun isShowing(): Boolean = view != null

    /**
     * Show the recording overlay over whatever app the user is in.
     * Starts mic capture immediately.
     *
     * @param onComplete called with the recorded audio file path when
     *                   the user taps stop.
     * @param onCancel   called when the user taps the ✕ chip; the
     *                   audio file is already removed when this fires.
     */
    fun show(
        ctx: Context,
        onComplete: (audioPath: String) -> Unit,
        onCancel: () -> Unit,
    ) {
        if (view != null) return

        val windowManager =
            ctx.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        wm = windowManager

        val root = buildRecordingCard(
            ctx,
            onStop = {
                val path = stopRecording(ctx)
                hide()
                if (path != null) onComplete(path)
            },
            onCancel = {
                stopRecording(ctx)?.let { p ->
                    runCatching { File(p).delete() }
                }
                hide()
                onCancel()
            }
        )

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
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.CENTER
        }

        windowManager.addView(root, params)
        view = root

        // Begin recording immediately. If the mic isn't available
        // we still leave the overlay visible so the user gets feedback;
        // tapping cancel always removes everything cleanly.
        startRecording(ctx)
    }

    fun hide() {
        ampPoll?.let { ampHandler?.removeCallbacks(it) }
        ampHandler = null
        ampPoll = null
        waveform = null
        val v = view ?: return
        try { wm?.removeView(v) } catch (_: Throwable) { /* already detached */ }
        view = null
        wm = null
    }

    // ───────── MediaRecorder lifecycle ─────────

    private fun startRecording(ctx: Context) {
        try {
            val cacheDir = ctx.cacheDir
            audioFile = File(cacheDir, "vb_native_${System.currentTimeMillis()}.m4a")

            val rec = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                MediaRecorder(ctx)
            } else {
                @Suppress("DEPRECATION")
                MediaRecorder()
            }
            rec.setAudioSource(MediaRecorder.AudioSource.MIC)
            rec.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            rec.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            rec.setAudioEncodingBitRate(128000)
            rec.setAudioSamplingRate(44100)
            rec.setOutputFile(audioFile!!.absolutePath)
            rec.prepare()
            rec.start()
            recorder = rec
            DebugLog.log(
                ctx,
                "NativeOverlay",
                "MediaRecorder started → ${audioFile!!.name}"
            )

            // Drive the waveform off real mic levels.
            ampHandler = Handler(Looper.getMainLooper())
            ampPoll = object : Runnable {
                override fun run() {
                    val amp = try { rec.maxAmplitude } catch (_: Throwable) { 0 }
                    // MediaRecorder.maxAmplitude is a 16-bit signed
                    // peak (0..32767). Empirically ~8000 is a strong
                    // speaking voice — divide so a normal voice fills
                    // most of the bar.
                    val normalized = (amp / 8000f).coerceIn(0.12f, 1f)
                    waveform?.pushAmplitude(normalized)
                    ampHandler?.postDelayed(this, 80)
                }
            }
            ampHandler?.post(ampPoll!!)
        } catch (e: Throwable) {
            DebugLog.log(
                ctx,
                "NativeOverlay",
                "MediaRecorder start FAILED: ${e.javaClass.simpleName} ${e.message}"
            )
            Log.e(TAG, "Failed to start MediaRecorder", e)
        }
    }

    private fun stopRecording(ctx: Context): String? {
        ampPoll?.let { ampHandler?.removeCallbacks(it) }
        ampHandler = null
        ampPoll = null
        return try {
            recorder?.stop()
            recorder?.release()
            recorder = null
            val path = audioFile?.absolutePath
            DebugLog.log(ctx, "NativeOverlay", "MediaRecorder stopped → ${audioFile?.name}")
            path
        } catch (e: Throwable) {
            Log.e(TAG, "MediaRecorder stop failed", e)
            DebugLog.log(
                ctx,
                "NativeOverlay",
                "MediaRecorder stop threw: ${e.javaClass.simpleName} ${e.message}"
            )
            try { recorder?.release() } catch (_: Throwable) {}
            recorder = null
            null
        }
    }

    // ───────── View construction ─────────

    private fun buildRecordingCard(
        ctx: Context,
        onStop: () -> Unit,
        onCancel: () -> Unit,
    ): View {
        val outer = FrameLayout(ctx).apply {
            setPadding(dp(ctx, 16), 0, dp(ctx, 16), 0)
        }

        val card = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(
                dp(ctx, 20),
                dp(ctx, 14),
                dp(ctx, 12),
                dp(ctx, 14)
            )
            background = GradientDrawable().apply {
                cornerRadius = dp(ctx, 28).toFloat()
                setColor(Color.parseColor("#E60D0D1A")) // navy 90%
                setStroke(dp(ctx, 1), Color.parseColor("#1AFFFFFF"))
            }
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.WRAP_CONTENT
            )
        }

        // Live waveform takes the leading flex space.
        val wave = WaveformView(ctx).apply {
            layoutParams = LinearLayout.LayoutParams(
                0,
                dp(ctx, 44),
                1f
            )
        }
        waveform = wave

        // Primary STOP — purple circle with a square glyph.
        val stop = TextView(ctx).apply {
            text = "■"
            setTextColor(Color.WHITE)
            textSize = 18f
            gravity = Gravity.CENTER
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.parseColor("#7C6AE8"))
            }
            val size = dp(ctx, 52)
            layoutParams = LinearLayout.LayoutParams(size, size).apply {
                marginStart = dp(ctx, 12)
            }
            isClickable = true
            isFocusable = true
            setOnClickListener { onStop() }
        }

        // Secondary CANCEL chip.
        val cancel = TextView(ctx).apply {
            text = "✕"
            setTextColor(Color.WHITE)
            textSize = 16f
            gravity = Gravity.CENTER
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.parseColor("#1AFFFFFF"))
            }
            val size = dp(ctx, 36)
            layoutParams = LinearLayout.LayoutParams(size, size).apply {
                marginStart = dp(ctx, 8)
            }
            isClickable = true
            isFocusable = true
            setOnClickListener { onCancel() }
        }

        card.addView(wave)
        card.addView(stop)
        card.addView(cancel)
        outer.addView(card)
        return outer
    }

    private fun dp(ctx: Context, value: Int): Int =
        (value * ctx.resources.displayMetrics.density).toInt()
}
