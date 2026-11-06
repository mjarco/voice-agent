package com.voiceagent.voice_agent.location

import org.json.JSONObject

/** A visit in progress at a trigger's place (04, section 5); outside, there is none. */
data class Visit(val startedAtMs: Long, val fired: Boolean)

/**
 * Visits and `once: per_visit` (ADR-NOTIF-003): which transition fires, at most
 * once per visit per trigger id. Pure Kotlin and org.json, so it is tested off
 * the device. The state is keyed by id, never by version, so a new list at the
 * same store mid-visit does not fire again.
 */
object Visits {
    /** What one transition of one trigger does. */
    data class Step(
        val visits: Map<String, Visit>,
        /** A visit had outlived `max_visit_s` with no exit, and ended at this time. */
        val endedAtMs: Long?,
        /** Post the notification now. */
        val fire: Boolean,
    )

    /**
     * [transition] is `enter`, `dwell` or `exit`. [trigger] is null for an id
     * no longer in the set, whose visit is dropped with no row.
     */
    fun step(
        visits: Map<String, Visit>,
        id: String,
        trigger: Trigger?,
        transition: String,
        nowMs: Long,
        maxVisitS: Int,
    ): Step {
        val out = visits.toMutableMap()
        if (trigger == null || transition == "exit") {
            out.remove(id)
            return Step(out, null, false)
        }
        var visit = out[id]
        var endedAtMs: Long? = null
        // A missed exit: the visit ended max_visit_s after it began.
        if (visit != null && nowMs - visit.startedAtMs >= maxVisitS * 1000L) {
            endedAtMs = visit.startedAtMs + maxVisitS * 1000L
            visit = null
        }
        // An enter, or a dwell whose enter never came, begins a visit.
        val current = visit ?: Visit(nowMs, fired = false)
        val fire = !current.fired && Triggers.wouldFire(trigger, transition, nowMs)
        out[id] = if (fire) current.copy(fired = true) else current
        return Step(out, endedAtMs, fire)
    }

    /** The visits of triggers withdrawn from the set are forgotten. */
    fun prune(visits: Map<String, Visit>, ids: Set<String>): Map<String, Visit> =
        visits.filterKeys { it in ids }

    fun toJson(visits: Map<String, Visit>): String {
        val o = JSONObject()
        for ((id, visit) in visits) {
            o.put(id, JSONObject().put("started_at_ms", visit.startedAtMs).put("fired", visit.fired))
        }
        return o.toString()
    }

    /** Unreadable state counts as no visit: at worst one alert too many, never a crash. */
    fun fromJson(text: String?): Map<String, Visit> {
        if (text.isNullOrEmpty()) return emptyMap()
        val o = try {
            JSONObject(text)
        } catch (_: Exception) {
            return emptyMap()
        }
        val out = mutableMapOf<String, Visit>()
        for (id in o.keys()) {
            val v = o.optJSONObject(id) ?: continue
            val started = v.opt("started_at_ms") as? Number ?: continue
            val fired = v.opt("fired") as? Boolean ?: continue
            out[id] = Visit(started.toLong(), fired)
        }
        return out
    }
}
