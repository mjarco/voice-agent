package com.voiceagent.voice_agent.location

import android.content.Context
import androidx.work.Worker
import androidx.work.WorkerParameters

/**
 * Registers the geofences again after a failure, with backoff, until it works
 * (ADR-PLATFORM-010). While location stays off the add fails and the job backs
 * off. It posts nothing, so it is not a network path.
 */
class GeofenceRegisterWorker(context: Context, params: WorkerParameters) : Worker(context, params) {
    override fun doWork(): Result {
        val outcome = try {
            // On the registry's thread, so it never races the switch or another registration.
            GeofenceRegistry.reconcileAndWait(applicationContext, GeofenceRegistry.REASON_RETRY).get()
        } catch (_: Exception) {
            GeofenceRegistry.Outcome.FAILED
        }
        return if (outcome == GeofenceRegistry.Outcome.FAILED) Result.retry() else Result.success()
    }
}
