package com.voiceagent.voice_agent

import android.content.Intent
import android.os.Bundle
import com.voiceagent.voice_agent.location.LocationBridge
import com.voiceagent.voice_agent.location.PlaceReadingBridge
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private var mediaButtonBridge: MediaButtonBridge? = null
    private var audioFocusBridge: AudioFocusBridge? = null
    private var notificationActionBridge: NotificationActionBridge? = null
    private var shareBridge: ShareBridge? = null
    private var arrivalTapBridge: ArrivalTapBridge? = null

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

        val focus = AudioFocusBridge(this)
        audioFocusBridge = focus
        MethodChannel(messenger, "com.voiceagent/audio_focus")
            .setMethodCallHandler(focus)
        EventChannel(messenger, "com.voiceagent/audio_focus/events")
            .setStreamHandler(focus)

        val actions = NotificationActionBridge(this)
        notificationActionBridge = actions
        EventChannel(messenger, "com.voiceagent/notification_actions/events")
            .setStreamHandler(actions)

        MethodChannel(messenger, "com.voiceagent/location_log")
            .setMethodCallHandler(LocationBridge(this))

        MethodChannel(messenger, "com.voiceagent/place_reading")
            .setMethodCallHandler(PlaceReadingBridge(this))

        val shareChannel = MethodChannel(messenger, "com.voiceagent/share")
        val share = ShareBridge(shareChannel)
        shareChannel.setMethodCallHandler(share)
        shareBridge = share
        if (!recreated) share.accept(intent)

        val arrivalChannel = MethodChannel(messenger, "com.voiceagent/arrival_tap")
        val arrival = ArrivalTapBridge(this, arrivalChannel)
        arrivalChannel.setMethodCallHandler(arrival)
        arrivalTapBridge = arrival
        if (!recreated) arrival.accept(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        shareBridge?.accept(intent)
        arrivalTapBridge?.accept(intent)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        mediaButtonBridge?.deactivateSession()
        mediaButtonBridge = null
        // A focus left held by a destroyed engine would keep other apps paused.
        audioFocusBridge?.abandon()
        audioFocusBridge = null
        notificationActionBridge?.dispose()
        notificationActionBridge = null
        shareBridge = null
        arrivalTapBridge = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
