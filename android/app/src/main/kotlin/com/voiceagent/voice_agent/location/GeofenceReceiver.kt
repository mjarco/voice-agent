package com.voiceagent.voice_agent.location

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofenceStatusCodes
import com.google.android.gms.location.GeofencingEvent
import java.time.Instant
import org.json.JSONObject

/**
 * The system wakes this at a trigger's enter, dwell or exit (ADR-PLATFORM-010,
 * ADR-NET-007). Each becomes a status row of the location log, named by the
 * event types of 03: `place.entered` for enter and dwell, `place.left` for exit.
 * An enter or dwell row says whether the trigger would fire; nothing is shown
 * until task 5, which also judges once per visit.
 */
class GeofenceReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val event = GeofencingEvent.fromIntent(intent) ?: return
        val appContext = context.applicationContext
        val receivedAt = Instant.now()
        val pending = goAsync()
        var sending = false
        LocationPipeline.write(appContext, done = { if (!sending) pending.finish() }) {
            val config = GeofenceConfig(appContext)
            // A late broadcast after the switch went off writes nothing.
            if (!config.alertsEnabled) return@write
            if (event.hasError()) {
                if (event.errorCode == GeofenceStatusCodes.GEOFENCE_NOT_AVAILABLE) {
                    // The wake-up lasts until the registry's thread has taken it.
                    sending = true
                    GeofenceRegistry.lostLater(appContext) { pending.finish() }
                    return@write
                } else {
                    LocationPipeline.recordStatus(
                        appContext,
                        "geofences_failed",
                        JSONObject().put("code", event.errorCode).put("reason", "event"),
                    )
                }
            } else {
                record(appContext, config, event, receivedAt)
            }
            // If a send is already running it may miss these rows; the drain job takes them.
            LocationPipeline.scheduleDrain(appContext)
            // The wake-up must outlive the send, or the process may go first.
            sending = true
            LocationPipeline.sendNow(appContext) { pending.finish() }
        }
    }

    private fun record(context: Context, config: GeofenceConfig, event: GeofencingEvent, receivedAt: Instant) {
        val (status, transition) = when (event.geofenceTransition) {
            Geofence.GEOFENCE_TRANSITION_ENTER -> "place.entered" to "enter"
            Geofence.GEOFENCE_TRANSITION_DWELL -> "place.entered" to "dwell"
            Geofence.GEOFENCE_TRANSITION_EXIT -> "place.left" to "exit"
            else -> return
        }
        val triggers = config.triggers.associateBy { it.id }
        val fix = event.triggeringLocation
        val nowMs = receivedAt.toEpochMilli()
        for (geofence in event.triggeringGeofences.orEmpty()) {
            val trigger = triggers[geofence.requestId]
            val detail = JSONObject()
            if (trigger == null) {
                // A geofence of a set already replaced: only the trigger's id is known.
                detail.put("trigger", geofence.requestId).put("transition", transition)
            } else {
                detail.put("place", trigger.place)
                    .put("transition", transition)
                    .put("trigger", trigger.id)
                    .put("v", trigger.version)
                    // The trigger carries no place name; its title starts with it.
                    .put("name", trigger.title.takeCodePoints(MAX_NAME))
                    .put("radius_m", Triggers.radiusOf(trigger))
                if (status == "place.entered") {
                    detail.put("would_fire", Triggers.wouldFire(trigger, transition, nowMs))
                    if (Triggers.expired(trigger, nowMs)) detail.put("expired", true)
                }
            }
            if (fix != null) {
                detail.put("fix_at", Instant.ofEpochMilli(fix.time).toString())
                if (fix.hasAccuracy()) detail.put("accuracy_m", Math.round(fix.accuracy))
            }
            LocationPipeline.recordStatus(context, status, detail, receivedAt)
        }
    }

    /** Cuts at a code point, so an emoji is never split in half. */
    private fun String.takeCodePoints(n: Int): String =
        if (codePointCount(0, length) <= n) this else substring(0, offsetByCodePoints(0, n))

    companion object {
        const val ACTION = "com.voiceagent.voice_agent.location.GEOFENCE"
        private const val MAX_NAME = 60
    }
}
