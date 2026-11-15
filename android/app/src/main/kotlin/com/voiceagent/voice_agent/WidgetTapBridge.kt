package com.voiceagent.voice_agent

import android.content.Intent
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * A tap on the home-screen widget (ADR-PLATFORM-015), on `com.voiceagent/widget_tap`, in
 * ArrivalTapBridge's pattern (ADR-PLATFORM-008): Dart takes the tap that launched the app once,
 * with `takeInitialTap`; a later tap arrives as `tapped`, so one tap reaches one channel.
 */
class WidgetTapBridge(private val channel: MethodChannel) : MethodChannel.MethodCallHandler {
    private var pending: String? = null
    private var dartTookInitial = false

    fun accept(intent: Intent?) {
        if (intent == null || intent.action != ACTION) return
        // Recents redelivers the intent that started the task: the mic would listen again.
        if (intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY != 0) return
        val tap = intent.getStringExtra(EXTRA_TAP) ?: return
        if (dartTookInitial) {
            channel.invokeMethod("tapped", tap)
        } else {
            pending = tap
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "takeInitialTap") {
            result.notImplemented()
            return
        }
        dartTookInitial = true
        result.success(pending)
        pending = null
    }

    companion object {
        const val ACTION = "com.voiceagent.voice_agent.WIDGET_TAPPED"
        const val EXTRA_TAP = "tap"
    }
}
