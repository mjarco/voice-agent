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
 * [Visits] judges once per visit, and a firing transition posts the alert
 * (ADR-NOTIF-003).
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
        val set = config.triggerSet
        val triggers = set.triggers.associateBy { it.id }
        val fix = event.triggeringLocation
        val nowMs = receivedAt.toEpochMilli()
        // Withdrawn triggers' visits go first, so they cannot hold an alert back later.
        var visits = Visits.prune(config.visits, triggers.keys)
        for (geofence in event.triggeringGeofences.orEmpty()) {
            val trigger = triggers[geofence.requestId]
            val step = Visits.step(visits, geofence.requestId, trigger, transition, nowMs, set.maxVisitS)
            if (trigger != null && step.endedAtMs != null) {
                // The exit was missed: the visit ended by max_visit_s, dated at its end (04, section 5).
                val endedAt = Instant.ofEpochMilli(step.endedAtMs)
                LocationPipeline.recordStatus(context, "place.left", placeDetail(trigger, "max_visit"), endedAt)
            }
            val detail = if (trigger == null) {
                // A geofence of a set already replaced: only the trigger's id is known.
                JSONObject().put("trigger", geofence.requestId).put("transition", transition)
            } else {
                placeDetail(trigger, transition).apply {
                    if (status == "place.entered" && Triggers.expired(trigger, nowMs)) put("expired", true)
                }
            }
            if (fix != null) {
                detail.put("fix_at", Instant.ofEpochMilli(fix.time).toString())
                if (fix.hasAccuracy()) detail.put("accuracy_m", Math.round(fix.accuracy))
            }
            val rowId = LocationPipeline.recordStatus(context, status, detail, receivedAt)
            visits = step.visits
            // Saved before the alert: a restart right after must not post it again.
            config.visits = visits
            if (step.fire && trigger != null) ArrivalNotifier.fire(context, trigger, rowId, receivedAt)
        }
        config.visits = visits
    }

    private fun placeDetail(trigger: Trigger, transition: String): JSONObject = JSONObject()
        .put("place", trigger.place)
        .put("transition", transition)
        .put("trigger", trigger.id)
        .put("v", trigger.version)
        // The trigger carries no place name; its title starts with it.
        .put("name", trigger.title.takeCodePoints(MAX_NAME))
        .put("radius_m", Triggers.radiusOf(trigger))

    /** Cuts at a code point, so an emoji is never split in half. */
    private fun String.takeCodePoints(n: Int): String =
        if (codePointCount(0, length) <= n) this else substring(0, offsetByCodePoints(0, n))

    companion object {
        const val ACTION = "com.voiceagent.voice_agent.location.GEOFENCE"
        private const val MAX_NAME = 60
    }
}
