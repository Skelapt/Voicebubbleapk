package com.voicebubble.app

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.util.AttributeSet
import android.view.View

/**
 * Live waveform view: a row of vertical bars whose heights track
 * recent microphone amplitude readings. New samples push in from
 * the right, oldest fall off the left — the same shape the Dart
 * recording pill had, but drawn natively so we don't depend on a
 * Flutter engine.
 */
class WaveformView @JvmOverloads constructor(
    ctx: Context,
    attrs: AttributeSet? = null,
) : View(ctx, attrs) {

    private val barCount = 24
    private val levels = FloatArray(barCount) { 0.18f }

    private val barPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#7C6AE8") // brand purple
        style = Paint.Style.FILL
    }

    /** Push a new amplitude in 0..1, will be clamped + drawn. */
    fun pushAmplitude(normalized: Float) {
        val clamped = normalized.coerceIn(0.12f, 1.0f)
        for (i in 0 until barCount - 1) {
            levels[i] = levels[i + 1]
        }
        levels[barCount - 1] = clamped
        invalidate()
    }

    fun reset() {
        for (i in 0 until barCount) levels[i] = 0.18f
        invalidate()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val w = width.toFloat()
        val h = height.toFloat()
        if (w <= 0f || h <= 0f) return

        val barW = w / (barCount * 1.6f)
        val gap = (w - barW * barCount) / (barCount - 1)
        for (i in 0 until barCount) {
            val barH = levels[i] * h
            val x = i * (barW + gap)
            val y = (h - barH) / 2f
            // Subtle gradient of opacity left→right so the leading
            // edge of new sound feels brightest.
            barPaint.alpha = (255 * (0.55f + 0.45f * (i.toFloat() / barCount))).toInt()
            val rect = RectF(x, y, x + barW, y + barH)
            canvas.drawRoundRect(rect, barW / 2f, barW / 2f, barPaint)
        }
    }
}
