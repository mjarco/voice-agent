package com.voiceagent.voice_agent.location

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.os.SystemClock
import androidx.core.content.ContextCompat
import com.google.android.gms.location.CurrentLocationRequest
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * One fresh position for the Places screen, on `com.voiceagent/place_reading`.
 * It stands apart from the log's subscription: a place can be named with the
 * log off, and this reading is not a row of the log.
 */
class PlaceReadingBridge(context: Context) : MethodChannel.MethodCallHandler {
    private val context = context.applicationContext

    @SuppressLint("MissingPermission") // checked just above the call
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "currentReading") {
            result.notImplemented()
            return
        }
        val granted = listOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION)
            .any { ContextCompat.checkSelfPermission(context, it) == PackageManager.PERMISSION_GRANTED }
        if (!granted) {
            result.success(null)
            return
        }
        val request = CurrentLocationRequest.Builder()
            .setPriority(Priority.PRIORITY_HIGH_ACCURACY)
            .setMaxUpdateAgeMillis(MAX_AGE_MS)
            .setDurationMillis(WAIT_MS)
            .build()
        LocationServices.getFusedLocationProviderClient(context)
            .getCurrentLocation(request, null)
            .addOnSuccessListener { location ->
                result.success(
                    location?.let {
                        mapOf(
                            "latitude" to it.latitude,
                            "longitude" to it.longitude,
                            "accuracyM" to if (it.hasAccuracy()) it.accuracy.toDouble() else null,
                            "ageMs" to (SystemClock.elapsedRealtimeNanos() - it.elapsedRealtimeNanos) / 1_000_000,
                        )
                    },
                )
            }
            .addOnFailureListener { failure -> result.error("place_reading", failure.toString(), null) }
    }

    private companion object {
        const val MAX_AGE_MS = 15_000L
        const val WAIT_MS = 20_000L
    }
}
