import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/core/audio/audio_feedback_provider.dart';
import 'package:voice_agent/core/providers/activation_providers.dart';
import 'package:voice_agent/features/activation/domain/activation_state.dart';
import 'package:voice_agent/features/activation/presentation/activation_controller.dart';
import 'package:voice_agent/features/activation/presentation/wake_word_provider.dart';

final activationControllerProvider =
    StateNotifierProvider<ActivationController, ActivationState>((ref) {
  final controller = ActivationController(
    wakeWordService: ref.watch(wakeWordServiceProvider),
    audioFeedback: ref.watch(audioFeedbackServiceProvider),
    ref: ref,
  );

  // Watch session status changes and forward to controller.
  ref.listen(handsFreeSessionStatusProvider, (_, next) {
    controller.onSessionStatusChanged(next);
  });

  // Watch pause requests from manual recording.
  ref.listen(wakeWordPauseRequestProvider, (_, next) {
    controller.onPauseRequest(next);
  });

  return controller;
});
