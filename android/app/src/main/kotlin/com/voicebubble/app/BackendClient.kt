package com.voicebubble.app

import android.content.Context
import android.util.Log
import org.json.JSONObject
import java.io.DataOutputStream
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

/**
 * Pure-native client for the existing VoiceBubble backend so the
 * recording overlay can transcribe + rewrite without going through
 * a Dart isolate. Same endpoints the Dart `AIService` hits, just
 * wrapped in HttpURLConnection so we have zero plugin / Flutter
 * indirection in the bubble's hot path.
 *
 *   POST /api/transcribe          multipart "audio"            → {"text": "..."}
 *   POST /api/rewrite/batch       json {text, presetId, language} → {"text": "...", "label": "..."}
 *
 * All calls are synchronous. Caller is responsible for running
 * them off the main thread (RecordingOverlay uses a plain
 * `Thread { ... }` and posts UI updates back via Handler).
 */
object BackendClient {
    private const val TAG = "BackendClient"
    private const val BASE_URL = "https://voicebubble-production.up.railway.app"
    private const val CONNECT_TIMEOUT_MS = 30_000
    private const val READ_TIMEOUT_MS = 60_000

    data class MagicResult(val text: String, val label: String?)

    /**
     * Upload an audio file to the transcribe endpoint, return the
     * extracted text. Throws on network / non-200.
     */
    fun transcribe(ctx: Context, audioFile: File): String {
        val boundary = "----VoiceBubble${System.currentTimeMillis()}"
        val conn = (URL("$BASE_URL/api/transcribe").openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            doOutput = true
            useCaches = false
            connectTimeout = CONNECT_TIMEOUT_MS
            readTimeout = READ_TIMEOUT_MS
            setRequestProperty(
                "Content-Type",
                "multipart/form-data; boundary=$boundary"
            )
        }

        try {
            DataOutputStream(conn.outputStream).use { out ->
                out.writeBytes("--$boundary\r\n")
                out.writeBytes(
                    "Content-Disposition: form-data; name=\"audio\"; filename=\"${audioFile.name}\"\r\n"
                )
                out.writeBytes("Content-Type: audio/mp4\r\n\r\n")
                audioFile.inputStream().use { it.copyTo(out) }
                out.writeBytes("\r\n--$boundary--\r\n")
                out.flush()
            }

            val code = conn.responseCode
            if (code !in 200..299) {
                val err = conn.errorStream?.bufferedReader()?.readText().orEmpty()
                throw RuntimeException("transcribe HTTP $code: $err")
            }
            val body = conn.inputStream.bufferedReader().readText()
            val text = JSONObject(body).optString("text", "")
            DebugLog.log(ctx, "Backend", "Transcribe ok (${text.length} chars)")
            return text
        } finally {
            conn.disconnect()
        }
    }

    /**
     * Run the Magic preset on the transcript, return the polished
     * text + (optional) human-readable intent label.
     */
    fun rewriteMagic(ctx: Context, text: String, language: String = "en"): MagicResult {
        val conn = (URL("$BASE_URL/api/rewrite/batch").openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            doOutput = true
            useCaches = false
            connectTimeout = CONNECT_TIMEOUT_MS
            readTimeout = READ_TIMEOUT_MS
            setRequestProperty("Content-Type", "application/json; charset=utf-8")
        }

        try {
            val body = JSONObject().apply {
                put("text", text)
                put("presetId", "magic")
                put("language", language)
            }.toString()
            conn.outputStream.use { it.write(body.toByteArray(Charsets.UTF_8)) }

            val code = conn.responseCode
            if (code !in 200..299) {
                val err = conn.errorStream?.bufferedReader()?.readText().orEmpty()
                throw RuntimeException("rewrite HTTP $code: $err")
            }
            val responseBody = conn.inputStream.bufferedReader().readText()
            val json = JSONObject(responseBody)
            val polished = json.optString("text", "")
            val label = json.optString("label").takeIf { it.isNotBlank() }
            DebugLog.log(
                ctx,
                "Backend",
                "Rewrite ok (label=$label, ${polished.length} chars)"
            )
            return MagicResult(text = polished, label = label)
        } finally {
            conn.disconnect()
        }
    }
}
