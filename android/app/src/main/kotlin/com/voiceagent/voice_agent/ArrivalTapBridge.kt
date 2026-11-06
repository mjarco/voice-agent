package com.voiceagent.voice_agent

import android.content.Context
import android.content.Intent
import com.voiceagent.voice_agent.location.ArrivalNotifier
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * A tap on an arrival alert (ADR-NOTIF-003), on `com.voiceagent/arrival_tap`,
 * in ShareBridge's pattern (ADR-PLATFORM-008). Dart takes the route that
 * launched the app once, with `takeInitialRoute`; a later tap arrives as
 * `tapped`, so one tap reaches one channel. Dart checks the route.
 */
class ArrivalTapBridge(
    context: Context,
    private val channel: MethodChannel,
) : MethodChannel.MethodCallHandler {
    private val context = context.applicationContext
    private var pending: String? = null
    private var dartTookInitial = false

    fun accept(intent: Intent?) {
        if (intent == null || intent.action != ACTION) return
        // Recents redelivers the intent that started the task.
        if (intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY != 0) return
        val trigger = intent.getStringExtra(EXTRA_TRIGGER)
        val version = intent.getStringExtra(EXTRA_VERSION)
        val shown = intent.getStringExtra(EXTRA_SHOWN)
        if (trigger != null && version != null && shown != null) {
            ArrivalNotifier.tapped(context, trigger, version, shown)
        }
        val route = intent.getStringExtra(EXTRA_OPEN).orEmpty()
        if (dartTookInitial) {
            channel.invokeMethod("tapped", route)
        } else {
            pending = route
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "takeInitialRoute") {
            result.notImplemented()
            return
        }
        dartTookInitial = true
        result.success(pending)
        pending = null
    }

    companion object {
        const val ACTION = "com.voiceagent.voice_agent.ARRIVAL_TAPPED"
        const val EXTRA_TRIGGER = "trigger"
        const val EXTRA_VERSION = "v"
        const val EXTRA_SHOWN = "shown"
        const val EXTRA_OPEN = "open"
    }
}
