package com.voiceagent.voice_agent.location

import android.content.Context
import androidx.work.Worker
import androidx.work.WorkerParameters
import java.util.concurrent.TimeUnit

/**
 * The hourly pull of the armed triggers (ADR-NET-007), with a network
 * constraint. A failure waits for the next hour: the set last pulled stands.
 */
class TriggerPullWorker(context: Context, params: WorkerParameters) : Worker(context, params) {
    override fun doWork(): Result {
        try {
            TriggerPuller.pullAndWait(applicationContext, TriggerPuller.REASON_JOB).get(2, TimeUnit.MINUTES)
        } catch (_: Exception) {
            // The next hour pulls again.
        }
        return Result.success()
    }
}
