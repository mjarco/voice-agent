package com.voiceagent.voice_agent.location

/**
 * What one registration of geofences does (ADR-PLATFORM-010 item 3,
 * ADR-PLATFORM-011): which geofences it adds, which it removes, and which
 * visits it forgets. Pure Kotlin, so it is tested off the device; the registry
 * does the calls to Play services.
 */
object RegistrationPlan {
    /** The app started, and found its registration. */
    const val REASON_APP_START = "app_start"

    /**
     * The boot broadcast with no reboot: Android sends it at the next start
     * after a force stop, and on Android 17 after a plain process kill too.
     */
    const val REASON_RESTART_AFTER_STOP = "restart_after_stop"

    const val REASON_TRIGGERS = "triggers_changed"

    /**
     * Reasons after which Play services may still hold what was registered:
     * the app start, a restart after the process ended, and a new trigger set.
     * Whether it does is the caller's `standing`. For these only new or changed
     * geofences are added: adding one again replaces it and resets its state,
     * so a visit in progress would lose its enter and dwell. Every other reason
     * (boot, update, retry, the switch, a permission change) adds them all.
     */
    val KEEPING_REASONS = setOf(REASON_APP_START, REASON_RESTART_AFTER_STOP, REASON_TRIGGERS)

    data class Plan(
        /** The last registration stands, so only what changed is added. */
        val intact: Boolean,
        val toAdd: List<Trigger>,
        /** Held, and no longer in the set. */
        val gone: Set<String>,
        /** Visits to forget: only those of triggers withdrawn from the set. */
        val forget: Set<String>,
    )

    /**
     * [standing] says the last registration is still held: its hash is known,
     * location was not lost, and the intent survived (a force stop cancels it).
     */
    fun of(
        reason: String,
        standing: Boolean,
        chosen: List<Trigger>,
        held: Set<String>,
        heldKeys: Set<String>,
    ): Plan {
        val intact = reason in KEEPING_REASONS && standing
        val toAdd = if (intact) chosen.filter { Triggers.geofenceKey(it) !in heldKeys } else chosen
        val gone = held - chosen.map { it.id }.toSet()
        // A geofence added again keeps its trigger's visit: added while you stand
        // inside, Play services may still report a dwell (T17), and the visit's
        // once must hold it. If the exit was missed meanwhile, the visit ends at
        // the next transition after max_visit_s (Visits.step).
        return Plan(intact, toAdd, gone, forget = gone)
    }
}
