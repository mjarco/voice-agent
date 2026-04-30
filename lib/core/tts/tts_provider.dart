import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/core/session_control/session_control_provider.dart';
import 'package:voice_agent/core/tts/flutter_tts_service.dart';
import 'package:voice_agent/core/tts/tts_reply_buffer.dart';
import 'package:voice_agent/core/tts/tts_service.dart';

final ttsServiceProvider = Provider<TtsService>((ref) {
  final tts = FlutterTtsService();
  ref.onDispose(tts.dispose);
  return tts;
});

/// P036: holds the most recent successful agent reply for replay-last.
/// Cleared on session reset and on conversation_id rotation.
final ttsReplyBufferProvider = Provider<TtsReplyBuffer>((ref) {
  final buffer = InMemoryTtsReplyBuffer();

  // Clear on session reset (P029 reset_session signal path).
  final coordinator = ref.watch(sessionIdCoordinatorProvider);
  final disposeReset = coordinator.addResetListener(buffer.clear);
  // Clear when the backend rotates conversation_id without an explicit
  // reset_session signal.
  final disposeChange = coordinator.addConversationChangeListener(
    (_) => buffer.clear(),
  );
  ref.onDispose(disposeReset);
  ref.onDispose(disposeChange);

  return buffer;
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
