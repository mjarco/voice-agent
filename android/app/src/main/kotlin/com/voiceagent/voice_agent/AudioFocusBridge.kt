package com.voiceagent.voice_agent

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/// The app's own transient audio focus, held while the microphone listens
/// (ADR-AUDIO-014). The `record` plugin is set to take none, so other
/// apps' sound pauses only in Listening and resumes when it is given back.
///
/// - MethodChannel `com.voiceagent/audio_focus`: `request` (returns true
///   when granted) and `abandon`.
/// - EventChannel `com.voiceagent/audio_focus/events`: `loss`,
///   `lossTransient`, `lossTransientCanDuck` while the focus is held.
class AudioFocusBridge(
    context: Context,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private val audioManager =
        context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val handler = Handler(Looper.getMainLooper())
    private var eventSink: EventChannel.EventSink? = null

    private val listener = AudioManager.OnAudioFocusChangeListener { change ->
        val event = when (change) {
            AudioManager.AUDIOFOCUS_LOSS -> "loss"
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> "lossTransient"
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> "lossTransientCanDuck"
            else -> null
        }
        Log.d(TAG, "focus change $change → $event")
        if (event != null) eventSink?.success(event)
    }

    private val focusRequest: AudioFocusRequest? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                        .build(),
                )
                .setAcceptsDelayedFocusGain(false)
                // Deliver "may duck" losses instead of ducking silently, so
                // Dart sees (and ignores) them; there is no playback to duck.
                .setWillPauseWhenDucked(true)
                .setOnAudioFocusChangeListener(listener, handler)
                .build()
        } else {
            null
        }

    // -- MethodChannel handler ------------------------------------------------

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "request" -> result.success(request())
            "abandon" -> {
                abandon()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    @Suppress("DEPRECATION")
    private fun request(): Boolean {
        val granted = if (focusRequest != null) {
            audioManager.requestAudioFocus(focusRequest)
        } else {
            audioManager.requestAudioFocus(
                listener,
                AudioManager.STREAM_MUSIC,
                AudioManager.AUDIOFOCUS_GAIN_TRANSIENT,
            )
        }
        Log.d(TAG, "request → $granted")
        return granted == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
    }

    @Suppress("DEPRECATION")
    fun abandon() {
        if (focusRequest != null) {
            audioManager.abandonAudioFocusRequest(focusRequest)
        } else {
            audioManager.abandonAudioFocus(listener)
        }
        Log.d(TAG, "abandoned")
    }

    // -- EventChannel StreamHandler -------------------------------------------

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    private companion object {
        const val TAG = "AudioFocusBridge"
    }
}
