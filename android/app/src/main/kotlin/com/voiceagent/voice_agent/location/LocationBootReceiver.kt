package com.voiceagent.voice_agent.location

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** A subscription is assumed lost after a reboot or an update, so take it out again. */
class LocationBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val reason = when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED -> "reboot"
            Intent.ACTION_MY_PACKAGE_REPLACED -> "app_updated"
            else -> return
        }
        val appContext = context.applicationContext
        val pending = goAsync()
        LocationPipeline.executor.execute {
            try {
                if (LocationConfig(appContext).enabled) LocationPipeline.recordStatus(appContext, reason)
                LocationPipeline.reconcile(appContext, reason)
            } finally {
                pending.finish()
            }
        }
    }
}
