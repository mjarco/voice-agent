package com.voiceagent.voice_agent.location

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Places for the geofences, on `com.voiceagent/place_geofences`. Dart holds the
 * only copy of places (ADR-NET-006) and hands it over at load and after each
 * change; it is kept in [GeofenceConfig], so boot needs no Flutter. This is
 * the source until task 4, from which geofences come from the triggers.
 */
class PlaceGeofencesBridge(context: Context) : MethodChannel.MethodCallHandler {
    private val context = context.applicationContext
    private val mainThread = Handler(Looper.getMainLooper())

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "setPlaces") {
            result.notImplemented()
            return
        }
        GeofenceRegistry.executor.execute {
            try {
                val places = parse(call.arguments)
                val config = GeofenceConfig(context)
                val before = GeofenceRegistry.hashOf(config.places)
                config.places = places
                // Registers only if the places' geofences changed; a new name needs
                // none. A failed registration is taken up by the retry job, the app
                // start or a permission change, not by every hand-over.
                if (config.alertsEnabled && GeofenceRegistry.hashOf(places) != before) {
                    GeofenceRegistry.reconcileNow(context, "places_changed")
                }
                mainThread.post { result.success(null) }
            } catch (failure: Exception) {
                mainThread.post { result.error("place_geofences", failure.toString(), null) }
            }
        }
    }

    private fun parse(arguments: Any?): List<GeofencePlace> = (arguments as List<*>).map { raw ->
        val map = raw as Map<*, *>
        GeofencePlace(
            id = map["id"] as String,
            name = map["name"] as? String ?: "",
            latitude = (map["lat"] as Number).toDouble(),
            longitude = (map["lon"] as Number).toDouble(),
            radiusM = (map["radius_m"] as Number).toInt(),
        )
    }
}
