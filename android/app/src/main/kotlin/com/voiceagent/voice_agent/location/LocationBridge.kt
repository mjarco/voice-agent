package com.voiceagent.voice_agent.location

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Settings' view of the pipeline, on `com.voiceagent/location_log`. */
class LocationBridge(context: Context) : MethodChannel.MethodCallHandler {
    private val context = context.applicationContext
    private val mainThread = Handler(Looper.getMainLooper())

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        // Registering waits on Play services, so it never runs on the pipeline's thread.
        val executor = if (call.method == "setAlertsEnabled") GeofenceRegistry.executor else LocationPipeline.executor
        executor.execute {
            try {
                val reply = handle(call)
                mainThread.post { if (reply === NOT_IMPLEMENTED) result.notImplemented() else result.success(reply) }
            } catch (failure: Exception) {
                mainThread.post { result.error("location_log", failure.toString(), null) }
            }
        }
    }

    private fun handle(call: MethodCall): Any? {
        val config = LocationConfig(context)
        val geofences = GeofenceConfig(context)
        when (call.method) {
            "getState" -> return mapOf(
                "enabled" to config.enabled,
                "mode" to config.mode,
                "foregroundIntervalSeconds" to config.foregroundIntervalSeconds,
                "effectiveMode" to config.effectiveMode,
                "intervalSeconds" to config.intervalSeconds,
                "motionPermission" to MotionTransitions.permissionGranted(context),
                "motionActivity" to config.motion.activity,
                "motionAtMs" to config.motion.atMs,
                "permission" to LocationPipeline.permission(context),
                "lastReadingAtMs" to config.lastReadingAtMs,
                "lastSentAtMs" to config.lastSentAtMs,
                "queueLength" to LocationStore.get(context).count(),
                "lastError" to config.lastError,
                "alertsEnabled" to geofences.alertsEnabled,
                "geofenceCount" to geofences.registeredCount,
                "geofencesAtMs" to geofences.registeredAtMs,
                "triggerCount" to geofences.triggers.size,
                "triggersCheckedAtMs" to geofences.triggersCheckedAtMs,
            )
            "setCredentials" -> {
                config.apiUrl = call.argument<String>("apiUrl")
                config.token = call.argument<String>("token")
            }
            "setEnabled" -> {
                val enabled = call.argument<Boolean>("enabled") == true
                if (enabled != config.enabled) {
                    config.enabled = enabled
                    LocationPipeline.recordStatus(context, if (enabled) "start" else "stop", "switch in Settings")
                    LocationPipeline.reconcile(context, "switch")
                }
            }
            // "Alerty w sklepach": the triggers' geofences, apart from the log's switch.
            "setAlertsEnabled" -> {
                val enabled = call.argument<Boolean>("enabled") == true
                if (enabled != geofences.alertsEnabled) {
                    geofences.alertsEnabled = enabled
                    if (!enabled) {
                        TriggerPuller.cancel(context)
                        // The next switch on pulls afresh (ADR-NET-007).
                        geofences.clearTriggers()
                        // Visits live on the pipeline's thread (ADR-NOTIF-003): queued
                        // there, after any broadcast already being written.
                        LocationPipeline.write(context) { geofences.clearVisits() }
                    }
                    // On the registry's thread (see above), so the reply comes once registered.
                    GeofenceRegistry.reconcileNow(context, GeofenceRegistry.REASON_SWITCH)
                    if (enabled) {
                        ArrivalNotifier.ensureChannel(context)
                        TriggerPuller.schedule(context)
                        TriggerPuller.pullLater(context, TriggerPuller.REASON_SWITCH)
                    }
                }
            }
            "setMode" -> {
                val mode = call.argument<String>("mode")
                require(
                    mode == LocationConfig.MODE_BACKGROUND ||
                        mode == LocationConfig.MODE_FOREGROUND ||
                        mode == LocationConfig.MODE_MOTION,
                )
                if (mode != config.mode) {
                    config.mode = mode
                    // Each mode starts from the background readings; motion waits for a transition.
                    config.motion = Motion.State()
                    if (config.enabled) LocationPipeline.reconcile(context, "mode changed")
                }
            }
            "setForegroundInterval" -> {
                config.foregroundIntervalSeconds = requireNotNull(call.argument<Int>("seconds"))
                if (config.enabled) LocationPipeline.reconcile(context, "interval changed")
            }
            "openAppSettings" -> context.startActivity(
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", context.packageName, null))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
            // A return to the app: "always" may have been granted on the settings
            // page, and the triggers may be due (at most once per 5 minutes).
            "appResumed" -> {
                GeofenceRegistry.permissionMayHaveChanged(context)
                TriggerPuller.appResumed(context)
            }
            "reconcile" -> {
                try {
                    LocationPipeline.reconcile(context, "app_start")
                } finally {
                    GeofenceRegistry.reconcileLater(context, RegistrationPlan.REASON_APP_START)
                    if (geofences.alertsEnabled) {
                        TriggerPuller.schedule(context)
                        TriggerPuller.pullLater(context, TriggerPuller.REASON_APP_START)
                    }
                }
            }
            else -> return NOT_IMPLEMENTED
        }
        return null
    }

    private companion object {
        val NOT_IMPLEMENTED = Any()
    }
}
