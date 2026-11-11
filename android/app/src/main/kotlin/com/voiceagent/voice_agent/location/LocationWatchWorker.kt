package com.voiceagent.voice_agent.location

import android.content.Context
import androidx.work.Worker
import androidx.work.WorkerParameters
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * The watch of the subscription (ADR-PLATFORM-012), every 30 minutes with no
 * constraint: re-subscribing needs no network, and the rows it writes wait in
 * the queue like any other.
 */
class LocationWatchWorker(context: Context, params: WorkerParameters) : Worker(context, params) {
    override fun doWork(): Result {
        val done = CountDownLatch(1)
        // On the pipeline's thread, like every other write and reconcile.
        LocationPipeline.write(applicationContext, done = { done.countDown() }) {
            LocationWatch.check(applicationContext)
        }
        done.await(1, TimeUnit.MINUTES)
        return Result.success()
    }
}
