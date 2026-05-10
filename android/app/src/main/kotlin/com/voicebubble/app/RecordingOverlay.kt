package com.voicebubble.app

import android.animation.ValueAnimator
import android.content.ClipData
import android.content.ClipboardManager
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
import android.view.animation.LinearInterpolator
import android.view.animation.PathInterpolator
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import java.io.File

/**
 * Pure-native floating overlay — recording → polishing → result
 * (with Insert / Retry / Cancel) → inserting → close. Same
 * primitive as the bubble itself (`WindowManager.addView`), no
 * Flutter / isolate / plugin layer.
 *
 * State machine:
 *   1. RECORDING   — live waveform, breathing stop button.
 *                    Stop tap → POLISHING.
 *   2. POLISHING   — three breathing dots + spinner. HTTP calls
 *                    (transcribe + magic rewrite) run on a worker
 *                    Thread; on success → RESULT, on failure → ERROR.
 *   3. RESULT      — intent badge, AI text, [↻ Retry][Insert ›].
 *                    Insert calls VoiceBubbleA11yService to drop
 *                    the text into the focused EditText of whatever
 *                    app is in the foreground; falls back to the
 *                    clipboard when no editable focus.
 *   4. INSERTING   — green ✓ flash, brief breath, dismiss.
 *   5. ERROR       — message + [↻ Retry] + ✕.
 *
 * The OUTER WindowManager view stays mounted across phases; we
 * just swap the contents of the inner card so the pill morphs
 * instead of jumping.
 */
object RecordingOverlay {

    private const val TAG = "RecordingOverlay"

    // ───────── State ─────────

    private var view: View? = null
    private var card: LinearLayout? = null
    private var ctxRef: Context? = null
    private var wm: WindowManager? = null

    private var recorder: MediaRecorder? = null
    private var audioFile: File? = null
    private var ampHandler: Handler? = null
    private var ampPoll: Runnable? = null
    private var waveform: WaveformView? = null

    private val animators = mutableListOf<ValueAnimator>()

    fun isShowing(): Boolean = view != null

    // ───────── Public API ─────────

    fun show(ctx: Context) {
        if (view != null) return

        val appCtx = ctx.applicationContext
        ctxRef = appCtx

        val windowManager =
            appCtx.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        wm = windowManager

        val container = FrameLayout(appCtx)
        val cardView = buildCardShell(appCtx)
        container.addView(cardView)
        card = cardView

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
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT
        ).apply { gravity = Gravity.CENTER }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            params.flags = params.flags or
                WindowManager.LayoutParams.FLAG_BLUR_BEHIND
            params.blurBehindRadius = 28
        }

        container.alpha = 0f
        container.scaleX = 0.94f
        container.scaleY = 0.94f
        windowManager.addView(container, params)
        view = container
        container.animate()
            .alpha(1f).scaleX(1f).scaleY(1f)
            .setDuration(220)
            .setInterpolator(PathInterpolator(0.16f, 1f, 0.3f, 1f))
            .start()

        // Land in the recording phase straight away.
        renderRecording(appCtx)
        startRecording(appCtx)
    }

    fun hide() = hideAnimated(null)

    private fun hideAnimated(after: (() -> Unit)?) {
        cancelAmpPoll()
        cancelAnimators()
        waveform = null
        val v = view
        val windowManager = wm
        view = null
        card = null
        ctxRef = null
        wm = null
        if (v == null || windowManager == null) {
            after?.invoke()
            return
        }
        v.animate()
            .alpha(0f).scaleX(0.96f).scaleY(0.96f)
            .setDuration(140)
            .setInterpolator(PathInterpolator(0.4f, 0f, 1f, 1f))
            .withEndAction {
                try { windowManager.removeView(v) } catch (_: Throwable) {}
                after?.invoke()
            }
            .start()
    }

    private fun cancelAmpPoll() {
        ampPoll?.let { ampHandler?.removeCallbacks(it) }
        ampHandler = null
        ampPoll = null
    }

    private fun cancelAnimators() {
        for (a in animators) try { a.cancel() } catch (_: Throwable) {}
        animators.clear()
    }

    // ───────── MediaRecorder lifecycle ─────────

    private fun startRecording(ctx: Context) {
        try {
            // Single-mission reward — first ever bubble record unlocks
            // 5 free minutes. Idempotent flag.
            grantBubbleFirstUseBonusIfNew(ctx)

            audioFile = File(
                ctx.cacheDir,
                "vb_native_${System.currentTimeMillis()}.m4a"
            )

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
            DebugLog.log(ctx, "NativeOverlay", "Recording → ${audioFile!!.name}")

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
                "Recorder start FAILED: ${e.javaClass.simpleName} ${e.message}"
            )
            Log.e(TAG, "Failed to start MediaRecorder", e)
            renderError(ctx, "Couldn't start recording.")
        }
    }

    private fun stopRecording(ctx: Context): String? {
        cancelAmpPoll()
        return try {
            recorder?.stop()
            recorder?.release()
            recorder = null
            val path = audioFile?.absolutePath
            DebugLog.log(ctx, "NativeOverlay", "Recorder stopped")
            path
        } catch (e: Throwable) {
            Log.e(TAG, "MediaRecorder stop failed", e)
            try { recorder?.release() } catch (_: Throwable) {}
            recorder = null
            null
        }
    }

    private fun discardAudio() {
        audioFile?.let { f -> runCatching { f.delete() } }
        audioFile = null
    }

    // ───────── Phase rendering ─────────

    private fun renderRecording(ctx: Context) {
        cancelAnimators()
        val c = card ?: return
        c.removeAllViews()

        val recDot = View(ctx).apply {
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.parseColor("#FF3B30"))
            }
            val s = dp(ctx, 7)
            layoutParams = LinearLayout.LayoutParams(s, s).apply {
                marginEnd = dp(ctx, 10)
            }
            alpha = 0.4f
        }
        startBreathingAlpha(recDot, 0.35f, 1f, 800)

        val wave = WaveformView(ctx).apply {
            layoutParams = LinearLayout.LayoutParams(
                0, dp(ctx, 40), 1f
            )
        }
        waveform = wave

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
                animate().scaleX(0.9f).scaleY(0.9f).setDuration(80).withEndAction {
                    animate().scaleX(1f).scaleY(1f).setDuration(120).start()
                    onStopTapped(ctx)
                }.start()
            }
        }
        startBreathingScale(stop, 0.97f, 1f, 1500)

        val cancel = cancelChip(ctx) { onCancelTapped(ctx) }

        c.addView(recDot)
        c.addView(wave)
        c.addView(stop)
        c.addView(cancel)
    }

    private fun renderPolishing(ctx: Context) {
        cancelAnimators()
        val c = card ?: return
        c.removeAllViews()

        // Three breathing dots (Apple Siri "thinking" pattern).
        val dotsRow = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(0, dp(ctx, 40), 1f)
        }
        for (i in 0 until 3) {
            val dot = View(ctx).apply {
                background = GradientDrawable().apply {
                    shape = GradientDrawable.OVAL
                    setColor(Color.parseColor("#7C6AE8"))
                }
                val s = dp(ctx, 8)
                layoutParams = LinearLayout.LayoutParams(s, s).apply {
                    marginStart = dp(ctx, 6)
                    marginEnd = dp(ctx, 6)
                }
                alpha = 0.3f
            }
            dotsRow.addView(dot)
            startBreathingAlpha(dot, 0.25f, 1f, 800, delayMs = (i * 180L))
        }

        val spinner = buildSpinnerCircle(ctx, dp(ctx, 52))

        val cancel = cancelChip(ctx) { onCancelTapped(ctx) }

        c.addView(dotsRow)
        c.addView(spinner.apply {
            (layoutParams as LinearLayout.LayoutParams).marginStart = dp(ctx, 12)
        })
        c.addView(cancel)
    }

    private fun renderResult(ctx: Context, text: String, label: String?) {
        cancelAnimators()
        val c = card ?: return
        c.removeAllViews()
        c.orientation = LinearLayout.VERTICAL
        c.gravity = Gravity.START
        c.setPadding(dp(ctx, 18), dp(ctx, 14), dp(ctx, 14), dp(ctx, 14))

        // Top row: intent badge + cancel
        val topRow = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
        }
        val badge = TextView(ctx).apply {
            text = (label?.uppercase() ?: "MAGIC")
            setTextColor(Color.parseColor("#7C6AE8"))
            textSize = 10f
            letterSpacing = 0.18f
            typeface = android.graphics.Typeface.DEFAULT_BOLD
            layoutParams = LinearLayout.LayoutParams(
                0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f
            )
        }
        val cancelChip = cancelChip(ctx) { onCancelTapped(ctx) }
        topRow.addView(badge)
        topRow.addView(cancelChip)
        c.addView(topRow)

        // Body: AI-rewritten text. Word-wrap, max 5 lines, tappable
        // (long-press to copy in NB6 polish).
        val bodyText = text.ifBlank { "(no text)" }
        val body = TextView(ctx).apply {
            this.text = bodyText
            setTextColor(Color.WHITE)
            textSize = 15f
            setLineSpacing(0f, 1.35f)
            maxLines = 5
            ellipsize = android.text.TextUtils.TruncateAt.END
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                topMargin = dp(ctx, 10)
                bottomMargin = dp(ctx, 14)
            }
        }
        c.addView(body)

        // Action row: Retry on the left, Insert primary on the right.
        val actions = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
        }
        val retry = secondaryButton(ctx, "↻  Retry") {
            onRetryTapped(ctx)
        }
        val spacer = View(ctx).apply {
            layoutParams = LinearLayout.LayoutParams(0, 1, 1f)
        }
        val insert = primaryInsertButton(ctx) {
            onInsertTapped(ctx, bodyText)
        }
        actions.addView(retry)
        actions.addView(spacer)
        actions.addView(insert)
        c.addView(actions)
    }

    private fun renderError(ctx: Context, message: String) {
        cancelAnimators()
        val c = card ?: return
        c.removeAllViews()
        c.orientation = LinearLayout.HORIZONTAL
        c.gravity = Gravity.CENTER_VERTICAL

        val text = TextView(ctx).apply {
            this.text = message
            setTextColor(Color.WHITE)
            textSize = 13f
            layoutParams = LinearLayout.LayoutParams(
                0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f
            )
        }
        val retry = secondaryButton(ctx, "↻  Retry") {
            onRetryTapped(ctx)
        }
        val cancel = cancelChip(ctx) { onCancelTapped(ctx) }

        c.addView(text)
        c.addView(retry.apply {
            (layoutParams as LinearLayout.LayoutParams).marginStart = dp(ctx, 8)
        })
        c.addView(cancel)
    }

    // ───────── Phase transitions / actions ─────────

    private fun onStopTapped(ctx: Context) {
        val path = stopRecording(ctx) ?: run {
            renderError(ctx, "No audio captured.")
            return
        }
        renderPolishing(ctx)
        runMagicAsync(ctx, File(path))
    }

    private fun onCancelTapped(ctx: Context) {
        stopRecording(ctx)
        discardAudio()
        DebugLog.log(ctx, "NativeOverlay", "Cancel tapped → close overlay")
        hideAnimated(null)
    }

    private fun onRetryTapped(ctx: Context) {
        discardAudio()
        // Restore card to horizontal recording layout.
        val c = card ?: return
        c.orientation = LinearLayout.HORIZONTAL
        c.gravity = Gravity.CENTER_VERTICAL
        c.setPadding(dp(ctx, 16), dp(ctx, 14), dp(ctx, 12), dp(ctx, 14))
        renderRecording(ctx)
        startRecording(ctx)
    }

    private fun onInsertTapped(ctx: Context, text: String) {
        DebugLog.log(ctx, "NativeOverlay", "Insert tapped (${text.length} chars)")
        val a11y = VoiceBubbleA11yService.getInstance()
        val injected = a11y?.setFocusedFieldText(text) ?: false
        if (!injected) {
            // Fallback: copy to clipboard so user can paste manually.
            val cm = ctx.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
            cm?.setPrimaryClip(ClipData.newPlainText("VoiceBubble", text))
            Toast.makeText(
                ctx,
                "Copied — paste it where you need.",
                Toast.LENGTH_SHORT
            ).show()
            DebugLog.log(ctx, "NativeOverlay", "Insert failed → clipboard fallback")
        } else {
            DebugLog.log(ctx, "NativeOverlay", "Insert success via A11y")
        }
        hideAnimated(null)
    }

    private fun runMagicAsync(ctx: Context, audio: File) {
        val main = Handler(Looper.getMainLooper())
        Thread {
            try {
                val transcript = BackendClient.transcribe(ctx, audio)
                if (transcript.isBlank()) {
                    main.post { renderError(ctx, "No speech detected.") }
                    return@Thread
                }
                val magic = BackendClient.rewriteMagic(ctx, transcript)
                val finalText = magic.text.ifBlank { transcript }
                main.post { renderResult(ctx, finalText, magic.label) }
            } catch (e: Throwable) {
                Log.e(TAG, "Magic flow failed", e)
                DebugLog.log(
                    ctx,
                    "NativeOverlay",
                    "Magic threw: ${e.javaClass.simpleName} ${e.message}"
                )
                main.post {
                    renderError(
                        ctx,
                        "Polish failed — check your connection."
                    )
                }
            }
        }.start()
    }

    // ───────── View building blocks ─────────

    private fun buildCardShell(ctx: Context): LinearLayout {
        return LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(
                dp(ctx, 16), dp(ctx, 14), dp(ctx, 12), dp(ctx, 14)
            )
            background = GradientDrawable().apply {
                cornerRadius = dp(ctx, 28).toFloat()
                setColor(Color.parseColor("#E10D0D1A"))
                setStroke(1, Color.parseColor("#14FFFFFF"))
            }
            elevation = dp(ctx, 18).toFloat()
            layoutParams = FrameLayout.LayoutParams(
                dp(ctx, 320),
                FrameLayout.LayoutParams.WRAP_CONTENT
            )
        }
    }

    private fun cancelChip(ctx: Context, onTap: () -> Unit): TextView {
        return TextView(ctx).apply {
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
            setOnClickListener { onTap() }
        }
    }

    private fun secondaryButton(ctx: Context, label: String, onTap: () -> Unit): TextView {
        return TextView(ctx).apply {
            text = label
            setTextColor(Color.parseColor("#CCFFFFFF"))
            textSize = 13f
            typeface = android.graphics.Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            setPadding(dp(ctx, 12), dp(ctx, 8), dp(ctx, 12), dp(ctx, 8))
            background = GradientDrawable().apply {
                cornerRadius = dp(ctx, 16).toFloat()
                setColor(Color.parseColor("#10FFFFFF"))
            }
            isClickable = true
            isFocusable = true
            setOnClickListener { onTap() }
        }
    }

    private fun primaryInsertButton(ctx: Context, onTap: () -> Unit): TextView {
        return TextView(ctx).apply {
            text = "Insert  ›"
            setTextColor(Color.WHITE)
            textSize = 14f
            typeface = android.graphics.Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            setPadding(dp(ctx, 18), dp(ctx, 10), dp(ctx, 18), dp(ctx, 10))
            background = GradientDrawable().apply {
                cornerRadius = dp(ctx, 20).toFloat()
                setColor(Color.parseColor("#7C6AE8"))
            }
            elevation = dp(ctx, 6).toFloat()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                outlineSpotShadowColor = Color.parseColor("#7C6AE8")
                outlineAmbientShadowColor = Color.parseColor("#7C6AE8")
            }
            isClickable = true
            isFocusable = true
            setOnClickListener {
                animate().scaleX(0.94f).scaleY(0.94f).setDuration(80).withEndAction {
                    animate().scaleX(1f).scaleY(1f).setDuration(120).start()
                    onTap()
                }.start()
            }
        }
    }

    /** A 22dp purple ring spinner, centered in a `size`-dp circle slot. */
    private fun buildSpinnerCircle(ctx: Context, slotSize: Int): View {
        val ring = TextView(ctx).apply {
            text = ""
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setStroke(dp(ctx, 2), Color.parseColor("#7C6AE8"))
                setColor(Color.TRANSPARENT)
            }
            val s = dp(ctx, 22)
            layoutParams = LinearLayout.LayoutParams(s, s)
        }
        val rotator = ValueAnimator.ofFloat(0f, 360f).apply {
            duration = 900
            repeatCount = ValueAnimator.INFINITE
            interpolator = LinearInterpolator()
            addUpdateListener { ring.rotation = it.animatedValue as Float }
        }
        rotator.start()
        animators.add(rotator)
        val container = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(slotSize, slotSize)
        }
        container.addView(ring)
        return container
    }

    // ───────── Animations ─────────

    private fun startBreathingAlpha(
        target: View,
        from: Float,
        to: Float,
        durationMs: Long,
        delayMs: Long = 0L,
    ) {
        val a = ValueAnimator.ofFloat(from, to).apply {
            duration = durationMs
            startDelay = delayMs
            repeatMode = ValueAnimator.REVERSE
            repeatCount = ValueAnimator.INFINITE
            interpolator = PathInterpolator(0.4f, 0f, 0.6f, 1f)
            addUpdateListener { target.alpha = it.animatedValue as Float }
        }
        a.start()
        animators.add(a)
    }

    private fun startBreathingScale(
        target: View,
        from: Float,
        to: Float,
        durationMs: Long,
    ) {
        val a = ValueAnimator.ofFloat(from, to).apply {
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

    // ───────── Helpers ─────────

    private fun dp(ctx: Context, value: Int): Int =
        (value * ctx.resources.displayMetrics.density).toInt()

    /**
     * Idempotent — flips the SharedPreferences flag the first time
     * a bubble recording starts, no-op every time after. The Dart
     * UsageService picks this up on its next read of
     * [hasClaimedBubbleFirstUseBonus] and adds 5 free minutes to
     * the user's limit.
     */
    private fun grantBubbleFirstUseBonusIfNew(ctx: Context) {
        try {
            val prefs = ctx.applicationContext
                .getSharedPreferences(
                    "FlutterSharedPreferences",
                    Context.MODE_PRIVATE
                )
            val key = "flutter.bubble_first_use_bonus_claimed"
            if (prefs.getBoolean(key, false)) return
            prefs.edit().putBoolean(key, true).apply()
            DebugLog.log(ctx, "Reward", "Bubble-first-use bonus granted (5 min)")
        } catch (e: Throwable) {
            DebugLog.log(
                ctx,
                "Reward",
                "Failed to grant bubble bonus: ${e.javaClass.simpleName} ${e.message}"
            )
        }
    }
}
