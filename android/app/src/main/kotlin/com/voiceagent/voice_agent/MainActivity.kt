package com.voiceagent.voice_agent

import com.voiceagent.voice_agent.location.LocationBridge
import com.voiceagent.voice_agent.location.PlaceReadingBridge
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

        MethodChannel(messenger, "com.voiceagent/location_log")
            .setMethodCallHandler(LocationBridge(this))

        MethodChannel(messenger, "com.voiceagent/place_reading")
            .setMethodCallHandler(PlaceReadingBridge(this))
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
