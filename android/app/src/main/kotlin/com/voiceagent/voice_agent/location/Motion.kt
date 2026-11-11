package com.voiceagent.voice_agent.location

/**
 * Sampling by motion (ADR-PLATFORM-014): what a transition of the Activity
 * Recognition Transition API does to the location log's subscription. Pure
 * Kotlin, so it is tested off the device; MotionReceiver maps the API's
 * constants to these names.
 *
 * Only ENTER transitions are asked for: entering one activity is leaving the
 * previous one. A moving activity switches to frequent readings at once;
 * `still` switches back only after [SETTLE_MS] without a new motion, because
 * traffic lights and jams report `still` and then a vehicle again.
 */
object Motion {
    const val STILL = "still"
    const val WALKING = "walking"
    const val RUNNING = "running"
    const val ON_BICYCLE = "on_bicycle"
    const val IN_VEHICLE = "in_vehicle"

    /** How long `still` must last before the log goes back to the background. */
    const val SETTLE_MS = 3 * 60 * 1000L

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
     * not settled yet.
     */
    data class State(
        val frequent: Boolean = false,
        val activity: String? = null,
        val atMs: Long = 0,
        val intervalS: Int = LocationConfig.BACKGROUND_INTERVAL_S,
    )

    /** The state after one transition; an activity the log does not use changes nothing. */
    fun onTransition(state: State, activity: String, atMs: Long): State {
        val interval = intervalSeconds(activity)
        return when {
            interval != null -> State(frequent = true, activity = activity, atMs = atMs, intervalS = interval)
            activity == STILL -> state.copy(activity = STILL, atMs = atMs)
            else -> state
        }
    }

    /** Whether frequent readings should end now: `still` has lasted [SETTLE_MS]. */
    fun shouldSettle(state: State, nowMs: Long): Boolean =
        state.frequent && state.activity == STILL && nowMs - state.atMs >= SETTLE_MS
}
