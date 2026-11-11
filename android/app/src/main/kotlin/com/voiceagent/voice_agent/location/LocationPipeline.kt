package com.voiceagent.voice_agent.location

import android.Manifest
import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationManager
import android.os.Build
import android.os.PowerManager
import androidx.core.content.ContextCompat
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import java.time.Instant
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import org.json.JSONObject

/**
 * The location log on the phone (ADR-PLATFORM-009): subscribes, writes each
 * reading locally, then sends. All of it runs without Flutter, because a
 * background wake-up may end before an engine could start.
 */
object LocationPipeline {
    /** One thread for writes and Settings, so a slow server never delays a reading. */
    val executor = Executors.newSingleThreadExecutor()

    /** One thread for live sends. A send only reads the rows it posts, then deletes them. */
    private val sender = Executors.newSingleThreadExecutor()
    private val sending = AtomicBoolean(false)

    private const val DRAIN_WORK = "location-log-drain"
    private const val UPDATES_REQUEST_CODE = 4101
    private const val FASTEST_BACKGROUND_INTERVAL_MS = 60_000L
    private const val MAX_DETAIL_LENGTH = 500

    fun updatesIntent(context: Context, flags: Int): PendingIntent? {
        val intent = Intent(context, LocationUpdateReceiver::class.java).setAction(LocationUpdateReceiver.ACTION)
        return PendingIntent.getBroadcast(context, UPDATES_REQUEST_CODE, intent, flags)
    }

    fun permission(context: Context): String {
        fun granted(name: String) = ContextCompat.checkSelfPermission(context, name) == PackageManager.PERMISSION_GRANTED
        val fine = granted(Manifest.permission.ACCESS_FINE_LOCATION)
        val coarse = granted(Manifest.permission.ACCESS_COARSE_LOCATION)
        return when {
            !fine && !coarse -> "none"
            !fine -> "approximate"
            granted(Manifest.permission.ACCESS_BACKGROUND_LOCATION) -> "always"
            else -> "while_in_use"
        }
    }

    /** Returns the row's id. */
    fun recordStatus(
        context: Context,
        status: String,
        detail: String? = null,
        recordedAt: Instant = Instant.now(),
        id: String = Uuid7.next(),
    ): String {
        val payload = JSONObject()
            .put("kind", "status")
            .put("recorded_at", recordedAt.toString())
            .put("status", status)
        // The server refuses a longer one, and a refused row is gone.
        detail?.let { payload.put("detail", it.take(MAX_DETAIL_LENGTH)) }
        return LocationStore.get(context).enqueue(payload, id)
    }

    /**
     * A status whose detail is JSON. Cutting it at 500 characters would leave
     * half an object, so it is kept whole or shrunk by dropping the name.
     */
    fun recordStatus(
        context: Context,
        status: String,
        detail: JSONObject,
        recordedAt: Instant = Instant.now(),
        id: String = Uuid7.next(),
    ): String {
        var text = detail.toString()
        if (text.length > MAX_DETAIL_LENGTH) {
            detail.remove("name")
            text = detail.toString()
        }
        if (text.length > MAX_DETAIL_LENGTH) {
            text = JSONObject().put("detail_too_long", text.length).toString()
        }
        return recordStatus(context, status, text, recordedAt, id)
    }

    fun recordReadings(context: Context, locations: List<Location>, config: LocationConfig) {
        val store = LocationStore.get(context)
        for (location in locations) {
            val payload = JSONObject()
                .put("kind", "reading")
                .put("recorded_at", Instant.ofEpochMilli(location.time).toString())
                .put("latitude", location.latitude)
                .put("longitude", location.longitude)
                .put("requested_mode", config.mode)
                .put("requested_interval_s", config.intervalSeconds)
            if (location.hasAccuracy()) payload.put("accuracy_m", location.accuracy.toDouble())
            if (location.hasSpeed()) payload.put("speed_mps", location.speed.toDouble())
            store.enqueue(payload)
            config.lastReadingAtMs = location.time
        }
    }

    /** Writes a status row for anything that changed since the last look. */
    fun recordChanges(context: Context, config: LocationConfig) {
        val permission = permission(context)
        if (config.lastPermission != permission) {
            if (config.lastPermission != null) recordStatus(context, "permission", permission)
            config.lastPermission = permission
        }
        val saver = context.getSystemService(PowerManager::class.java).isPowerSaveMode
        if (config.lastBatterySaver != saver) {
            if (config.lastBatterySaver != null) recordStatus(context, "battery_saver", if (saver) "on" else "off")
            config.lastBatterySaver = saver
        }
        val locationOn = locationEnabled(context)
        if (config.lastLocationOn != locationOn) {
            if (config.lastLocationOn != null) recordStatus(context, "location_setting", if (locationOn) "on" else "off")
            config.lastLocationOn = locationOn
        }
    }

    private fun locationEnabled(context: Context): Boolean {
        val manager = context.getSystemService(LocationManager::class.java)
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            manager.isLocationEnabled
        } else {
            manager.isProviderEnabled(LocationManager.GPS_PROVIDER)
        }
    }

    /**
     * The Stop button of the Task Manager ends the app with no callback, so its
     * trace can only be read on the next start.
     */
    private fun recordExits(context: Context, config: LocationConfig) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return
        val exits = context.getSystemService(ActivityManager::class.java)
            .getHistoricalProcessExitReasons(context.packageName, 0, 8)
        val seen = config.lastExitSeenAtMs
        config.lastExitSeenAtMs = maxOf(seen, exits.maxOfOrNull { it.timestamp } ?: seen)
        // With the log off nothing is written, not even a status.
        if (seen == 0L || !config.enabled) return
        for (exit in exits.filter { it.timestamp > seen }.sortedBy { it.timestamp }) {
            val reason = when (exit.reason) {
                ApplicationExitInfo.REASON_USER_REQUESTED -> "user_requested"
                ApplicationExitInfo.REASON_USER_STOPPED -> "user_stopped"
                ApplicationExitInfo.REASON_LOW_MEMORY -> "low_memory"
                ApplicationExitInfo.REASON_CRASH, ApplicationExitInfo.REASON_CRASH_NATIVE -> "crash"
                ApplicationExitInfo.REASON_ANR -> "anr"
                else -> null
            } ?: continue
            recordStatus(context, "process_exit", "$reason at ${Instant.ofEpochMilli(exit.timestamp)}")
        }
    }

    /**
     * Makes the subscription match the configuration. Safe to repeat: a
     * subscription is assumed lost after a reboot, an update or a force stop, so
     * this runs at each of those and at each app start.
     */
    fun reconcile(context: Context, reason: String) {
        val config = LocationConfig(context)
        recordExits(context, config)
        if (!config.enabled) {
            unsubscribe(context)
            LocationWatch.cancel(context)
            scheduleDrainIfNeeded(context)
            return
        }
        recordChanges(context, config)
        LocationWatch.schedule(context)
        if (config.mode == LocationConfig.MODE_FOREGROUND) {
            subscribeInForeground(context, config, reason)
        } else {
            subscribeInBackground(context, config, reason)
        }
        scheduleDrainIfNeeded(context)
    }

    fun unsubscribe(context: Context) {
        stopBackgroundUpdates(context)
        context.stopService(Intent(context, LocationForegroundService::class.java))
    }

    private fun stopBackgroundUpdates(context: Context) {
        val intent = updatesIntent(context, PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_MUTABLE) ?: return
        LocationServices.getFusedLocationProviderClient(context).removeLocationUpdates(intent)
        intent.cancel()
    }

    private fun subscribeInBackground(context: Context, config: LocationConfig, reason: String) {
        context.stopService(Intent(context, LocationForegroundService::class.java))
        val request = LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, config.intervalSeconds * 1000L)
            .setMinUpdateIntervalMillis(FASTEST_BACKGROUND_INTERVAL_MS)
            .build()
        val intent = updatesIntent(context, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE)!!
        try {
            LocationServices.getFusedLocationProviderClient(context)
                .requestLocationUpdates(request, intent)
                .addOnFailureListener { failure ->
                    executor.execute { recordStatus(context, "subscribe_failed", failure.message ?: "unknown") }
                }
            config.lastSubscribedAtMs = System.currentTimeMillis()
            recordStatus(context, "subscribed", "background, $reason")
        } catch (failure: SecurityException) {
            recordStatus(context, "subscribe_failed", "permission: ${failure.message}")
        }
    }

    private fun subscribeInForeground(context: Context, config: LocationConfig, reason: String) {
        stopBackgroundUpdates(context)
        try {
            ContextCompat.startForegroundService(context, Intent(context, LocationForegroundService::class.java))
            config.lastSubscribedAtMs = System.currentTimeMillis()
            recordStatus(context, "subscribed", "foreground every ${config.intervalSeconds} s, $reason")
        } catch (failure: RuntimeException) {
            // ForegroundServiceStartNotAllowedException and SecurityException
            // both land here: the next app start tries again.
            recordStatus(context, "subscribe_failed", failure.toString())
        }
    }

    fun scheduleDrain(context: Context) {
        val request = OneTimeWorkRequestBuilder<LocationDrainWorker>()
            .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
            .build()
        WorkManager.getInstance(context).enqueueUniqueWork(DRAIN_WORK, ExistingWorkPolicy.KEEP, request)
    }

    private fun scheduleDrainIfNeeded(context: Context) {
        if (LocationStore.get(context).count() > 0) scheduleDrain(context)
    }

    /**
     * Writes on the pipeline's thread. An exception must not reach the thread's
     * top, or it would end the whole process, a hands-free session with it.
     */
    fun write(context: Context, done: () -> Unit = {}, block: () -> Unit) {
        executor.execute {
            try {
                block()
            } catch (failure: Exception) {
                note(context, failure)
            } finally {
                done()
            }
        }
    }

    /**
     * One live attempt off the write thread; whatever it leaves goes to the
     * worker, which waits for a network. While a send runs, a second is not
     * queued behind it: the worker takes what the first leaves.
     */
    fun sendNow(context: Context, done: () -> Unit = {}) {
        if (!sending.compareAndSet(false, true)) {
            done()
            return
        }
        sender.execute {
            try {
                if (LocationUploader(context).sendBatch() != LocationUploader.Outcome.DONE) scheduleDrain(context)
            } catch (failure: Exception) {
                note(context, failure)
            } finally {
                sending.set(false)
                done()
            }
        }
    }

    fun note(context: Context, failure: Exception) {
        try {
            LocationConfig(context).lastError = "${Instant.now()}: $failure"
        } catch (_: Exception) {
            // Nothing is left to tell it to; the process must still live.
        }
    }
}
