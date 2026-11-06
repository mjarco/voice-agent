package com.voiceagent.voice_agent.location

import java.time.OffsetDateTime
import org.json.JSONArray
import org.json.JSONObject

/**
 * An armed trigger the phone can run (ADR-NET-007): the part of the trigger
 * contract goal 2 builds, `enter` with a dwell time, no guards, once per visit.
 */
data class Trigger(
    val id: String,
    val version: String,
    val place: String,
    val latitude: Double,
    val longitude: Double,
    val radiusM: Int,
    val dwellS: Int,
    val title: String,
    val expiresAtMs: Long,
    /** Shown as it comes (04, section 3); may be empty. */
    val body: String = "",
    /** The route a tap opens (04, section 6); Dart checks it. Empty: the start screen. */
    val open: String = "",
)

/** A trigger the phone cannot run, reported once per id and version. */
data class Rejection(val id: String, val version: String, val why: String) {
    val key: String get() = "$id|$version"
}

data class TriggerSet(
    val triggers: List<Trigger>,
    val rejected: List<Rejection>,
    val maxVisitS: Int,
)

/** The set does not follow the contract this phone knows; the old set stays. */
class TriggerSetException(message: String) : Exception(message)

/**
 * Reads the set of `GET /api/v1/triggers`, by the trigger contract
 * (workspace docs, `compilations/notification-triggers/reviewed/04-trigger-contract.md`).
 * Pure Kotlin and org.json, so it is tested off the device.
 */
object Triggers {
    const val CONTRACT = 1

    /** The smallest radius Android's geofencing is reliable at (04, section 4). */
    const val MIN_RADIUS_M = 150

    /** Play services refuses a longer request id, and with it the whole batch. */
    const val MAX_ID_LENGTH = 100

    /** A dwell longer than a day is no arrival; it also keeps `dwell_s * 1000` in an Int. */
    const val MAX_DWELL_S = 86_400

    /** A route longer than this opens nothing; no route of the app comes near it. */
    const val MAX_OPEN_LENGTH = 300

    /** 04, section 5: a visit with no exit ends after 6 hours. */
    const val DEFAULT_MAX_VISIT_S = 21_600

    /** The API's envelope, `{"data": <set>}`. */
    fun parseEnvelope(body: String): TriggerSet {
        val envelope = try {
            JSONObject(body)
        } catch (failure: Exception) {
            throw TriggerSetException("not JSON")
        } catch (_: StackOverflowError) {
            // org.json parses recursively; an Error would end the process.
            throw TriggerSetException("nested too deep")
        }
        val data = envelope.optJSONObject("data") ?: throw TriggerSetException("no data")
        return parse(data)
    }

    /** The inner set, as stored on disk. */
    fun parse(set: JSONObject): TriggerSet {
        val contract = set.opt("contract")
        if (contract !is Number || contract.toInt() != CONTRACT || contract.toDouble() != CONTRACT.toDouble()) {
            throw TriggerSetException("contract $contract")
        }
        val array = set.opt("triggers") as? JSONArray ?: throw TriggerSetException("no triggers")
        val maxVisitS = set.optJSONObject("detectors")?.let { positiveInt(it, "max_visit_s") }
            ?: DEFAULT_MAX_VISIT_S
        val triggers = mutableListOf<Trigger>()
        val rejected = mutableListOf<Rejection>()
        val seen = mutableSetOf<String>()
        for (i in 0 until array.length()) {
            val raw = array.opt(i) as? JSONObject
            if (raw == null) {
                rejected += Rejection("", "", "not an object at $i")
                continue
            }
            when (val read = read(raw)) {
                is Read.Ok -> if (seen.add(read.trigger.id)) {
                    triggers += read.trigger
                } else {
                    rejected += Rejection(read.trigger.id, read.trigger.version, "duplicate id")
                }
                is Read.Rejected -> rejected += read.rejection
            }
        }
        return TriggerSet(triggers, rejected, maxVisitS)
    }

    /** The set without `compiled_at`, to tell a changed set from a recompiled one. */
    fun contentOf(json: String): String = try {
        canonical(JSONObject(json).apply { remove("compiled_at") })
    } catch (_: Exception) {
        json
    } catch (_: StackOverflowError) {
        json
    }

    /** JSON with keys sorted at every level, so equal sets give equal text. */
    private fun canonical(value: Any?): String = when (value) {
        is JSONObject -> value.keys().asSequence().toList().sorted()
            .joinToString(",", "{", "}") { JSONObject.quote(it) + ":" + canonical(value.opt(it)) }
        is JSONArray -> (0 until value.length()).joinToString(",", "[", "]") { canonical(value.opt(it)) }
        is String -> JSONObject.quote(value)
        null -> "null"
        else -> value.toString()
    }

    /** The geofence's radius. */
    fun radiusOf(trigger: Trigger): Int = maxOf(trigger.radiusM, MIN_RADIUS_M)

    /**
     * What a geofence is made of. The version and the text are left out, so a
     * new list at the same store does not add the geofence again and reset a
     * visit in progress.
     */
    fun geofenceKey(trigger: Trigger): String =
        "${trigger.id}|${trigger.latitude}|${trigger.longitude}|${radiusOf(trigger)}|${trigger.dwellS}"

    fun expired(trigger: Trigger, nowMs: Long): Boolean = nowMs >= trigger.expiresAtMs

    /**
     * Whether this transition is the one the trigger fires on: the dwell when
     * `dwell_s` > 0, the enter when it is 0, and never once expired. Once per
     * visit is judged by [Visits].
     */
    fun wouldFire(trigger: Trigger, transition: String, nowMs: Long): Boolean {
        if (expired(trigger, nowMs)) return false
        return if (trigger.dwellS > 0) transition == "dwell" else transition == "enter"
    }

    private sealed class Read {
        data class Ok(val trigger: Trigger) : Read()
        data class Rejected(val rejection: Rejection) : Read()
    }

    private fun read(raw: JSONObject): Read {
        val id = string(raw, "id") ?: ""
        val version = string(raw, "version") ?: ""
        fun reject(why: String) = Read.Rejected(Rejection(id.take(MAX_ID_LENGTH), version.take(MAX_ID_LENGTH), why))
        if (id.isEmpty()) return reject("missing id")
        if (id.length > MAX_ID_LENGTH) return reject("id too long")
        if (version.isEmpty()) return reject("missing version")
        // Every report carries it; a long one would push caused_by out of the row's 500 characters.
        if (version.length > MAX_ID_LENGTH) return reject("version too long")

        val condition = raw.optJSONObject("when") ?: return reject("missing when")
        val kinds = condition.keys().asSequence().toList().sorted()
        if (kinds.size != 1) return reject("conditions ${kinds.joinToString(",").ifEmpty { "none" }}")
        if (kinds[0] != "enter") return reject("condition ${kinds[0]}")
        val enter = condition.optJSONObject("enter") ?: return reject("missing when.enter")

        raw.opt("guards")?.let { guards ->
            if (guards != JSONObject.NULL) {
                val names = (guards as? JSONObject)?.keys()?.asSequence()?.toList()?.sorted()
                    ?: return reject("guards not an object")
                if (names.isNotEmpty()) return reject("guard ${names[0]}")
            }
        }
        val once = string(raw, "once") ?: ""
        if (once != "per_visit") return reject("once ${once.ifEmpty { "missing" }.take(40)}")

        val show = raw.optJSONObject("show") ?: return reject("missing show")
        val surfaces = show.opt("surfaces") as? JSONArray ?: return reject("missing show.surfaces")
        if ((0 until surfaces.length()).none { surfaces.opt(it) == "phone" }) return reject("no phone surface")

        val place = string(enter, "place") ?: return reject("missing place")
        if (place.length > MAX_ID_LENGTH) return reject("place too long")
        val lat = number(enter, "lat") ?: return reject("missing lat")
        val lon = number(enter, "lon") ?: return reject("missing lon")
        if (lat !in -90.0..90.0 || lon !in -180.0..180.0) return reject("coordinates out of range")
        val radius = positiveInt(enter, "radius_m") ?: return reject("missing radius_m")
        val dwell = nonNegativeInt(enter, "dwell_s") ?: return reject("missing dwell_s")
        if (dwell > MAX_DWELL_S) return reject("dwell_s too long")
        val title = string(show, "title") ?: return reject("missing show.title")
        val body = string(show, "body") ?: ""
        val open = (string(show, "open") ?: "").takeIf { it.length <= MAX_OPEN_LENGTH } ?: ""
        val expires = (string(raw, "expires_at") ?: "").let { text ->
            try {
                OffsetDateTime.parse(text).toInstant().toEpochMilli()
            } catch (_: Exception) {
                return reject("missing expires_at")
            }
        }
        return Read.Ok(Trigger(id, version, place, lat, lon, radius, dwell, title, expires, body, open))
    }

    /**
     * A non-empty string, or null. Not `optString`: Android's returns the text
     * "null" for a JSON null, the JVM's the fallback, so the tests would not
     * model the phone.
     */
    private fun string(o: JSONObject, name: String): String? = (o.opt(name) as? String)?.ifEmpty { null }

    private fun number(o: JSONObject, name: String): Double? =
        (o.opt(name) as? Number)?.toDouble()?.takeIf { it.isFinite() }

    private fun nonNegativeInt(o: JSONObject, name: String): Int? {
        val n = o.opt(name) as? Number ?: return null
        val d = n.toDouble()
        if (d != Math.floor(d) || d < 0 || d > Int.MAX_VALUE) return null
        return d.toInt()
    }

    private fun positiveInt(o: JSONObject, name: String): Int? = nonNegativeInt(o, name)?.takeIf { it > 0 }
}
