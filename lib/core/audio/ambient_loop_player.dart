import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Ambient-mode of [AmbientLoopPlayer].
///
/// `idle` — silence loop. App is the active media participant for iOS
/// hardware-button routing but produces no audible output.
///
/// `listening` — pleasant tonal pad. Audible cue that the mic is hot
/// and the engagement window is open. Volume is intentionally low so
/// it does not trigger our own VAD on the captured input.
///
/// `off` — nothing playing. Used while disposing or when foreground
/// audio (TTS reply) supersedes the loop.
enum AmbientMode { idle, listening, off }

/// Audio output orchestrator that swaps between two looped samples
/// based on the engagement state of the app. Replaces and extends the
/// original `KeepAliveSilentPlayer` from PR #270.
///
/// Contract:
///   - At app start the loop is `idle` (silence). iOS treats us as the
///     active media participant, hardware buttons route to our
///     MPRemoteCommand targets.
///   - On engage → `listening`. The listening sample plays, the user
///     hears that the mic is hot.
///   - On disengage → back to `idle`. Silence resumes.
///   - On TTS start → `off` (TTS is its own audio output, supersedes).
///   - On TTS end → back to whatever engagement state the app is in.
///
/// Thread-safety: state setters serialise transitions via internal
/// awaits. Failures from the underlying [AudioPlayer] are logged via
/// `debugPrint` but never rethrown — silence is acceptable
/// degradation of a UX-only signal.
class AmbientLoopPlayer {
  AmbientLoopPlayer({AudioPlayer? player})
      : _player = player ?? AudioPlayer() {
    // ignore: discarded_futures
    _player.setReleaseMode(ReleaseMode.loop);
  }

  final AudioPlayer _player;
  AmbientMode _mode = AmbientMode.off;

  AmbientMode get mode => _mode;

  /// Volume for the listening sample. Idle is always volume 0 (the
  /// silence asset is technically silent but volume 0 also avoids any
  /// sample-rate or DSP cost).
  static const double _listeningVolume = 1.0;

  Future<void> setMode(AmbientMode next) async {
    if (next == _mode) return;
    debugPrint('[AmbientLoopDbg] $_mode → $next');
    try {
      await _player.stop();
      switch (next) {
        case AmbientMode.idle:
          await _player.setVolume(0);
          await _player.play(AssetSource('audio/silence_loop.wav'));
        case AmbientMode.listening:
          await _player.setVolume(_listeningVolume);
          await _player.play(AssetSource('audio/listening_loop.wav'));
        case AmbientMode.off:
          // Already stopped above.
          break;
      }
      _mode = next;
    } catch (e) {
      debugPrint('[AmbientLoopDbg] setMode($next) failed: $e');
    }
  }

  Future<void> dispose() async {
    await setMode(AmbientMode.off);
    await _player.dispose();
  }
}
