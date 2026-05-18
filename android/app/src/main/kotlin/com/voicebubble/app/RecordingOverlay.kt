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
import android.view.HapticFeedbackConstants
import android.view.View
import android.view.WindowManager
import android.view.animation.LinearInterpolator
import android.view.animation.PathInterpolator
import android.widget.FrameLayout
import android.widget.HorizontalScrollView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import java.io.File

/**
 * Pure-native floating overlay built around two intentionally
 * different shapes:
 *
 *   RECORDING / POLISHING — a *small* compact pill (~200dp wide,
 *     56dp tall). Quiet, doesn't dominate the screen. Just enough
 *     to confirm capture is happening + give the user a stop tap
 *     target.
 *
 *   RESULT — the *elite panel*. Wider (340dp), vertical, generous
 *     typography, intent badge, preset re-rewrite chips
 *     (Magic / Reply / Email / Social — tap to re-render the same
 *     audio in a different tone without re-recording), and a
 *     bottom action row with Retry, Copy and the primary Insert
 *     button. This is the main event the user came for.
 *
 * Same underlying primitive everywhere: `WindowManager.addView` of
 * a plain Android view. No Flutter engine, no plugin, no isolate.
 *
 * Insert routes through [VoiceBubbleA11yService.setFocusedFieldText]
 * so the AI text drops directly into the focused EditText of
 * whatever app is in the foreground; falls back to clipboard when
 * accessibility isn't enabled / no editable focus.
 */
object RecordingOverlay {

    private const val TAG = "RecordingOverlay"

    // ───────── State ─────────

    private var view: View? = null
    private var card: LinearLayout? = null
    private var ctxRef: Context? = null
    private var wm: WindowManager? = null
    private var windowParams: WindowManager.LayoutParams? = null

    private var recorder: MediaRecorder? = null
    private var audioFile: File? = null
    private var ampHandler: Handler? = null
    private var ampPoll: Runnable? = null
    private var waveform: WaveformView? = null

    /** Last successful transcript — re-used by preset chips so they
     *  don't have to re-transcribe the audio when re-rewriting. */
    private var lastTranscript: String? = null
    private var activePresetId: String = "magic"

    private val animators = mutableListOf<ValueAnimator>()

    fun isShowing(): Boolean = view != null

    // ───────── Public API ─────────

    fun show(ctx: Context) {
        if (view != null) return

        val appCtx = ctx.applicationContext
        ctxRef = appCtx
        lastTranscript = null
        activePresetId = "magic"

        val windowManager =
            appCtx.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        wm = windowManager

        val container = FrameLayout(appCtx)
        val cardView = buildCardShell(appCtx, widthDp = 200)
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

        // Blur is OFF during recording so the user can read the
        // message they're replying to. We only turn it on when we
        // morph into the result panel (the "main event") — kept in
        // sync via [setBlurEnabled].
        windowParams = params

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

    /**
     * Toggle FLAG_BLUR_BEHIND on the live overlay window. Blur is
     * ON for the result panel (premium focus on the AI text), OFF
     * for the recording / polishing pill (so the user can read the
     * message they're responding to while speaking).
     */
    private fun setBlurEnabled(enabled: Boolean) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return
        val v = view ?: return
        val windowManager = wm ?: return
        val params = windowParams ?: return
        val currentlyOn = (params.flags and
            WindowManager.LayoutParams.FLAG_BLUR_BEHIND) != 0
        if (enabled == currentlyOn) return
        params.flags = if (enabled) {
            params.flags or WindowManager.LayoutParams.FLAG_BLUR_BEHIND
        } else {
            params.flags and WindowManager.LayoutParams.FLAG_BLUR_BEHIND.inv()
        }
        params.blurBehindRadius = if (enabled) 28 else 0
        try { windowManager.updateViewLayout(v, params) } catch (_: Throwable) {}
    }

    private fun cancelAnimators() {
        for (a in animators) try { a.cancel() } catch (_: Throwable) {}
        animators.clear()
    }

    // ───────── MediaRecorder lifecycle ─────────

    private fun startRecording(ctx: Context) {
        try {
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

    /** Compact 200dp pill — small waveform + stop + cancel. */
    private fun renderRecording(ctx: Context) {
        cancelAnimators()
        // Recording: no blur — user is reading the message they're
        // replying to while speaking.
        setBlurEnabled(false)
        resizeCard(ctx, widthDp = 200)
        val c = card ?: return
        c.orientation = LinearLayout.HORIZONTAL
        c.gravity = Gravity.CENTER_VERTICAL
        c.setPadding(dp(ctx, 14), dp(ctx, 10), dp(ctx, 10), dp(ctx, 10))
        c.removeAllViews()

        val recDot = View(ctx).apply {
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.parseColor("#FF3B30"))
            }
            val s = dp(ctx, 6)
            layoutParams = LinearLayout.LayoutParams(s, s).apply {
                marginEnd = dp(ctx, 8)
            }
            alpha = 0.4f
        }
        startBreathingAlpha(recDot, 0.35f, 1f, 800)

        val wave = WaveformView(ctx).apply {
            layoutParams = LinearLayout.LayoutParams(
                0, dp(ctx, 28), 1f
            )
        }
        waveform = wave

        val stop = TextView(ctx).apply {
            text = "■"
            setTextColor(Color.WHITE)
            textSize = 13f
            gravity = Gravity.CENTER
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.parseColor("#7C6AE8"))
            }
            elevation = dp(ctx, 6).toFloat()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                outlineSpotShadowColor = Color.parseColor("#7C6AE8")
                outlineAmbientShadowColor = Color.parseColor("#7C6AE8")
            }
            val size = dp(ctx, 40)
            layoutParams = LinearLayout.LayoutParams(size, size).apply {
                marginStart = dp(ctx, 10)
            }
            isClickable = true
            isFocusable = true
            setOnClickListener {
                animate().scaleX(0.9f).scaleY(0.9f).setDuration(70).withEndAction {
                    animate().scaleX(1f).scaleY(1f).setDuration(110).start()
                    onStopTapped(ctx)
                }.start()
            }
        }
        startBreathingScale(stop, 0.97f, 1f, 1500)

        val cancel = compactCancelChip(ctx) { onCancelTapped(ctx) }

        c.addView(recDot)
        c.addView(wave)
        c.addView(stop)
        c.addView(cancel)
    }

    /** Same compact 200dp pill — three breathing dots + ring spinner. */
    private fun renderPolishing(ctx: Context) {
        cancelAnimators()
        resizeCard(ctx, widthDp = 200)
        val c = card ?: return
        c.orientation = LinearLayout.HORIZONTAL
        c.gravity = Gravity.CENTER_VERTICAL
        c.setPadding(dp(ctx, 14), dp(ctx, 10), dp(ctx, 10), dp(ctx, 10))
        c.removeAllViews()

        val dotsRow = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(0, dp(ctx, 28), 1f)
        }
        for (i in 0 until 3) {
            val dot = View(ctx).apply {
                background = GradientDrawable().apply {
                    shape = GradientDrawable.OVAL
                    setColor(Color.parseColor("#7C6AE8"))
                }
                val s = dp(ctx, 7)
                layoutParams = LinearLayout.LayoutParams(s, s).apply {
                    marginStart = dp(ctx, 5)
                    marginEnd = dp(ctx, 5)
                }
                alpha = 0.3f
            }
            dotsRow.addView(dot)
            startBreathingAlpha(dot, 0.25f, 1f, 800, delayMs = (i * 180L))
        }

        val spinner = buildSpinnerCircle(ctx, dp(ctx, 40))
        (spinner.layoutParams as LinearLayout.LayoutParams).marginStart = dp(ctx, 10)

        val cancel = compactCancelChip(ctx) { onCancelTapped(ctx) }

        c.addView(dotsRow)
        c.addView(spinner)
        c.addView(cancel)
    }

    /**
     * The elite result panel. 340dp wide, vertical layout:
     *   intent badge + ✕
     *   AI text (scrollable if long)
     *   preset re-rewrite chips
     *   action row: Retry / Copy / Insert
     */
    private fun renderResult(ctx: Context, text: String, label: String?) {
        cancelAnimators()
        // Result panel: blur ON — focus the user's eyes on the AI
        // text. The underlying app stays legible behind the blur
        // but recedes.
        setBlurEnabled(true)
        resizeCard(ctx, widthDp = 340)
        val c = card ?: return
        c.orientation = LinearLayout.VERTICAL
        c.gravity = Gravity.START
        c.setPadding(dp(ctx, 18), dp(ctx, 16), dp(ctx, 18), dp(ctx, 16))
        c.removeAllViews()

        // Top: intent badge + close
        val topRow = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
        }
        val badge = TextView(ctx).apply {
            this.text = (label?.uppercase() ?: presetLabelFor(activePresetId).uppercase())
            setTextColor(Color.parseColor("#7C6AE8"))
            textSize = 10f
            letterSpacing = 0.18f
            typeface = android.graphics.Typeface.DEFAULT_BOLD
            layoutParams = LinearLayout.LayoutParams(
                0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f
            )
        }
        val cancelChip = compactCancelChip(ctx) { onCancelTapped(ctx) }
        topRow.addView(badge)
        topRow.addView(cancelChip)
        c.addView(topRow)

        // Body — generous typography. Scrollable if long, capped to
        // a height that keeps the panel reasonable.
        val bodyText = text.ifBlank { "(no text)" }
        val body = TextView(ctx).apply {
            this.text = bodyText
            setTextColor(Color.WHITE)
            // 15sp at 1.45 line height — comfortably readable, fits
            // ~10 lines into the panel before scroll engages.
            textSize = 15f
            setLineSpacing(0f, 1.45f)
        }
        val scroll = ScrollView(ctx).apply {
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                topMargin = dp(ctx, 12)
                bottomMargin = dp(ctx, 14)
            }
            isFillViewport = false
            // Hard cap so a giant rewrite doesn't push the panel
            // off-screen — but big enough that a typical email
            // / reply fits without ever needing to scroll.
            val maxBodyDp = dp(ctx, 320)
            layoutParams.height = LinearLayout.LayoutParams.WRAP_CONTENT
            body.maxHeight = maxBodyDp
            isVerticalScrollBarEnabled = false
            overScrollMode = View.OVER_SCROLL_NEVER
            addView(body)
        }
        c.addView(scroll)

        // Preset re-rewrite chips — tap to re-render same recording
        // in a different tone using the cached transcript.
        val chipsScroll = HorizontalScrollView(ctx).apply {
            isHorizontalScrollBarEnabled = false
            overScrollMode = View.OVER_SCROLL_NEVER
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { bottomMargin = dp(ctx, 14) }
        }
        val chipsRow = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        for (preset in PRESETS) {
            chipsRow.addView(presetChip(ctx, preset) {
                onPresetTapped(ctx, it)
            })
        }
        chipsScroll.addView(chipsRow)
        c.addView(chipsScroll)

        // Bottom action row: Retry · Copy · [Insert]
        val actions = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
        }
        val retry = secondaryButton(ctx, "↻  Retry") { onRetryTapped(ctx) }
        val gap1 = View(ctx).apply {
            layoutParams = LinearLayout.LayoutParams(dp(ctx, 8), 1)
        }
        val copy = secondaryButton(ctx, "⧉  Copy") {
            copyToClipboard(ctx, bodyText)
            Toast.makeText(ctx, "Copied", Toast.LENGTH_SHORT).show()
            hideAnimated(null)
        }
        val spacer = View(ctx).apply {
            layoutParams = LinearLayout.LayoutParams(0, 1, 1f)
        }
        val insert = primaryInsertButton(ctx) { onInsertTapped(ctx, bodyText) }
        actions.addView(retry)
        actions.addView(gap1)
        actions.addView(copy)
        actions.addView(spacer)
        actions.addView(insert)
        c.addView(actions)
    }

    private fun renderError(ctx: Context, message: String) {
        cancelAnimators()
        resizeCard(ctx, widthDp = 280)
        val c = card ?: return
        c.orientation = LinearLayout.HORIZONTAL
        c.gravity = Gravity.CENTER_VERTICAL
        c.setPadding(dp(ctx, 14), dp(ctx, 10), dp(ctx, 10), dp(ctx, 10))
        c.removeAllViews()

        val text = TextView(ctx).apply {
            this.text = message
            setTextColor(Color.WHITE)
            textSize = 13f
            layoutParams = LinearLayout.LayoutParams(
                0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f
            )
        }
        val retry = secondaryButton(ctx, "↻  Retry") { onRetryTapped(ctx) }
        val cancel = compactCancelChip(ctx) { onCancelTapped(ctx) }

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
        lastTranscript = null
        activePresetId = "magic"
        renderRecording(ctx)
        startRecording(ctx)
    }

    private fun onInsertTapped(ctx: Context, text: String) {
        DebugLog.log(ctx, "NativeOverlay", "Insert tapped (${text.length} chars)")
        val a11y = VoiceBubbleA11yService.getInstance()
        val injected = a11y?.setFocusedFieldText(text) ?: false
        if (!injected) {
            copyToClipboard(ctx, text)
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

    private fun onPresetTapped(ctx: Context, preset: PresetSpec) {
        if (preset.id == activePresetId) return
        val transcript = lastTranscript ?: return
        activePresetId = preset.id
        renderPolishing(ctx)
        val main = Handler(Looper.getMainLooper())
        Thread {
            try {
                val res = BackendClient.rewriteWithPreset(ctx, transcript, preset.id)
                val finalText = res.text.ifBlank { transcript }
                main.post { renderResult(ctx, finalText, res.label ?: preset.label) }
            } catch (e: Throwable) {
                DebugLog.log(
                    ctx,
                    "NativeOverlay",
                    "Preset re-rewrite [${preset.id}] threw: ${e.message}"
                )
                main.post { renderError(ctx, "Could not re-style. Check connection.") }
            }
        }.start()
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
                lastTranscript = transcript
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
                    renderError(ctx, "Polish failed — check your connection.")
                }
            }
        }.start()
    }

    private fun copyToClipboard(ctx: Context, text: String) {
        val cm = ctx.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
        cm?.setPrimaryClip(ClipData.newPlainText("VoiceBubble", text))
    }

    // ───────── View building blocks ─────────

    private fun buildCardShell(ctx: Context, widthDp: Int): LinearLayout {
        return LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(
                dp(ctx, 14), dp(ctx, 10), dp(ctx, 10), dp(ctx, 10)
            )
            background = GradientDrawable().apply {
                cornerRadius = dp(ctx, 24).toFloat()
                setColor(Color.parseColor("#E10D0D1A"))
                setStroke(1, Color.parseColor("#14FFFFFF"))
            }
            elevation = dp(ctx, 18).toFloat()
            layoutParams = FrameLayout.LayoutParams(
                dp(ctx, widthDp),
                FrameLayout.LayoutParams.WRAP_CONTENT
            )
        }
    }

    /**
     * Re-size the card in place (no remount) so morphing between
     * the small recording pill and the wider result panel happens
     * smoothly via WindowManager's natural relayout.
     */
    private fun resizeCard(ctx: Context, widthDp: Int) {
        val c = card ?: return
        val lp = c.layoutParams as FrameLayout.LayoutParams
        lp.width = dp(ctx, widthDp)
        c.layoutParams = lp
        // Bigger panels deserve bigger corners.
        (c.background as? GradientDrawable)?.cornerRadius = dp(
            ctx, if (widthDp >= 320) 28 else 24
        ).toFloat()
    }

    private fun compactCancelChip(ctx: Context, onTap: () -> Unit): TextView {
        return TextView(ctx).apply {
            text = "✕"
            setTextColor(Color.parseColor("#CCFFFFFF"))
            textSize = 12f
            gravity = Gravity.CENTER
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.parseColor("#10FFFFFF"))
            }
            val size = dp(ctx, 26)
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
            textSize = 12.5f
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

    private fun presetChip(
        ctx: Context,
        preset: PresetSpec,
        onTap: (PresetSpec) -> Unit,
    ): TextView {
        val active = preset.id == activePresetId
        return TextView(ctx).apply {
            text = "${preset.icon}  ${preset.label}"
            setTextColor(
                if (active) Color.WHITE else Color.parseColor("#BFFFFFFF")
            )
            textSize = 12f
            typeface = android.graphics.Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            setPadding(dp(ctx, 12), dp(ctx, 7), dp(ctx, 12), dp(ctx, 7))
            background = GradientDrawable().apply {
                cornerRadius = dp(ctx, 14).toFloat()
                if (active) {
                    setColor(Color.parseColor("#7C6AE8"))
                } else {
                    setColor(Color.parseColor("#10FFFFFF"))
                    setStroke(1, Color.parseColor("#22FFFFFF"))
                }
            }
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { marginEnd = dp(ctx, 8) }
            isClickable = true
            isFocusable = true
            setOnClickListener {
                performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
                onTap(preset)
            }
        }
    }

    private fun buildSpinnerCircle(ctx: Context, slotSize: Int): View {
        val ring = TextView(ctx).apply {
            text = ""
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setStroke(dp(ctx, 2), Color.parseColor("#7C6AE8"))
                setColor(Color.TRANSPARENT)
            }
            val s = dp(ctx, 20)
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

    // ───────── Preset specs (server presetIds) ─────────

    private data class PresetSpec(
        val id: String,
        val label: String,
        val icon: String,
    )

    private val PRESETS = listOf(
        PresetSpec("magic", "Magic", "✨"),
        PresetSpec("quick_reply", "Reply", "💬"),
        PresetSpec("email_professional", "Email", "✉️"),
        PresetSpec("instagram_caption", "Social", "🔥"),
    )

    private fun presetLabelFor(id: String): String =
        PRESETS.firstOrNull { it.id == id }?.label ?: "Magic"
}
