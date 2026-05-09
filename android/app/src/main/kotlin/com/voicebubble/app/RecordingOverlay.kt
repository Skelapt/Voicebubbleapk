package com.voicebubble.app

import android.animation.ValueAnimator
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
import android.view.animation.PathInterpolator
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import java.io.File

/**
 * Native floating overlay — the recording pill that paints over
 * whatever app the user is in. Same primitive as the bubble itself
 * (`WindowManager.addView`), no Flutter / isolate / plugin layer.
 *
 * NB2: live recording. Premium design language —
 *   • Glass blur behind (Android 12+) so the underlying app stays
 *     legible but recedes.
 *   • Centered pill, capped at 320dp wide so it never feels like
 *     a slab.
 *   • Pulsing 6dp red "live" dot, no text label needed.
 *   • Mirrored 32-bar oscilloscope waveform driven off
 *     `MediaRecorder.maxAmplitude`.
 *   • 52dp purple stop button that *breathes* (subtle scale pulse)
 *     so it visually invites the tap. Soft halo glow.
 *   • Tiny 28dp cancel chip — secondary, never competes.
 *   • 220ms scale-fade in / 140ms scale-fade out so transitions
 *     feel composed, not jumpy.
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

    private val animators = mutableListOf<ValueAnimator>()

    fun isShowing(): Boolean = view != null

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
                hideAnimated {
                    if (path != null) onComplete(path)
                }
            },
            onCancel = {
                stopRecording(ctx)?.let { p ->
                    runCatching { File(p).delete() }
                }
                hideAnimated { onCancel() }
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
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            type,
            // FLAG_NOT_FOCUSABLE keeps the underlying app interactive.
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.CENTER
        }

        // Glass blur of underlying app on Android 12+. Adds the
        // single-most-important "premium" cue — the underlying
        // content stays visible but recedes. Older devices fall
        // back to the card's own 88% solid fill.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            params.flags = params.flags or
                WindowManager.LayoutParams.FLAG_BLUR_BEHIND
            params.blurBehindRadius = 28
        }

        // Enter animation: subtle scale + fade. 220ms easeOutCubic.
        root.alpha = 0f
        root.scaleX = 0.94f
        root.scaleY = 0.94f
        windowManager.addView(root, params)
        view = root
        root.animate()
            .alpha(1f)
            .scaleX(1f)
            .scaleY(1f)
            .setDuration(220)
            .setInterpolator(PathInterpolator(0.16f, 1f, 0.3f, 1f))
            .start()

        startRecording(ctx)
    }

    fun hide() = hideAnimated(null)

    private fun hideAnimated(after: (() -> Unit)?) {
        ampPoll?.let { ampHandler?.removeCallbacks(it) }
        ampHandler = null
        ampPoll = null
        cancelAnimators()
        waveform = null
        val v = view
        val windowManager = wm
        if (v == null || windowManager == null) {
            view = null
            wm = null
            after?.invoke()
            return
        }
        view = null
        wm = null
        v.animate()
            .alpha(0f)
            .scaleX(0.96f)
            .scaleY(0.96f)
            .setDuration(140)
            .setInterpolator(PathInterpolator(0.4f, 0f, 1f, 1f))
            .withEndAction {
                try { windowManager.removeView(v) } catch (_: Throwable) {}
                after?.invoke()
            }
            .start()
    }

    private fun cancelAnimators() {
        for (a in animators) {
            try { a.cancel() } catch (_: Throwable) {}
        }
        animators.clear()
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

            ampHandler = Handler(Looper.getMainLooper())
            ampPoll = object : Runnable {
                override fun run() {
                    val amp = try { rec.maxAmplitude } catch (_: Throwable) { 0 }
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
            // Cap pill width at ~320dp so it never feels slab-y.
            // Outer FrameLayout is WRAP_CONTENT so the card sets
            // its own bounds.
        }

        val card = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(
                dp(ctx, 16),
                dp(ctx, 14),
                dp(ctx, 12),
                dp(ctx, 14)
            )
            background = GradientDrawable().apply {
                cornerRadius = dp(ctx, 32).toFloat()
                // 88% navy — feels solid where blur isn't supported,
                // and lets blur do the heavy lifting where it is.
                setColor(Color.parseColor("#E10D0D1A"))
                setStroke(
                    1, // 0.5dp visually after AA
                    Color.parseColor("#14FFFFFF") // white @ 8%
                )
            }
            // Soft drop shadow — Android elevation gets us part of
            // the way; the blur-behind does the rest.
            elevation = dp(ctx, 18).toFloat()
            layoutParams = FrameLayout.LayoutParams(
                dp(ctx, 320),
                FrameLayout.LayoutParams.WRAP_CONTENT
            )
        }

        // ●  the live "REC" dot. No label, no text.
        val recDot = View(ctx).apply {
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.parseColor("#FF3B30")) // iOS-y red
            }
            val s = dp(ctx, 7)
            layoutParams = LinearLayout.LayoutParams(s, s).apply {
                marginEnd = dp(ctx, 10)
            }
            alpha = 0.4f
        }
        startBreathing(recDot, fromAlpha = 0.35f, toAlpha = 1f, durationMs = 800)

        // Live waveform, mirrored from center, fills remaining space.
        val wave = WaveformView(ctx).apply {
            layoutParams = LinearLayout.LayoutParams(
                0,
                dp(ctx, 40),
                1f
            )
        }
        waveform = wave

        // Primary STOP. Breathing scale pulse so it visually
        // invites the tap. Soft purple halo via large elevation +
        // tinted shadow.
        val stop = TextView(ctx).apply {
            text = "■"
            setTextColor(Color.WHITE)
            textSize = 16f
            gravity = Gravity.CENTER
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.parseColor("#7C6AE8"))
            }
            elevation = dp(ctx, 8).toFloat()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                outlineSpotShadowColor = Color.parseColor("#7C6AE8")
                outlineAmbientShadowColor = Color.parseColor("#7C6AE8")
            }
            val size = dp(ctx, 52)
            layoutParams = LinearLayout.LayoutParams(size, size).apply {
                marginStart = dp(ctx, 12)
            }
            isClickable = true
            isFocusable = true
            setOnClickListener {
                // Snap-down haptic feel: scale to 0.9 for 80ms, then
                // run the actual stop.
                animate()
                    .scaleX(0.9f).scaleY(0.9f)
                    .setDuration(80)
                    .withEndAction {
                        animate().scaleX(1f).scaleY(1f).setDuration(120).start()
                        onStop()
                    }.start()
            }
        }
        startBreathing(stop, fromScale = 0.97f, toScale = 1f, durationMs = 1500)

        // Secondary CANCEL — smaller, quieter so it doesn't compete
        // with stop.
        val cancel = TextView(ctx).apply {
            text = "✕"
            setTextColor(Color.parseColor("#CCFFFFFF"))
            textSize = 13f
            gravity = Gravity.CENTER
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.parseColor("#10FFFFFF"))
            }
            val size = dp(ctx, 28)
            layoutParams = LinearLayout.LayoutParams(size, size).apply {
                marginStart = dp(ctx, 8)
            }
            isClickable = true
            isFocusable = true
            setOnClickListener { onCancel() }
        }

        card.addView(recDot)
        card.addView(wave)
        card.addView(stop)
        card.addView(cancel)
        outer.addView(card)
        return outer
    }

    /** Breathing alpha pulse used by the REC dot. */
    private fun startBreathing(
        target: View,
        fromAlpha: Float,
        toAlpha: Float,
        durationMs: Long,
    ) {
        val a = ValueAnimator.ofFloat(fromAlpha, toAlpha).apply {
            duration = durationMs
            repeatMode = ValueAnimator.REVERSE
            repeatCount = ValueAnimator.INFINITE
            interpolator = PathInterpolator(0.4f, 0f, 0.6f, 1f) // soft sine-ish
            addUpdateListener { target.alpha = it.animatedValue as Float }
        }
        a.start()
        animators.add(a)
    }

    /** Breathing scale pulse used by the stop button. */
    private fun startBreathing(
        target: View,
        fromScale: Float,
        toScale: Float,
        durationMs: Long,
    ) {
        val a = ValueAnimator.ofFloat(fromScale, toScale).apply {
            duration = durationMs
            repeatMode = ValueAnimator.REVERSE
            repeatCount = ValueAnimator.INFINITE
            interpolator = PathInterpolator(0.4f, 0f, 0.6f, 1f)
            addUpdateListener {
                val v = it.animatedValue as Float
                target.scaleX = v
                target.scaleY = v
            }
        }
        a.start()
        animators.add(a)
    }

    private fun dp(ctx: Context, value: Int): Int =
        (value * ctx.resources.displayMetrics.density).toInt()
}
