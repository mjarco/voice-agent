package com.voiceagent.voice_agent.location

import android.content.Context
import androidx.work.Worker
import androidx.work.WorkerParameters

/**
 * Empties the queue once a network is back. This is the location log's own
 * background carve-out (ADR-NET-005): it posts location rows only.
 */
class LocationDrainWorker(context: Context, params: WorkerParameters) : Worker(context, params) {
    override fun doWork(): Result {
        val uploader = LocationUploader(applicationContext)
        while (!isStopped) {
            when (uploader.sendBatch()) {
                LocationUploader.Outcome.DONE -> return Result.success()
                LocationUploader.Outcome.MORE -> Unit
                // A live send holds the queue; come back after the backoff.
                LocationUploader.Outcome.BUSY, LocationUploader.Outcome.FAILED -> return Result.retry()
            }
        }
        return Result.retry()
    }
}
