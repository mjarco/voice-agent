package com.voiceagent.voice_agent.location

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.Looper
import com.google.android.gms.location.FusedLocationProviderClient
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationResult
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority

/**
 * Foreground mode: readings as often as asked, with a permanent notification.
 * Separate from the hands-free service, which HandsFreeController stops when a
 * session ends, and which cannot start at boot because its type is microphone.
 */
class LocationForegroundService : Service() {
    private var client: FusedLocationProviderClient? = null

    private val callback = object : LocationCallback() {
        override fun onLocationResult(result: LocationResult) {
            val appContext = applicationContext
            val locations = result.locations
            LocationPipeline.write(appContext) {
                val config = LocationConfig(appContext)
                // A last reading can arrive after the switch went off.
                if (config.enabled) {
                    LocationPipeline.recordChanges(appContext, config)
                    LocationPipeline.recordReadings(appContext, locations, config)
                    LocationPipeline.sendNow(appContext)
                    // Motion mode ends its frequent readings here once `still` has lasted.
                    LocationPipeline.settleIfStill(appContext, config)
                }
            }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        try {
            val notification = buildNotification(LocationConfig(this))
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION)
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
            subscribe()
        } catch (failure: RuntimeException) {
            val appContext = applicationContext
            LocationPipeline.write(appContext) {
                LocationPipeline.recordStatus(appContext, "subscribe_failed", failure.toString())
                // Motion mode must not stay "frequent" with no subscription at all.
                LocationPipeline.fallBackFromForeground(appContext, LocationConfig(appContext), "service")
            }
            stopSelf()
            return START_NOT_STICKY
        }
        return START_STICKY
    }

    private fun subscribe() {
        val config = LocationConfig(this)
        val fused = client ?: LocationServices.getFusedLocationProviderClient(this).also { client = it }
        fused.removeLocationUpdates(callback)
        val request = LocationRequest.Builder(
            Priority.PRIORITY_HIGH_ACCURACY,
            config.intervalSeconds * 1000L,
        ).build()
        val appContext = applicationContext
        fused.requestLocationUpdates(request, callback, Looper.getMainLooper())
            .addOnFailureListener { failure ->
                LocationPipeline.write(appContext) {
                    LocationPipeline.recordStatus(appContext, "subscribe_failed", failure.toString())
                }
            }
    }

    override fun onDestroy() {
        client?.removeLocationUpdates(callback)
        super.onDestroy()
    }

    private fun buildNotification(config: LocationConfig): Notification {
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Dziennik lokalizacji", NotificationManager.IMPORTANCE_LOW),
            )
        }
        val open = packageManager.getLaunchIntentForPackage(packageName)?.let {
            PendingIntent.getActivity(this, 0, it, PendingIntent.FLAG_IMMUTABLE)
        }
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setContentTitle("Dziennik lokalizacji")
            .setContentText(
                if (config.mode == LocationConfig.MODE_MOTION) {
                    "W ruchu: odczyt co ${config.intervalSeconds} s"
                } else {
                    "Zapisuję lokalizację"
                },
            )
            .setOngoing(true)
            .setContentIntent(open)
            .build()
    }

    companion object {
        private const val CHANNEL_ID = "location_log"
        private const val NOTIFICATION_ID = 4102
    }
}
