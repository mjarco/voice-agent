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
    enum class Outcome { OFF, REGISTERED, FAILED }

    const val REASON_RETRY = "retry"
    const val REASON_SWITCH = "switch"

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
        val text = places.take(MAX_GEOFENCES)
            .sortedBy { it.id }
            .joinToString("\n") { "${it.id}|${it.latitude}|${it.longitude}|${radiusOf(it)}" }
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
        LocationPipeline.note(context, failure)
        Outcome.FAILED
    }

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
        if (all.size > chosen.size) {
            record(
                context,
                "geofences_capped",
                JSONObject().put("count", chosen.size).put("left_out", all.size - chosen.size).put("reason", reason),
            )
        }
        val ids = chosen.map { it.id }.toSet()
        val held = config.registeredIds
        val client = LocationServices.getGeofencingClient(context)
        try {
            if (config.registeredHash == null && held.isNotEmpty()) {
                // The last attempt failed half-way: what Play services holds is
                // unknown, so start from nothing rather than leave a stale one.
                pendingIntent(context, PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_MUTABLE)
                    ?.let { await(client.removeGeofences(it)) }
            } else {
                val gone = held - ids
                if (gone.isNotEmpty()) await(client.removeGeofences(gone.toList()))
            }
            if (chosen.isNotEmpty()) {
                if (!fineGranted(context)) throw SecurityException("no fine location")
                await(add(context, chosen))
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
            if (code != CODE_NO_PERMISSION) scheduleRetry(context)
            return Outcome.FAILED
        }
        config.registered(ids, hashOf(chosen), System.currentTimeMillis())
        record(context, "geofences_registered", JSONObject().put("count", chosen.size).put("reason", reason))
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
     * pipeline's thread, from the receiver, and writes there directly.
     */
    fun lost(context: Context) {
        val config = GeofenceConfig(context)
        config.clearRegistration()
        if (!config.degraded) {
            config.degraded = true
            LocationPipeline.recordStatus(
                context,
                "app.location_degraded",
                JSONObject().put("cause", "geofence_not_available"),
            )
        }
        scheduleRetry(context)
    }

    /**
     * A unique one-time job with backoff and no network constraint: it only
     * registers and posts nothing (ADR-NET-002 and ADR-NET-005 stand).
     */
    fun scheduleRetry(context: Context) {
        val request = OneTimeWorkRequestBuilder<GeofenceRegisterWorker>()
            .setInitialDelay(30, TimeUnit.SECONDS)
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
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
        // Initial trigger 0: re-registering at every app start while standing in
        // a place must not log a false enter each time. A reboot inside a place
        // therefore logs no enter there; the exit still comes.
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
