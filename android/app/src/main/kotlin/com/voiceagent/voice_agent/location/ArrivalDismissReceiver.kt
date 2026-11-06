package com.voiceagent.voice_agent.location

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import java.time.Instant
import org.json.JSONArray
import org.json.JSONObject

/**
 * An arrival alert swiped away (ADR-NOTIF-003): a `trigger.ignored` row naming
 * the `trigger.shown` it answers (04, section 7). Not exported; only the
 * alert's own delete intent reaches it.
 */
class ArrivalDismissReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION) return
        val trigger = intent.getStringExtra(EXTRA_TRIGGER) ?: return
        val version = intent.getStringExtra(EXTRA_VERSION) ?: return
        val shown = intent.getStringExtra(EXTRA_SHOWN) ?: return
        val appContext = context.applicationContext
        val at = Instant.now()
        val pending = goAsync()
        LocationPipeline.write(appContext, done = { pending.finish() }) {
            // With the switch off nothing is written.
            if (!GeofenceConfig(appContext).alertsEnabled) return@write
            LocationPipeline.recordStatus(
                appContext,
                "trigger.ignored",
                JSONObject().put("trigger", trigger).put("v", version).put("caused_by", JSONArray().put(shown)),
                at,
            )
            LocationPipeline.scheduleDrain(appContext)
        }
    }

    companion object {
        const val ACTION = "com.voiceagent.voice_agent.location.ARRIVAL_DISMISSED"
        const val EXTRA_TRIGGER = "trigger"
        const val EXTRA_VERSION = "v"
        const val EXTRA_SHOWN = "shown"
    }
}
