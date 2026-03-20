import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/core/audio/audio_feedback_service.dart';
import 'package:voice_agent/core/audio/audioplayers_audio_feedback_service.dart';
import 'package:voice_agent/core/config/app_config_provider.dart';

final audioFeedbackServiceProvider = Provider<AudioFeedbackService>((ref) {
  final svc = AudioplayersAudioFeedbackService(
    getEnabled: () => ref.read(appConfigProvider).audioFeedbackEnabled,
  );
  ref.onDispose(svc.dispose);
  return svc;
});
