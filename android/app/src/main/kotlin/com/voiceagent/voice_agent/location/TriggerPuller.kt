package com.voiceagent.voice_agent.location

import android.content.Context
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Callable
import java.util.concurrent.Executors
import java.util.concurrent.Future
import java.util.concurrent.TimeUnit
import org.json.JSONObject

/**
 * Pulls the armed triggers, `GET /api/v1/triggers` (ADR-NET-007): every hour
 * from a job, at app start, when the switch goes on, and on a return to the
 * app at most once per 5 minutes. Only while "Alerty w sklepach" is on.
 *
 * The request runs on its own thread, so a slow server never holds a
 * registration; the set it brings is stored and registered on the registry's
 * thread. A pull that fails keeps the set last pulled: the phone fires from it
 * offline, and the triggers' expiry bounds how old it may be.
 */
object TriggerPuller {
    enum class Outcome { OFF, CHANGED, UNCHANGED, FAILED }

    const val REASON_JOB = "hourly"
    const val REASON_APP_START = "app_start"
    const val REASON_SWITCH = "switch"
    const val REASON_RESUMED = "app_resumed"

    private val thread = Executors.newSingleThreadExecutor()

    private const val PATH = "/triggers"
    private const val WORK = "triggers-pull"
    private const val TIMEOUT_MS = 6_000
    private const val RETURN_MIN_INTERVAL_MS = 5 * 60_000L
    private const val WAIT_REGISTRY_S = 60L

    /** The status of a reply that is not personal-agent's set. */
    private const val CODE_BAD_BODY = -3
    private const val CODE_NO_URL = -4
    private const val CODE_NETWORK = -5

    fun pullLater(context: Context, reason: String) {
        thread.execute { pullNow(context.applicationContext, reason) }
    }

    /** For the hourly job. */
    fun pullAndWait(context: Context, reason: String): Future<Outcome> =
        thread.submit(Callable { pullNow(context.applicationContext, reason) })

    /** A return to the app pulls, unless one was tried in the last 5 minutes. */
    fun appResumed(context: Context) {
        val config = GeofenceConfig(context)
        if (!config.alertsEnabled) return
        if (System.currentTimeMillis() - config.triggersTriedAtMs < RETURN_MIN_INTERVAL_MS) return
        pullLater(context, REASON_RESUMED)
    }

    /** The hourly job, with a network constraint; kept if already there. */
    fun schedule(context: Context) {
        val request = PeriodicWorkRequestBuilder<TriggerPullWorker>(1, TimeUnit.HOURS)
            .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
            .build()
        WorkManager.getInstance(context).enqueueUniquePeriodicWork(WORK, ExistingPeriodicWorkPolicy.KEEP, request)
    }

    fun cancel(context: Context) {
        WorkManager.getInstance(context).cancelUniqueWork(WORK)
    }

    /** Never throws: an exception must not reach a thread's top and end the process. */
    private fun pullNow(context: Context, reason: String): Outcome = try {
        pull(context, reason)
    } catch (failure: Exception) {
        failed(context, CODE_NETWORK, messageOf(failure), reason)
    }

    private fun pull(context: Context, reason: String): Outcome {
        val config = GeofenceConfig(context)
        if (!config.alertsEnabled) return Outcome.OFF
        config.triggersTriedAtMs = System.currentTimeMillis()
        val log = LocationConfig(context)
        val base = log.apiUrl
        if (base.isNullOrBlank()) return failed(context, CODE_NO_URL, "no server URL", reason)

        val reply = get(base.trimEnd('/') + PATH, log.token, config.triggersEtag)
        val changed = when (reply.code) {
            HttpURLConnection.HTTP_NOT_MODIFIED -> {
                config.triggersChecked(System.currentTimeMillis())
                false
            }
            HttpURLConnection.HTTP_OK -> {
                val set = try {
                    Triggers.parseEnvelope(reply.body)
                } catch (failure: TriggerSetException) {
                    return failed(context, CODE_BAD_BODY, failure.message ?: "bad set", reason)
                }
                // The inner set is what is stored, so a set read from disk parses alike.
                val json = JSONObject(reply.body).getJSONObject("data").toString()
                val adopted = GeofenceRegistry.adoptAndWait(context, json, reply.etag, set, reason)
                    .get(WAIT_REGISTRY_S, TimeUnit.SECONDS)
                // The switch went off while the pull ran: nothing was kept.
                if (!config.alertsEnabled) return Outcome.OFF
                adopted
            }
            else -> return failed(context, reply.code, "HTTP ${reply.code}", reason)
        }
        val recovered = config.triggersFailing
        config.triggersFailing = false
        if (changed || recovered) {
            GeofenceRegistry.record(
                context,
                "triggers_pulled",
                JSONObject().put("count", config.triggers.size).put("changed", changed).put("reason", reason),
            )
        }
        return if (changed) Outcome.CHANGED else Outcome.UNCHANGED
    }

    /** One row at the first failure after a success, so a day offline writes one, not 24. */
    private fun failed(context: Context, code: Int, error: String, reason: String): Outcome {
        try {
            val config = GeofenceConfig(context)
            if (!config.triggersFailing) {
                config.triggersFailing = true
                GeofenceRegistry.record(
                    context,
                    "triggers_failed",
                    JSONObject().put("code", code).put("error", error.take(200)).put("reason", reason),
                )
            }
        } catch (_: Exception) {
            // Nothing is left to tell it to; the process must still live.
        }
        return Outcome.FAILED
    }

    private class Reply(val code: Int, val body: String, val etag: String?)

    private fun get(url: String, token: String?, etag: String?): Reply {
        val connection = URL(url).openConnection() as HttpURLConnection
        try {
            connection.requestMethod = "GET"
            // A redirect could land on a page that is not the set.
            connection.instanceFollowRedirects = false
            connection.connectTimeout = TIMEOUT_MS
            connection.readTimeout = TIMEOUT_MS
            connection.setRequestProperty("Accept", "application/json")
            if (!token.isNullOrEmpty()) connection.setRequestProperty("Authorization", "Bearer $token")
            if (!etag.isNullOrEmpty()) connection.setRequestProperty("If-None-Match", etag)
            val code = connection.responseCode
            val body = if (code == HttpURLConnection.HTTP_OK) {
                connection.inputStream.bufferedReader().use { it.readText() }
            } else {
                ""
            }
            return Reply(code, body, connection.getHeaderField("ETag"))
        } finally {
            connection.disconnect()
        }
    }

    private fun messageOf(failure: Exception): String {
        val cause = failure.cause ?: failure
        return (cause.message ?: cause.javaClass.simpleName).take(200)
    }
}
