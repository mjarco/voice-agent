package com.voiceagent.voice_agent.location

import android.Manifest
import android.annotation.SuppressLint
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import androidx.core.content.ContextCompat
import androidx.work.BackoffPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import com.google.android.gms.common.api.ApiException
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingRequest
import com.google.android.gms.location.LocationServices
import com.google.android.gms.tasks.Task
import com.google.android.gms.tasks.Tasks
import java.security.MessageDigest
import java.util.concurrent.Callable
import java.util.concurrent.ExecutionException
import java.util.concurrent.Executors
import java.util.concurrent.Future
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException
import org.json.JSONObject

/**
 * Geofences of places (ADR-PLATFORM-010): one per place, registered beside the
 * location log. Until task 4 they only write rows; nothing is shown.
 *
 * Registration is safe to repeat, as the pipeline's subscription is: geofences
 * are lost at a reboot, an update, a force stop and when location goes off, so
 * it runs at each of those, at app start, and when the places, the switch or
 * the permission change. It runs on its own thread, one at a time, and waits
 * there for Play services; rows go to the pipeline's thread, which never waits
 * on Play services, so a reading or a broadcast is never held behind it.
 */
object GeofenceRegistry {
    /** NO_PERMISSION is not retried by the job: a return to the app registers. */
    enum class Outcome { OFF, REGISTERED, UNCHANGED, FAILED, NO_PERMISSION }

    const val REASON_RETRY = "retry"
    const val REASON_SWITCH = "switch"

    /**
     * Reasons after which Play services still holds what was registered, as
     * long as the intent survived (a force stop cancels it). For these only new
     * or changed geofences are added: adding one again replaces it and resets
     * its state, so with initial trigger 0 a visit in progress would lose its
     * enter and dwell. Every other reason (boot, update, retry, the switch, a
     * permission change) adds them all.
     */
    private val KEEPING_REASONS = setOf("app_start", "places_changed")

    /** Registrations run here, one at a time. */
    val executor = Executors.newSingleThreadExecutor()

    /** Android's limit per app. */
    private const val MAX_GEOFENCES = 100

    /** The smallest radius Android's geofencing is reliable at. */
    private const val MIN_RADIUS_M = 150

    /** One value with `dwell_s` of the triggers (personal-agent, thought-agent#637). */
    private const val LOITERING_DELAY_MS = 60_000

    private const val REQUEST_CODE = 4102
    private const val RETRY_WORK = "geofence-register"
    private const val WAIT_S = 15L

    /** GeofenceStatusCodes.GEOFENCE_INSUFFICIENT_LOCATION_PERMISSION. */
    private const val CODE_NO_PERMISSION = 1004
    private const val CODE_TIMEOUT = -1
    private const val CODE_UNKNOWN = -2

    fun radiusOf(place: GeofencePlace): Int = maxOf(place.radiusM, MIN_RADIUS_M)

    fun pendingIntent(context: Context, flags: Int): PendingIntent? {
        val intent = Intent(context, GeofenceReceiver::class.java).setAction(GeofenceReceiver.ACTION)
        return PendingIntent.getBroadcast(context, REQUEST_CODE, intent, flags)
    }

    /** What the set would register as, so an unchanged hand-over registers nothing. */
    fun hashOf(places: List<GeofencePlace>): String {
        val text = places.take(MAX_GEOFENCES).map { keyOf(it) }.sorted().joinToString("\n")
        val digest = MessageDigest.getInstance("SHA-256").digest(text.toByteArray())
        return digest.joinToString("") { "%02x".format(it.toInt() and 0xFF) }
    }

    /** Registers on the registry's thread; [done] runs after, whatever happened. */
    fun reconcileLater(context: Context, reason: String, done: () -> Unit = {}) {
        executor.execute {
            try {
                reconcileNow(context, reason)
            } finally {
                done()
            }
        }
    }

    /** For the retry job, which needs the outcome. */
    fun reconcileAndWait(context: Context, reason: String): Future<Outcome> =
        executor.submit(Callable { reconcileNow(context, reason) })

    /**
     * Must run on [executor]. Never throws: an exception here must not reach a
     * thread's top, or it would end the process, a hands-free session with it.
     */
    fun reconcileNow(context: Context, reason: String): Outcome = try {
        reconcile(context, reason)
    } catch (failure: Exception) {
        // A row, not the log's last error, which the screen shows as a send error.
        try {
            record(
                context,
                "geofences_failed",
                JSONObject().put("code", CODE_UNKNOWN).put("reason", reason).put("error", messageOf(failure)),
            )
        } catch (_: Exception) {
            // Nothing is left to tell it to; the process must still live.
        }
        Outcome.FAILED
    }

    /** What a geofence is made of; a place whose key changed is added again. */
    private fun keyOf(place: GeofencePlace): String =
        "${place.id}|${place.latitude}|${place.longitude}|${radiusOf(place)}"

    /**
     * The permission changed since the last registration, as when "always" was
     * just granted on the settings page: register again. Cheap, so it may run
     * on any thread.
     */
    fun permissionMayHaveChanged(context: Context) {
        val config = GeofenceConfig(context)
        if (!config.alertsEnabled) return
        if (config.lastPermission == LocationPipeline.permission(context)) return
        reconcileLater(context, "permission_changed")
    }

    private fun reconcile(context: Context, reason: String): Outcome {
        val config = GeofenceConfig(context)
        if (!config.alertsEnabled) {
            removeAll(context, config, reason)
            return Outcome.OFF
        }
        config.lastPermission = LocationPipeline.permission(context)
        val all = config.places
        val chosen = all.take(MAX_GEOFENCES)
        val ids = chosen.map { it.id }.toSet()
        val held = config.registeredIds
        val heldKeys = config.registeredKeys
        val intact = reason in KEEPING_REASONS && config.registeredHash != null && !config.degraded &&
            pendingIntent(context, PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_MUTABLE) != null
        val toAdd = if (intact) chosen.filter { keyOf(it) !in heldKeys } else chosen
        val gone = held - ids
        // Nothing to do leaves a visit in progress alone, and writes no row.
        if (intact && toAdd.isEmpty() && gone.isEmpty()) return Outcome.UNCHANGED
        if (all.size > chosen.size) {
            record(
                context,
                "geofences_capped",
                JSONObject().put("count", chosen.size).put("left_out", all.size - chosen.size).put("reason", reason),
            )
        }
        val client = LocationServices.getGeofencingClient(context)
        try {
            if (config.registeredHash == null && held.isNotEmpty()) {
                // The last attempt failed half-way: what Play services holds is
                // unknown, so start from nothing rather than leave a stale one.
                pendingIntent(context, PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_MUTABLE)
                    ?.let { await(client.removeGeofences(it)) }
            } else if (gone.isNotEmpty()) {
                await(client.removeGeofences(gone.toList()))
            }
            if (toAdd.isNotEmpty()) {
                if (!fineGranted(context)) throw SecurityException("no fine location")
                await(add(context, toAdd))
            }
        } catch (failure: Exception) {
            val code = codeOf(failure)
            // Every id that may still be held is kept, so the next try removes it.
            config.uncertain(held + ids)
            record(
                context,
                "geofences_failed",
                JSONObject().put("code", code).put("reason", reason).put("error", messageOf(failure)),
            )
            // A missing permission is not waited out: a return to the app with
            // the permission changed registers again.
            if (code == CODE_NO_PERMISSION) return Outcome.NO_PERMISSION
            scheduleRetry(context)
            return Outcome.FAILED
        }
        config.registered(ids, chosen.map { keyOf(it) }.toSet(), hashOf(chosen), System.currentTimeMillis())
        record(
            context,
            "geofences_registered",
            JSONObject().put("count", chosen.size).put("added", toAdd.size).put("reason", reason),
        )
        if (config.degraded) {
            config.degraded = false
            record(context, "app.location_restored", JSONObject().put("cause", "geofence_not_available"))
        }
        // A pending retry has nothing left to do; the job itself ends by its result.
        if (reason != REASON_RETRY) WorkManager.getInstance(context).cancelUniqueWork(RETRY_WORK)
        return Outcome.REGISTERED
    }

    /**
     * The system dropped every geofence: location went off. Runs on the
     * registry's thread, after any registration in progress, so that one cannot
     * overwrite this state or cancel the retry scheduled here; [done] runs after.
     */
    fun lostLater(context: Context, done: () -> Unit) {
        executor.execute {
            try {
                val config = GeofenceConfig(context)
                // Uncertain, not cleared: the next registration removes them all first.
                config.uncertain(config.registeredIds)
                if (!config.degraded) {
                    config.degraded = true
                    record(context, "app.location_degraded", JSONObject().put("cause", "geofence_not_available"))
                }
                scheduleRetry(context)
            } catch (_: Exception) {
                // The retry job or the next app start registers again.
            } finally {
                done()
            }
        }
    }

    /**
     * A unique one-time job with backoff and no network constraint: it only
     * registers and posts nothing (ADR-NET-002 and ADR-NET-005 stand). The
     * backoff is linear, a minute more each time, so after a night with location
     * off the next try is about half an hour away, not WorkManager's 5 h cap.
     */
    fun scheduleRetry(context: Context) {
        val request = OneTimeWorkRequestBuilder<GeofenceRegisterWorker>()
            .setInitialDelay(30, TimeUnit.SECONDS)
            .setBackoffCriteria(BackoffPolicy.LINEAR, 60, TimeUnit.SECONDS)
            .build()
        WorkManager.getInstance(context).enqueueUniqueWork(RETRY_WORK, ExistingWorkPolicy.KEEP, request)
    }

    private fun removeAll(context: Context, config: GeofenceConfig, reason: String) {
        WorkManager.getInstance(context).cancelUniqueWork(RETRY_WORK)
        val wasOn = config.registeredHash != null || reason == REASON_SWITCH
        var removed = true
        pendingIntent(context, PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_MUTABLE)?.let { intent ->
            try {
                await(LocationServices.getGeofencingClient(context).removeGeofences(intent))
            } catch (_: Exception) {
                // Kept as uncertain: the next registration starts by removing them all.
                removed = false
            }
        }
        if (removed) config.clearRegistration() else config.uncertain(config.registeredIds)
        config.degraded = false
        // Only the switch turning off writes; with it off nothing else does.
        if (wasOn) record(context, "geofences_removed", JSONObject().put("reason", reason))
    }

    @SuppressLint("MissingPermission") // checked by the caller
    private fun add(context: Context, places: List<GeofencePlace>): Task<Void> {
        val geofences = places.map { place ->
            Geofence.Builder()
                .setRequestId(place.id)
                .setCircularRegion(place.latitude, place.longitude, radiusOf(place).toFloat())
                .setExpirationDuration(Geofence.NEVER_EXPIRE)
                .setTransitionTypes(
                    Geofence.GEOFENCE_TRANSITION_ENTER or
                        Geofence.GEOFENCE_TRANSITION_DWELL or
                        Geofence.GEOFENCE_TRANSITION_EXIT,
                )
                .setLoiteringDelay(LOITERING_DELAY_MS)
                .setNotificationResponsiveness(0)
                .build()
        }
        // Initial trigger 0: registering while standing in a place must not log
        // a false enter. A reboot inside a place therefore logs no enter there;
        // the exit still comes.
        val request = GeofencingRequest.Builder()
            .setInitialTrigger(0)
            .addGeofences(geofences)
            .build()
        val intent = pendingIntent(context, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE)!!
        return LocationServices.getGeofencingClient(context).addGeofences(request, intent)
    }

    private fun fineGranted(context: Context): Boolean =
        ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED

    private fun <T> await(task: Task<T>): T = Tasks.await(task, WAIT_S, TimeUnit.SECONDS)

    private fun codeOf(failure: Exception): Int {
        val cause = if (failure is ExecutionException) failure.cause else failure
        return when (cause) {
            is ApiException -> cause.statusCode
            is SecurityException -> CODE_NO_PERMISSION
            is TimeoutException -> CODE_TIMEOUT
            else -> CODE_UNKNOWN
        }
    }

    private fun messageOf(failure: Exception): String {
        val cause = (if (failure is ExecutionException) failure.cause else failure) ?: failure
        return (cause.message ?: cause.javaClass.simpleName).take(200)
    }

    /** Rows are written on the pipeline's thread, in order, then drained. */
    private fun record(context: Context, status: String, detail: JSONObject) {
        LocationPipeline.write(context) {
            LocationPipeline.recordStatus(context, status, detail)
            LocationPipeline.scheduleDrain(context)
        }
    }
}
