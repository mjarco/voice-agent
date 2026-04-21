import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:voice_agent/core/audio/audio_feedback_service.dart';

class AudioplayersAudioFeedbackService implements AudioFeedbackService {
  AudioplayersAudioFeedbackService({
    AudioPlayer? player,
    required bool Function() getEnabled,
  })  : _player = player ?? AudioPlayer(),
        _getEnabled = getEnabled {
    unawaited(_player.setAudioContext(AudioContext(
      iOS: AudioContextIOS(
        category: AVAudioSessionCategory.ambient,
        // ambient already implies mix-with-others; no explicit options needed
      ),
      android: AudioContextAndroid(
        contentType: AndroidContentType.sonification,
        usageType: AndroidUsageType.assistanceSonification,
        audioFocus: AndroidAudioFocus.none,
      ),
    )));
  }

  final AudioPlayer _player;
  final bool Function() _getEnabled;

  // Generation counter — incremented by stopLoop/playSuccess/playError/dispose
  // to invalidate any pending start→loop callbacks.
  int _generation = 0;

  @override
  Future<void> startProcessingFeedback() async {
    if (!_getEnabled()) return;
    final gen = ++_generation;
    await _player.setReleaseMode(ReleaseMode.release);
    await _player.play(AssetSource('audio/processing_start.mp3'));
    _player.onPlayerComplete.first.then((_) async {
      if (_generation != gen) return;
      if (!_getEnabled()) return;
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.play(AssetSource('audio/processing_loop.mp3'));
    }).catchError((_) {}); // stream closed on dispose — ignore
  }

  @override
  Future<void> stopLoop() async {
    ++_generation;
    await _player.stop();
  }

  @override
  Future<void> playSuccess() async {
    ++_generation;
    await _player.stop();
    if (!_getEnabled()) return;
    await _player.setReleaseMode(ReleaseMode.release);
    await _player.play(AssetSource('audio/processing_success.mp3'));
  }

  @override
  Future<void> playError() async {
    ++_generation;
    await _player.stop();
    if (!_getEnabled()) return;
    await _player.setReleaseMode(ReleaseMode.release);
    await _player.play(AssetSource('audio/processing_error.mp3'));
  }

  @override
  void dispose() {
    ++_generation;
    _player.dispose();
  }
}
