package com.voiceagent.voice_agent

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.util.Log
import io.flutter.plugin.common.EventChannel

/// Passes presses on the foreground notification's buttons to Dart
/// (ADR-AUDIO-015).
///
/// `flutter_foreground_task` builds the buttons, but it hands a press only
/// to Dart code running in its service, and voice-agent runs none there.
/// The press is a broadcast to this package, so a receiver of our own,
/// registered while the app's engine listens, catches it too. It depends
/// on two internal names of the plugin (9.2.2, `ForegroundService.kt`):
/// the action [PLUGIN_BUTTON_ACTION] and the extra [PLUGIN_BUTTON_ID]. Check
/// both when upgrading the plugin.
///
/// EventChannel `com.voiceagent/notification_actions/events` streams the
/// button ids ("pause", "resume", "stop").
class NotificationActionBridge(
    context: Context,
) : EventChannel.StreamHandler {

    private val appContext = context.applicationContext
    private var eventSink: EventChannel.EventSink? = null
    private var registered = false

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent == null) return
            if (intent.`package` != appContext.packageName) return
            val id = intent.getStringExtra(PLUGIN_BUTTON_ID)
            Log.d(TAG, "button pressed: $id")
            if (id != null) eventSink?.success(id)
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        register()
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
        unregister()
    }

    /// Stops listening when the engine that owns this bridge goes away.
    fun dispose() {
        eventSink = null
        unregister()
    }

    private fun register() {
        if (registered) return
        val filter = IntentFilter(PLUGIN_BUTTON_ACTION)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            appContext.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            appContext.registerReceiver(receiver, filter)
        }
        registered = true
    }

    private fun unregister() {
        if (!registered) return
        try {
            appContext.unregisterReceiver(receiver)
        } catch (e: IllegalArgumentException) {
            Log.w(TAG, "unregister failed", e)
        }
        registered = false
    }

    private companion object {
        const val TAG = "NotificationActionBridge"
        const val PLUGIN_BUTTON_ACTION = "onNotificationButtonPressed"
        const val PLUGIN_BUTTON_ID = "intentData"
    }
}
