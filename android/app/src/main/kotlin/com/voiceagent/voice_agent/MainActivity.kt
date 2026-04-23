package com.voiceagent.voice_agent

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val messenger = flutterEngine.dartExecutor.binaryMessenger
        val bridge = MediaButtonBridge(this)

        MethodChannel(messenger, "com.voiceagent/media_button")
            .setMethodCallHandler(bridge)

        EventChannel(messenger, "com.voiceagent/media_button/events")
            .setStreamHandler(bridge)
    }
}
