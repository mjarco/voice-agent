package com.voiceagent.voice_agent.location

import kotlin.math.asin
import kotlin.math.cos
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * Sampling by motion (ADR-PLATFORM-014): what a transition of the Activity
 * Recognition Transition API does to the location log's subscription. Pure
 * Kotlin, so it is tested off the device; MotionReceiver maps the API's
 * constants to these names.
 *
 * Only ENTER transitions are asked for: entering one activity is leaving the
 * previous one. A moving activity switches to frequent readings at once;
 * `still` switches back only after [SETTLE_MS] without a new motion, because
 * traffic lights and jams report `still` and then a vehicle again. Frequent
 * readings also end when the phone has not moved [ANCHOR_RADIUS_M] for
 * [STATIONARY_MS], or no reading came for that long: a missed `still` must
 * not keep the GPS on for good (deep review of D1, H1 and H3).
 */
object Motion {
    const val STILL = "still"
    const val WALKING = "walking"
    const val RUNNING = "running"
    const val ON_BICYCLE = "on_bicycle"
    const val IN_VEHICLE = "in_vehicle"

    /** How long `still` must last before the log goes back to the background. */
    const val SETTLE_MS = 3 * 60 * 1000L

    /** How long frequent readings may go on without moving [ANCHOR_RADIUS_M]. */
    const val STATIONARY_MS = 10 * 60 * 1000L

    /** A reading further than this from the anchor counts as moving. */
    const val ANCHOR_RADIUS_M = 100.0

    const val SETTLED_STILL = "still"
    const val SETTLED_STATIONARY = "stationary"

    /** The interval of the readings while moving, by activity; null when not moving. */
    fun intervalSeconds(activity: String?): Int? = when (activity) {
        IN_VEHICLE -> 10
        ON_BICYCLE -> 15
        RUNNING, WALKING -> 30
        else -> null
    }

    fun isMoving(activity: String?): Boolean = intervalSeconds(activity) != null

    /**
     * What the log remembers of motion. [frequent] is whether readings are
     * frequent now; [activity] and [atMs] the last transition; [intervalS] the
     * interval of the last moving activity, kept through a `still` that has
     * not settled yet. The anchor is where the phone last moved
     * [ANCHOR_RADIUS_M] and when; with no position yet, the start of motion.
     */
    data class State(
        val frequent: Boolean = false,
        val activity: String? = null,
        val atMs: Long = 0,
        val intervalS: Int = LocationConfig.BACKGROUND_INTERVAL_S,
        val anchorLat: Double? = null,
        val anchorLon: Double? = null,
        val anchorAtMs: Long = 0,
    )

    /**
     * The state after one transition; an activity the log does not use changes
     * nothing. A start of motion anchors at [nowMs], when the frequent readings
     * start, not at the event's time: a batch can arrive late.
     */
    fun onTransition(state: State, activity: String, atMs: Long, nowMs: Long = atMs): State {
        val interval = intervalSeconds(activity)
        return when {
            // Already moving: another motion keeps the anchor.
            interval != null && state.frequent -> state.copy(activity = activity, atMs = atMs, intervalS = interval)
            interval != null -> State(frequent = true, activity = activity, atMs = atMs, intervalS = interval, anchorAtMs = nowMs)
            activity == STILL -> state.copy(activity = STILL, atMs = atMs)
            else -> state
        }
    }

    /** A frequent reading moves the anchor when it is the first or far enough from it. */
    fun onReading(state: State, latitude: Double, longitude: Double, atMs: Long): State {
        if (!state.frequent) return state
        val lat = state.anchorLat
        val lon = state.anchorLon
        if (lat == null || lon == null || distanceMeters(lat, lon, latitude, longitude) > ANCHOR_RADIUS_M) {
            return state.copy(anchorLat = latitude, anchorLon = longitude, anchorAtMs = atMs)
        }
        return state
    }

    /** Why frequent readings should end now, or null. */
    fun settleReason(state: State, nowMs: Long): String? = when {
        !state.frequent -> null
        state.activity == STILL && nowMs - state.atMs >= SETTLE_MS -> SETTLED_STILL
        nowMs - state.anchorAtMs >= STATIONARY_MS -> SETTLED_STATIONARY
        else -> null
    }

    fun shouldSettle(state: State, nowMs: Long): Boolean = settleReason(state, nowMs) != null

    /** Great-circle distance; enough for 100 m. */
    fun distanceMeters(lat1: Double, lon1: Double, lat2: Double, lon2: Double): Double {
        val r = 6_371_000.0
        val dLat = Math.toRadians(lat2 - lat1)
        val dLon = Math.toRadians(lon2 - lon1)
        val a = sin(dLat / 2).pow(2) + cos(Math.toRadians(lat1)) * cos(Math.toRadians(lat2)) * sin(dLon / 2).pow(2)
        return 2 * r * asin(sqrt(a))
    }
}
