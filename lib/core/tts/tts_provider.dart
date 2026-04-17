import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/core/tts/flutter_tts_service.dart';
import 'package:voice_agent/core/tts/tts_service.dart';

final ttsServiceProvider = Provider<TtsService>((ref) {
  final tts = FlutterTtsService();
  ref.onDispose(tts.dispose);
  return tts;
});

/// Whether TTS is currently playing audio. Used by hands-free controller
/// to pause VAD during playback (avoids mic picking up speaker output).
final ttsPlayingProvider = Provider<bool>((ref) {
  final tts = ref.watch(ttsServiceProvider);
  final notifier = tts.isSpeaking;
  // Bridge ValueListenable → Riverpod: invalidate self on each change.
  void listener() => ref.invalidateSelf();
  notifier.addListener(listener);
  ref.onDispose(() => notifier.removeListener(listener));
  return notifier.value;
});
