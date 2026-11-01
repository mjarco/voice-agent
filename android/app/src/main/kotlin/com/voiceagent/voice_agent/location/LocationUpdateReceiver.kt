package com.voiceagent.voice_agent.location

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.google.android.gms.location.LocationResult

/** Background mode: the system wakes this with new readings, a few times an hour. */
class LocationUpdateReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val result = LocationResult.extractResult(intent) ?: return
        val appContext = context.applicationContext
        val pending = goAsync()
        LocationPipeline.executor.execute {
            try {
                val config = LocationConfig(appContext)
                if (config.enabled) {
                    LocationPipeline.recordChanges(appContext, config)
                    LocationPipeline.recordReadings(appContext, result.locations, config)
                    LocationPipeline.sendNow(appContext)
                }
            } finally {
                pending.finish()
            }
        }
    }

    companion object {
        const val ACTION = "com.voiceagent.voice_agent.location.UPDATES"
    }
}
