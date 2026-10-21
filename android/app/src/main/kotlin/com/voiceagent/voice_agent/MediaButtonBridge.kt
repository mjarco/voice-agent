package com.voiceagent.voice_agent

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.os.Handler
import android.os.Looper
import android.util.Log
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
                    Log.d(TAG, "onPlay")
                    eventSink?.success("togglePlayPause")
                }

                override fun onPause() {
                    Log.d(TAG, "onPause")
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
        claimMediaButtonRouting()
    }

    /// Android routes media buttons to the session of the app that most
    /// recently played audio, not to any active session. TTS is played by
    /// the TTS engine's UID, so the app never qualifies on its own: play a
    /// short burst of PCM silence under the app's UID (#358). Called when
    /// the session activates and when the activity resumes, since another
    /// app's playback in between takes the routing away.
    fun claimMediaButtonRouting() {
        if (mediaSession == null) return
        var track: AudioTrack? = null
        try {
            val sampleRate = 16000
            val samples = ShortArray(sampleRate * SILENCE_MS / 1000)
            val built = AudioTrack.Builder()
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                        .build(),
                )
                .setAudioFormat(
                    AudioFormat.Builder()
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .setSampleRate(sampleRate)
                        .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                        .build(),
                )
                .setTransferMode(AudioTrack.MODE_STATIC)
                .setBufferSizeInBytes(samples.size * 2)
                .build()
            track = built
            built.write(samples, 0, samples.size)
            built.play()
            Log.d(TAG, "claimMediaButtonRouting: silence played")
            Handler(Looper.getMainLooper()).postDelayed({
                built.stop()
                built.release()
            }, SILENCE_MS + 200L)
        } catch (e: Exception) {
            Log.w(TAG, "claimMediaButtonRouting failed", e)
            track?.release()
        }
    }

    /// Releases the session when the engine that owns this bridge goes
    /// away. A session left active by a destroyed engine keeps the media
    /// button routing while its event sink leads nowhere (#358).
    fun deactivateSession() {
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

    private companion object {
        const val TAG = "MediaButtonBridge"
        const val SILENCE_MS = 300
    }
}
