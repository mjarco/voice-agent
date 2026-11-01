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
        LocationPipeline.executor.execute {
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
        when (call.method) {
            "getState" -> return mapOf(
                "enabled" to config.enabled,
                "mode" to config.mode,
                "foregroundIntervalSeconds" to config.foregroundIntervalSeconds,
                "permission" to LocationPipeline.permission(context),
                "lastReadingAtMs" to config.lastReadingAtMs,
                "lastSentAtMs" to config.lastSentAtMs,
                "queueLength" to LocationStore.get(context).count(),
                "lastError" to config.lastError,
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
            "setMode" -> {
                val mode = call.argument<String>("mode")
                require(mode == LocationConfig.MODE_BACKGROUND || mode == LocationConfig.MODE_FOREGROUND)
                if (mode != config.mode) {
                    config.mode = mode
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
            "reconcile" -> LocationPipeline.reconcile(context, "app_start")
            else -> return NOT_IMPLEMENTED
        }
        return null
    }

    private companion object {
        val NOT_IMPLEMENTED = Any()
    }
}
