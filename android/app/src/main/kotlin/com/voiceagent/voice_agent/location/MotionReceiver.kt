package com.voiceagent.voice_agent.location

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.SystemClock
import com.google.android.gms.location.ActivityTransition
import com.google.android.gms.location.ActivityTransitionResult
import java.time.Instant
import org.json.JSONObject

/**
 * Activity transitions (ADR-PLATFORM-014). Each is a status row of the log;
 * a start of motion switches to frequent readings. Started by such an event,
 * the app may start its foreground service from the background (Android 12+).
 */
class MotionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (!ActivityTransitionResult.hasResult(intent)) return
        val result = ActivityTransitionResult.extractResult(intent) ?: return
        val appContext = context.applicationContext
        val pending = goAsync()
        val nowMs = System.currentTimeMillis()
        val nowElapsedNanos = SystemClock.elapsedRealtimeNanos()
        LocationPipeline.write(appContext, done = { pending.finish() }) {
            val config = LocationConfig(appContext)
            // A last event can arrive after the mode or the switch changed.
            if (!config.enabled || config.mode != LocationConfig.MODE_MOTION) return@write
            val before = config.motion
            var state = before
            for (event in result.transitionEvents) {
                if (event.transitionType != ActivityTransition.ACTIVITY_TRANSITION_ENTER) continue
                val activity = MotionTransitions.name(event.activityType) ?: continue
                val atMs = nowMs - (nowElapsedNanos - event.elapsedRealTimeNanos) / 1_000_000
                LocationPipeline.recordStatus(
                    appContext,
                    "activity",
                    JSONObject().put("activity", activity).put("at", Instant.ofEpochMilli(atMs).toString()),
                )
                state = Motion.onTransition(state, activity, atMs, nowMs)
            }
            // A late batch can end in a `still` already settled: no start for nothing (deep review of D1, L1).
            if (Motion.settleReason(state, nowMs) == Motion.SETTLED_STILL) state = state.copy(frequent = false)
            config.motion = state
            // A start or an end of motion, or another motion with another interval.
            if (state.frequent != before.frequent || (state.frequent && state.intervalS != before.intervalS)) {
                LocationPipeline.reconcile(appContext, "motion: ${state.activity}", renewTransitions = false)
            }
        }
    }

    companion object {
        const val ACTION = "com.voiceagent.voice_agent.location.MOTION"
    }
}
