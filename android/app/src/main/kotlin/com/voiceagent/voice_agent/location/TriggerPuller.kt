package com.voiceagent.voice_agent.location

import android.content.Context
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import java.net.HttpURLConnection
import java.net.URL
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
    const val REASON_JOB = "hourly"
    const val REASON_APP_START = "app_start"
    const val REASON_SWITCH = "switch"
    const val REASON_RESUMED = "app_resumed"

    private val thread = Executors.newSingleThreadExecutor()

    private const val PATH = "/triggers"
    private const val WORK = "triggers-pull"
    private const val TIMEOUT_MS = 6_000
    private const val RETURN_MIN_INTERVAL_MS = 5 * 60_000L

    /** The status of a reply that is not personal-agent's set. */
    private const val CODE_BAD_BODY = -3
    private const val CODE_NO_URL = -4
    private const val CODE_NETWORK = -5

    fun pullLater(context: Context, reason: String) {
        thread.execute { pullNow(context.applicationContext, reason) }
    }

    /** For the hourly job: waits for the request, not for the registration after it. */
    fun pullAndWait(context: Context, reason: String): Future<*> =
        thread.submit { pullNow(context.applicationContext, reason) }

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

    /** What a pull brought; settled on the registry's thread. */
    private sealed class Pulled {
        object Unchanged : Pulled()
        class NewSet(val json: String, val etag: String?, val set: TriggerSet) : Pulled()
        class Failed(val code: Int, val error: String) : Pulled()
    }

    /**
     * The request runs here; what it brought is settled on the registry's
     * thread, after any registration in progress, so the switch going off
     * meanwhile wins and nothing is written with it off. Never throws: an
     * exception must not reach a thread's top and end the process.
     */
    private fun pullNow(context: Context, reason: String) {
        val pulled = try {
            val config = GeofenceConfig(context)
            if (!config.alertsEnabled) return
            config.triggersTriedAtMs = System.currentTimeMillis()
            request(context, config)
        } catch (failure: Exception) {
            Pulled.Failed(CODE_NETWORK, messageOf(failure))
        }
        try {
            GeofenceRegistry.executor.execute { settle(context, pulled, reason) }
        } catch (_: Exception) {
            // The next pull tries again.
        }
    }

    private fun request(context: Context, config: GeofenceConfig): Pulled {
        val log = LocationConfig(context)
        val base = log.apiUrl
        if (base.isNullOrBlank()) return Pulled.Failed(CODE_NO_URL, "no server URL")
        val reply = get(base.trimEnd('/') + PATH, log.token, config.triggersEtag)
        return when (reply.code) {
            HttpURLConnection.HTTP_NOT_MODIFIED -> Pulled.Unchanged
            HttpURLConnection.HTTP_OK -> try {
                val set = Triggers.parseEnvelope(reply.body)
                // The inner set is what is stored, so a set read from disk parses alike.
                Pulled.NewSet(JSONObject(reply.body).getJSONObject("data").toString(), reply.etag, set)
            } catch (failure: TriggerSetException) {
                Pulled.Failed(CODE_BAD_BODY, failure.message ?: "bad set")
            }
            else -> Pulled.Failed(reply.code, "HTTP ${reply.code}")
        }
    }

    /** On the registry's thread. A failure writes one row until a pull works again. */
    private fun settle(context: Context, pulled: Pulled, reason: String) {
        try {
            val config = GeofenceConfig(context)
            if (!config.alertsEnabled) return
            val changed = when (pulled) {
                is Pulled.Failed -> {
                    if (!config.triggersFailing) {
                        config.triggersFailing = true
                        GeofenceRegistry.record(
                            context,
                            "triggers_failed",
                            JSONObject().put("code", pulled.code).put("error", pulled.error.take(200)).put("reason", reason),
                        )
                    }
                    return
                }
                is Pulled.Unchanged -> {
                    config.triggersChecked(System.currentTimeMillis())
                    false
                }
                is Pulled.NewSet -> GeofenceRegistry.adopt(context, pulled.json, pulled.etag, pulled.set)
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
        } catch (_: Exception) {
            // Nothing is left to tell it to; the process must still live.
        }
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
