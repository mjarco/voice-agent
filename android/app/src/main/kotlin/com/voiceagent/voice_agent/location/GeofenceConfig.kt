package com.voiceagent.voice_agent.location

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONArray
import org.json.JSONObject

/** A place as Dart hands it over, kept so boot needs no Flutter. */
data class GeofencePlace(
    val id: String,
    val name: String,
    val latitude: Double,
    val longitude: Double,
    val radiusM: Int,
)

/**
 * What the geofences of places remember (ADR-PLATFORM-010), in their own file,
 * apart from the location log's: the switch, the places last handed over, and
 * the set last registered.
 */
class GeofenceConfig(context: Context) {
    private val prefs: SharedPreferences =
        context.applicationContext.getSharedPreferences("geofences", Context.MODE_PRIVATE)

    /** "Alerty w sklepach". Off by default, and apart from the log's switch. */
    var alertsEnabled: Boolean
        get() = prefs.getBoolean("alerts_enabled", false)
        set(value) = prefs.edit().putBoolean("alerts_enabled", value).apply()

    /** In the order Dart sent them, which decides what the cap keeps. */
    var places: List<GeofencePlace>
        get() {
            val raw = prefs.getString("places", null) ?: return emptyList()
            val array = JSONArray(raw)
            return (0 until array.length()).map { i ->
                val o = array.getJSONObject(i)
                GeofencePlace(
                    id = o.getString("id"),
                    name = o.optString("name"),
                    latitude = o.getDouble("lat"),
                    longitude = o.getDouble("lon"),
                    radiusM = o.getInt("radius_m"),
                )
            }
        }
        set(value) {
            val array = JSONArray()
            for (p in value) {
                array.put(
                    JSONObject()
                        .put("id", p.id)
                        .put("name", p.name)
                        .put("lat", p.latitude)
                        .put("lon", p.longitude)
                        .put("radius_m", p.radiusM),
                )
            }
            prefs.edit().putString("places", array.toString()).apply()
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

    fun registered(ids: Set<String>, hash: String, atMs: Long) {
        prefs.edit()
            .putStringSet("registered_ids", ids)
            .putString("registered_hash", hash)
            .putLong("registered_at", atMs)
            .apply()
    }

    /** A registration failed: what is held is unknown, apart from these ids at most. */
    fun uncertain(ids: Set<String>) {
        prefs.edit()
            .putStringSet("registered_ids", ids)
            .remove("registered_hash")
            .remove("registered_at")
            .apply()
    }

    fun clearRegistration() {
        prefs.edit()
            .remove("registered_ids")
            .remove("registered_hash")
            .remove("registered_at")
            .apply()
    }
}
