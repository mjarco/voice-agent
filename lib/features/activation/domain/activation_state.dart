import 'package:voice_agent/core/providers/activation_event.dart';

/// State machine for background activation.
sealed class ActivationState {
  const ActivationState();
}

/// Background listening is not active.
class ActivationIdle extends ActivationState {
  const ActivationIdle();
}

/// Porcupine is listening for a wake word.
class ActivationListening extends ActivationState {
  const ActivationListening({required this.keyword});
  final String keyword;
}

/// A hands-free session is in progress.
class ActivationHandsFreeActive extends ActivationState {
  const ActivationHandsFreeActive({required this.trigger});
  final ActivationEvent trigger;
}

/// An error occurred (e.g. invalid access key, audio failure).
class ActivationError extends ActivationState {
  const ActivationError({
    required this.message,
    this.requiresSettings = false,
  });
  final String message;
  final bool requiresSettings;
}
