package com.voiceagent.voice_agent

import android.content.Intent
import android.os.Bundle
import com.voiceagent.voice_agent.location.LocationBridge
import com.voiceagent.voice_agent.location.PlaceGeofencesBridge
import com.voiceagent.voice_agent.location.PlaceReadingBridge
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private var mediaButtonBridge: MediaButtonBridge? = null
    private var shareBridge: ShareBridge? = null

    /** A recreated activity gets its starting intent again. */
    private var recreated = false

    override fun onCreate(savedInstanceState: Bundle?) {
        recreated = savedInstanceState != null
        super.onCreate(savedInstanceState)
    }

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

        MethodChannel(messenger, "com.voiceagent/place_geofences")
            .setMethodCallHandler(PlaceGeofencesBridge(this))

        val shareChannel = MethodChannel(messenger, "com.voiceagent/share")
        val share = ShareBridge(shareChannel)
        shareChannel.setMethodCallHandler(share)
        shareBridge = share
        if (!recreated) share.accept(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        shareBridge?.accept(intent)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        mediaButtonBridge?.deactivateSession()
        mediaButtonBridge = null
        shareBridge = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onResume() {
        super.onResume()
        // Another app may have played audio while we were in the background (#358).
        mediaButtonBridge?.claimMediaButtonRouting()
    }
}
