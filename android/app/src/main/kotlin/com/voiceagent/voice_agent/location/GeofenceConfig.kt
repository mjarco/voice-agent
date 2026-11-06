package com.voiceagent.voice_agent.location

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONObject

/**
 * What the geofences remember (ADR-PLATFORM-010, ADR-NET-007), in their own
 * file, apart from the location log's: the switch, the trigger set last pulled,
 * and the geofences last registered.
 */
class GeofenceConfig(context: Context) {
    private val prefs: SharedPreferences =
        context.applicationContext.getSharedPreferences("geofences", Context.MODE_PRIVATE)

    /** "Alerty w sklepach". Off by default, and apart from the log's switch. */
    var alertsEnabled: Boolean
        get() = prefs.getBoolean("alerts_enabled", false)
        set(value) = prefs.edit().putBoolean("alerts_enabled", value).apply()

    /** The inner set as personal-agent sent it, `{"contract":1,…}`; null before the first pull. */
    val triggerSetJson: String?
        get() = prefs.getString("trigger_set", null)

    /** The set's `ETag`, exactly as received (weak behind Cloudflare). */
    val triggersEtag: String?
        get() = prefs.getString("triggers_etag", null)

    /** The last pull that personal-agent answered, with 200 or 304. */
    val triggersCheckedAtMs: Long
        get() = prefs.getLong("triggers_checked_at", 0)

    /** The last pull tried, answered or not; a return to the app waits on it. */
    var triggersTriedAtMs: Long
        get() = prefs.getLong("triggers_tried_at", 0)
        set(value) = prefs.edit().putLong("triggers_tried_at", value).apply()

    /** A pull failed and none has worked since: the next failure writes no row. */
    var triggersFailing: Boolean
        get() = prefs.getBoolean("triggers_failing", false)
        set(value) = prefs.edit().putBoolean("triggers_failing", value).apply()

    /** `id|version` of each rejected trigger already reported (04, section 4). */
    var rejectedReported: Set<String>
        get() = prefs.getStringSet("rejected_reported", null)?.toSet() ?: emptySet()
        set(value) = prefs.edit().putStringSet("rejected_reported", value).apply()

    /** The stored set, read; empty before the first pull or if it cannot be read. */
    val triggerSet: TriggerSet
        get() = triggerSetJson?.let {
            try {
                Triggers.parse(JSONObject(it))
            } catch (_: Exception) {
                null
            }
        } ?: TriggerSet(emptyList(), emptyList(), Triggers.DEFAULT_MAX_VISIT_S)

    val triggers: List<Trigger>
        get() = triggerSet.triggers

    /** A 200: the new set replaces the old as a whole (04, section 2). */
    fun storeTriggers(json: String, etag: String?, atMs: Long) {
        prefs.edit()
            .putString("trigger_set", json)
            .putString("triggers_etag", etag)
            .putLong("triggers_checked_at", atMs)
            // Task 3's places, handed over by Dart, are no longer read.
            .remove("places")
            .apply()
    }

    /** A 304: the set stands. */
    fun triggersChecked(atMs: Long) {
        prefs.edit().putLong("triggers_checked_at", atMs).apply()
    }

    /**
     * Visits in progress (ADR-NOTIF-003). Read and written only on the
     * pipeline's thread, so a broadcast and the switch never interleave; saved
     * with `commit`, so a restart right after an alert does not fire it again.
     */
    var visits: Map<String, Visit>
        get() = Visits.fromJson(prefs.getString("visits", null))
        set(value) {
            prefs.edit().putString("visits", Visits.toJson(value)).commit()
        }

    /** The switch went off: the next switch on starts with no visit. Pipeline's thread. */
    fun clearVisits() {
        prefs.edit().remove("visits").commit()
    }

    /** The switch went off: the next switch on pulls afresh. */
    fun clearTriggers() {
        prefs.edit()
            .remove("trigger_set")
            .remove("triggers_etag")
            .remove("triggers_checked_at")
            .remove("triggers_tried_at")
            .remove("triggers_failing")
            .remove("rejected_reported")
            .apply()
    }

    /**
     * Every id Play services may hold. After a failure it keeps the ids of
     * before and of the attempt, so the next registration removes what is stale.
     */
    val registeredIds: Set<String>
        get() = prefs.getStringSet("registered_ids", null)?.toSet() ?: emptySet()

    /** Geofences known to be registered: none while the state is uncertain. */
    val registeredCount: Int
        get() = if (registeredHash == null) 0 else registeredIds.size

    /** The hash of the set last registered; null when nothing is, or nobody knows. */
    val registeredHash: String?
        get() = prefs.getString("registered_hash", null)

    val registeredAtMs: Long
        get() = prefs.getLong("registered_at", 0)

    /** A GEOFENCE_NOT_AVAILABLE came, and no registration has worked since. */
    var degraded: Boolean
        get() = prefs.getBoolean("degraded", false)
        set(value) = prefs.edit().putBoolean("degraded", value).apply()

    /** The location permission at the last registration, to see a change on return. */
    var lastPermission: String?
        get() = prefs.getString("last_permission", null)
        set(value) = prefs.edit().putString("last_permission", value).apply()

    /** What each registered geofence was made of, to add only the changed ones. */
    val registeredKeys: Set<String>
        get() = if (registeredHash == null) {
            emptySet()
        } else {
            prefs.getStringSet("registered_keys", null)?.toSet() ?: emptySet()
        }

    fun registered(ids: Set<String>, keys: Set<String>, hash: String, atMs: Long) {
        prefs.edit()
            .putStringSet("registered_ids", ids)
            .putStringSet("registered_keys", keys)
            .putString("registered_hash", hash)
            .putLong("registered_at", atMs)
            .apply()
    }

    /** A registration failed: what is held is unknown, apart from these ids at most. */
    fun uncertain(ids: Set<String>) {
        prefs.edit()
            .putStringSet("registered_ids", ids)
            .remove("registered_keys")
            .remove("registered_hash")
            .remove("registered_at")
            .apply()
    }

    fun clearRegistration() {
        prefs.edit()
            .remove("registered_ids")
            .remove("registered_keys")
            .remove("registered_hash")
            .remove("registered_at")
            .apply()
    }
}
