package com.voiceagent.voice_agent.location

import android.content.Context
import androidx.work.Worker
import androidx.work.WorkerParameters
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * The second subscription a minute after an update (ADR-PLATFORM-013), with no
 * constraint: re-subscribing needs no network.
 */
class LocationAfterUpdateWorker(context: Context, params: WorkerParameters) : Worker(context, params) {
    override fun doWork(): Result {
        val done = CountDownLatch(1)
        // On the pipeline's thread, like every other write and reconcile.
        LocationPipeline.write(applicationContext, done = { done.countDown() }) {
            LocationWatch.afterUpdate(applicationContext)
        }
        done.await(1, TimeUnit.MINUTES)
        return Result.success()
    }
}
