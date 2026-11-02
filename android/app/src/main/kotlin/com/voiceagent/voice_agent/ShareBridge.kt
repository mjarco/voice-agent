package com.voiceagent.voice_agent

import android.content.Intent
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Text shared from another app, on `com.voiceagent/share` (ADR-PLATFORM-008).
 * Dart takes what launched the app once, with `takeInitialText`. Text shared
 * after that arrives as `sharedText`, so one share reaches one channel.
 */
class ShareBridge(private val channel: MethodChannel) : MethodChannel.MethodCallHandler {
    private var pending: String? = null
    private var dartTookInitial = false

    fun accept(intent: Intent?) {
        if (intent == null || intent.action != Intent.ACTION_SEND) return
        // Recents redelivers the intent that started the task.
        if (intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY != 0) return
        val text = intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()
        if (text.isNullOrBlank()) return
        if (dartTookInitial) {
            channel.invokeMethod("sharedText", text)
        } else {
            pending = text
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "takeInitialText") {
            result.notImplemented()
            return
        }
        dartTookInitial = true
        result.success(pending)
        pending = null
    }
}
