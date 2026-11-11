package com.voiceagent.voice_agent.location

import android.content.Context
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import java.time.Instant
import java.util.concurrent.TimeUnit
import org.json.JSONObject

/**
 * Watches the subscription by its readings (ADR-PLATFORM-012). Play services
 * can drop the app's location request with no callback (after the update to
 * 1.29.0 it held only the geofences), and the app re-subscribes only when its
 * process starts, so a long-lived process stayed without readings for a day.
 * A periodic job re-subscribes when no reading has come for a while, in
 * background mode only.
 */
object LocationWatch {
    /** Six background intervals: normal gaps stay under it, a lost request does not. */
    const val STALE_AFTER_MS = 30 * 60 * 1000L

    /** After a re-subscription that brought nothing, wait this long before the next one. */
    const val RETRY_AFTER_MS = 2 * 60 * 60 * 1000L

    const val REASON = "stale_readings"
    const val REASON_MOTION = "watch"
    private const val WORK = "location-log-watch"
    private const val PERIOD_MINUTES = 30L

    /**
     * Play services clears an updated package's requests after the app has
     * already subscribed again (ADR-PLATFORM-013: 117 ms later at the 1.29.1
     * install), so a second subscription follows an update by this long.
     */
    const val AFTER_UPDATE_DELAY_SECONDS = 60L
    const val AFTER_UPDATE_REASON = "after_update"
    private const val AFTER_UPDATE_WORK = "location-log-after-update"

    /**
     * Whether to re-subscribe now. A fresh subscription gets its own
     * [STALE_AFTER_MS] to bring a reading; a stale stretch is answered once
     * per [RETRY_AFTER_MS], so a phone with location off writes a few rows a
     * day, not two an hour.
     */
    fun isStale(nowMs: Long, lastReadingAtMs: Long, lastSubscribedAtMs: Long, lastStaleAtMs: Long): Boolean {
        val since = maxOf(lastReadingAtMs, lastSubscribedAtMs)
        if (nowMs - since < STALE_AFTER_MS) return false
        if (lastStaleAtMs > lastReadingAtMs && nowMs - lastStaleAtMs < RETRY_AFTER_MS) return false
        return true
    }

    /** Runs on the pipeline's thread. */
    fun check(context: Context, nowMs: Long = System.currentTimeMillis()) {
        val config = LocationConfig(context)
        if (!config.enabled) return
        if (config.mode == LocationConfig.MODE_MOTION) {
            // The registration may go silently, like the location request (deep review of D1, M1).
            MotionTransitions.subscribe(context, REASON_MOTION)
            // A `still` or a stop that no frequent reading has settled yet (ADR-PLATFORM-014).
            LocationPipeline.settleIfStill(context, config, nowMs)
        }
        // Foreground mode keeps its own service, which a start from a worker
        // could tear down (deep review of D1); the watch is for background readings.
        if (config.effectiveMode != LocationConfig.MODE_BACKGROUND) return
        val lastReading = config.lastReadingAtMs
        val lastSubscribed = config.lastSubscribedAtMs
        if (!isStale(nowMs, lastReading, lastSubscribed, config.lastStaleAtMs)) return
        config.lastStaleAtMs = nowMs
        LocationPipeline.recordStatus(
            context,
            "readings_stale",
            JSONObject()
                .put("last_reading_at", instantOrNull(lastReading))
                .put("last_subscribed_at", instantOrNull(lastSubscribed)),
        )
        LocationPipeline.reconcile(context, REASON)
    }

    /**
     * The second subscription after an update is for background readings only,
     * like the watch: background mode, and motion mode while it reads in the
     * background (ADR-PLATFORM-014), so [effectiveMode] decides.
     */
    fun resubscribesAfterUpdate(enabled: Boolean, effectiveMode: String): Boolean =
        enabled && effectiveMode == LocationConfig.MODE_BACKGROUND

    /** Runs on the pipeline's thread, [AFTER_UPDATE_DELAY_SECONDS] after `MY_PACKAGE_REPLACED`. */
    fun afterUpdate(context: Context) {
        val config = LocationConfig(context)
        if (!resubscribesAfterUpdate(config.enabled, config.effectiveMode)) return
        LocationPipeline.reconcile(context, AFTER_UPDATE_REASON)
    }

    /** Called at `MY_PACKAGE_REPLACED`; the worker reads the configuration when it runs. */
    fun scheduleAfterUpdate(context: Context) {
        val request = OneTimeWorkRequestBuilder<LocationAfterUpdateWorker>()
            .setInitialDelay(AFTER_UPDATE_DELAY_SECONDS, TimeUnit.SECONDS)
            .build()
        WorkManager.getInstance(context).enqueueUniqueWork(AFTER_UPDATE_WORK, ExistingWorkPolicy.REPLACE, request)
    }

    /**
     * Each reconcile may call it: UPDATE keeps the job's schedule but carries a
     * changed period to phones that already have the job.
     */
    fun schedule(context: Context) {
        val request = PeriodicWorkRequestBuilder<LocationWatchWorker>(PERIOD_MINUTES, TimeUnit.MINUTES).build()
        WorkManager.getInstance(context).enqueueUniquePeriodicWork(WORK, ExistingPeriodicWorkPolicy.UPDATE, request)
    }

    fun cancel(context: Context) {
        WorkManager.getInstance(context).cancelUniqueWork(WORK)
    }

    private fun instantOrNull(ms: Long): Any = if (ms > 0) Instant.ofEpochMilli(ms).toString() else JSONObject.NULL
}
