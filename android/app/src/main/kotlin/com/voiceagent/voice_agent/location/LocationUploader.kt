package com.voiceagent.voice_agent.location

import android.content.Context
import java.net.HttpURLConnection
import java.net.URL
import java.time.Instant
import java.util.concurrent.locks.ReentrantLock
import org.json.JSONArray
import org.json.JSONObject

/**
 * Sends the oldest queued rows. Rows leave the queue only after personal-agent
 * has answered for them, and a repeat is harmless because each row carries its
 * own id. Never touches the transcript sync queue.
 */
class LocationUploader(private val context: Context) {
    enum class Outcome { DONE, MORE, FAILED }

    fun sendBatch(): Outcome {
        if (!lock.tryLock()) return Outcome.MORE
        try {
            return send()
        } finally {
            lock.unlock()
        }
    }

    private fun send(): Outcome {
        val store = LocationStore.get(context)
        val config = LocationConfig(context)
        val batch = store.oldest(BATCH_SIZE)
        if (batch.isEmpty()) return Outcome.DONE
        val base = config.serverUrl
        if (base.isNullOrBlank()) return failed(config, "no server URL")

        val result = try {
            post(base.trimEnd('/') + PATH, config.token, batch)
        } catch (failure: Exception) {
            return failed(config, failure.toString())
        }
        if (result.first !in 200..299) return failed(config, "HTTP ${result.first}")

        store.delete(batch.map { it.id })
        config.lastSentAtMs = System.currentTimeMillis()
        config.lastError = null
        val rejected = try {
            JSONObject(result.second).optJSONObject("data")?.optJSONArray("rejected")?.length() ?: 0
        } catch (_: Exception) {
            0
        }
        if (rejected > 0) {
            // Refused for good: kept out of the queue, and the log says so.
            LocationPipeline.recordStatus(context, "rejected", "$rejected rows refused by the server")
        }
        return if (store.count() > 0) Outcome.MORE else Outcome.DONE
    }

    private fun failed(config: LocationConfig, reason: String): Outcome {
        config.lastError = "${Instant.now()}: $reason"
        return Outcome.FAILED
    }

    private fun post(url: String, token: String?, batch: List<LogEntry>): Pair<Int, String> {
        val body = JSONObject().put("entries", JSONArray(batch.map { it.json })).toString().toByteArray()
        val connection = URL(url).openConnection() as HttpURLConnection
        try {
            connection.requestMethod = "POST"
            connection.connectTimeout = TIMEOUT_MS
            connection.readTimeout = TIMEOUT_MS
            connection.doOutput = true
            connection.setRequestProperty("Content-Type", "application/json")
            if (!token.isNullOrEmpty()) connection.setRequestProperty("Authorization", "Bearer $token")
            connection.outputStream.use { it.write(body) }
            val code = connection.responseCode
            val text = if (code in 200..299) {
                connection.inputStream.bufferedReader().use { it.readText() }
            } else {
                ""
            }
            return code to text
        } finally {
            connection.disconnect()
        }
    }

    companion object {
        private const val PATH = "/location/entries"
        private const val BATCH_SIZE = 200
        private const val TIMEOUT_MS = 6_000
        private val lock = ReentrantLock()
    }
}
