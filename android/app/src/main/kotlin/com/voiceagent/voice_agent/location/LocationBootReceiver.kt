package com.voiceagent.voice_agent.location

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Settings

/** A subscription is assumed lost after a reboot or an update, so take it out again. */
class LocationBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val appContext = context.applicationContext
        val reason = when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED -> bootReason(appContext)
            Intent.ACTION_MY_PACKAGE_REPLACED -> "app_updated"
            else -> return
        }
        val pending = goAsync()
        LocationPipeline.write(appContext, done = { pending.finish() }) {
            if (LocationConfig(appContext).enabled) LocationPipeline.recordStatus(appContext, reason)
            LocationPipeline.reconcile(appContext, reason)
        }
    }

    /**
     * Android also sends BOOT_COMPLETED when a force-stopped app next runs, so
     * only the system's boot counter can tell a reboot from that.
     */
    private fun bootReason(context: Context): String {
        val config = LocationConfig(context)
        val boots = Settings.Global.getInt(context.contentResolver, Settings.Global.BOOT_COUNT, -1)
        val rebooted = boots != config.lastBootCount
        config.lastBootCount = boots
        return if (rebooted) "reboot" else "restart_after_stop"
    }
}
