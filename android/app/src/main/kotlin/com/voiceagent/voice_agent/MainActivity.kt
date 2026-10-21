package com.voiceagent.voice_agent

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private var mediaButtonBridge: MediaButtonBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val messenger = flutterEngine.dartExecutor.binaryMessenger
        val bridge = MediaButtonBridge(this)
        mediaButtonBridge = bridge

        MethodChannel(messenger, "com.voiceagent/media_button")
            .setMethodCallHandler(bridge)

        EventChannel(messenger, "com.voiceagent/media_button/events")
            .setStreamHandler(bridge)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        mediaButtonBridge?.deactivateSession()
        mediaButtonBridge = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onResume() {
        super.onResume()
        // Another app may have played audio while we were in the background (#358).
        mediaButtonBridge?.claimMediaButtonRouting()
    }
}
