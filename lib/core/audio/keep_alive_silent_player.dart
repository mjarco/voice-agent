import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// P034 follow-up. iOS routes hardware media-button events
/// (AirPods click → MPRemoteCommandCenter) only to apps that are
/// actively producing audio output. During hands-free listening the
/// app captures mic input but produces nothing on the speaker — iOS
/// treats us as "claimed but inactive media participant" and rejects
/// the press with an audible "boop". Looping a silent WAV through
/// AVAudioPlayer makes iOS see continuous audio output and route the
/// press to our MPRemoteCommand target normally.
///
/// The loop runs only while hands-free is listening (not capturing /
/// not suspended). Stopped during TTS playback (TTS is real audio
/// output and supersedes the keepalive).
class KeepAliveSilentPlayer {
  KeepAliveSilentPlayer({AudioPlayer? player})
      : _player = player ?? AudioPlayer() {
    // Loop forever; silence is silence.
    // ignore: discarded_futures
    _player.setReleaseMode(ReleaseMode.loop);
    // Keep volume at 0 — audible silence is still silence, but the
    // engine activity is what iOS uses to route hardware buttons.
    // ignore: discarded_futures
    _player.setVolume(0);
  }

  final AudioPlayer _player;
  bool _running = false;

  bool get isRunning => _running;

  Future<void> start() async {
    if (_running) return;
    try {
      await _player.play(AssetSource('audio/silence_loop.wav'));
      _running = true;
    } catch (e) {
      debugPrint('[KeepAliveSilentPlayer] start failed: $e');
    }
  }

  Future<void> stop() async {
    if (!_running) return;
    try {
      await _player.stop();
    } catch (e) {
      debugPrint('[KeepAliveSilentPlayer] stop failed: $e');
    } finally {
      _running = false;
    }
  }

  Future<void> dispose() async {
    await stop();
    await _player.dispose();
  }
}
