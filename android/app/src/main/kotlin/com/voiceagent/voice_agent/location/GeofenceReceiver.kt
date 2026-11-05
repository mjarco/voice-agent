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
 * The system wakes this at a place's enter, dwell or exit (ADR-PLATFORM-010).
 * Each becomes a status row of the location log, named by the event types of
 * 03: `place.entered` for enter and dwell, `place.left` for exit.
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
                    GeofenceRegistry.lost(appContext)
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
        val places = config.places.associateBy { it.id }
        val fix = event.triggeringLocation
        for (geofence in event.triggeringGeofences.orEmpty()) {
            val place = places[geofence.requestId]
            val detail = JSONObject()
                .put("place", geofence.requestId)
                .put("transition", transition)
            place?.let {
                detail.put("name", it.name.takeCodePoints(MAX_NAME))
                detail.put("radius_m", GeofenceRegistry.radiusOf(it))
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
