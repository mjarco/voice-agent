package com.voiceagent.voice_agent

import android.content.Context
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/// Bridges Android media-session events (e.g. Bluetooth headset play/pause)
/// to Dart via platform channels.
///
/// - MethodChannel `com.voiceagent/media_button` handles `activate` /
///   `deactivate` calls from Dart.
/// - EventChannel `com.voiceagent/media_button/events` streams toggle
///   events back to Dart.
class MediaButtonBridge(
    private val context: Context,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private var mediaSession: MediaSessionCompat? = null
    private var eventSink: EventChannel.EventSink? = null

    // -- MethodChannel handler ------------------------------------------------

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "activate" -> {
                activateSession()
                result.success(null)
            }
            "deactivate" -> {
                deactivateSession()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    // -- Media session management ---------------------------------------------

    private fun activateSession() {
        if (mediaSession != null) return

        val session = MediaSessionCompat(context, "VoiceAgentMediaSession").apply {
            setCallback(object : MediaSessionCompat.Callback() {
                override fun onPlay() {
                    eventSink?.success("togglePlayPause")
                }

                override fun onPause() {
                    eventSink?.success("togglePlayPause")
                }

                override fun onMediaButtonEvent(mediaButtonEvent: android.content.Intent?): Boolean {
                    // Let the default handler dispatch to onPlay/onPause.
                    return super.onMediaButtonEvent(mediaButtonEvent)
                }
            })

            // Set a paused playback state so the session is eligible to receive
            // media button events.
            setPlaybackState(
                PlaybackStateCompat.Builder()
                    .setState(
                        PlaybackStateCompat.STATE_PAUSED,
                        PlaybackStateCompat.PLAYBACK_POSITION_UNKNOWN,
                        0f,
                    )
                    .setActions(
                        PlaybackStateCompat.ACTION_PLAY or
                            PlaybackStateCompat.ACTION_PAUSE or
                            PlaybackStateCompat.ACTION_PLAY_PAUSE,
                    )
                    .build(),
            )

            isActive = true
        }
        mediaSession = session
    }

    private fun deactivateSession() {
        mediaSession?.isActive = false
        mediaSession?.release()
        mediaSession = null
    }

    // -- EventChannel StreamHandler -------------------------------------------

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }
}
