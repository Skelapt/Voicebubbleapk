package com.voicebubble.app

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Shader
import android.util.AttributeSet
import android.view.View

/**
 * Mirrored oscilloscope waveform — bars grow from the horizontal
 * centerline outward (up + down), not from the floor up. Reads as
 * "live audio" the way Apple Voice Memos does, far more premium
 * than a row of floor-anchored bars.
 *
 * Smooth-interpolated: each new amplitude sample eases toward its
 * target value over a few frames so the wave breathes rather than
 * jitters when the mic levels jump.
 */
class WaveformView @JvmOverloads constructor(
    ctx: Context,
    attrs: AttributeSet? = null,
) : View(ctx, attrs) {

    private val barCount = 32
    private val targets = FloatArray(barCount) { 0.10f }
    private val current = FloatArray(barCount) { 0.10f }

    private val barPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
    }

    private var gradientShader: Shader? = null
    private var lastWidth = 0
    private var lastHeight = 0

    /** Push a new amplitude in 0..1 — clamps to a visible minimum. */
    fun pushAmplitude(normalized: Float) {
        val clamped = normalized.coerceIn(0.10f, 1.0f)
        // Shift left, append on right.
        for (i in 0 until barCount - 1) {
            targets[i] = targets[i + 1]
        }
        targets[barCount - 1] = clamped
        invalidate()
    }

    fun reset() {
        for (i in 0 until barCount) {
            targets[i] = 0.10f
            current[i] = 0.10f
        }
        invalidate()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val w = width.toFloat()
        val h = height.toFloat()
        if (w <= 0f || h <= 0f) return

        // Rebuild gradient if size changed — left side fades to ~50%
        // alpha, right side full. Adds the "leading edge is brightest"
        // depth cue.
        if (w.toInt() != lastWidth || h.toInt() != lastHeight) {
            lastWidth = w.toInt()
            lastHeight = h.toInt()
            gradientShader = LinearGradient(
                0f, 0f, w, 0f,
                intArrayOf(
                    Color.parseColor("#557C6AE8"), // 33% alpha
                    Color.parseColor("#FF7C6AE8"), // full
                ),
                floatArrayOf(0f, 1f),
                Shader.TileMode.CLAMP
            )
            barPaint.shader = gradientShader
        }

        val barW = w / (barCount * 1.7f)
        val gap = (w - barW * barCount) / (barCount - 1)
        val center = h / 2f

        for (i in 0 until barCount) {
            // Smooth-interpolate current toward target so the wave
            // glides instead of snapping.
            current[i] += (targets[i] - current[i]) * 0.35f

            val barH = current[i] * h
            val x = i * (barW + gap)
            val top = center - barH / 2f
            val bottom = center + barH / 2f
            val rect = RectF(x, top, x + barW, bottom)
            canvas.drawRoundRect(rect, barW / 2f, barW / 2f, barPaint)
        }

        // Always invalidate while interpolation is still settling —
        // cheap to do, pays off in smoothness.
        var settling = false
        for (i in 0 until barCount) {
            if (Math.abs(current[i] - targets[i]) > 0.005f) {
                settling = true
                break
            }
        }
        if (settling) postInvalidateOnAnimation()
    }
}
