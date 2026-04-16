import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/core/providers/activation_event.dart';
import 'package:voice_agent/core/providers/hands_free_session_status.dart';

/// Set by `ActivationController` when a wake word is detected or a shortcut
/// is activated. Watched by `HandsFreeController` to trigger a session.
/// Reset to `null` after the session starts.
final activationEventProvider = StateProvider<ActivationEvent?>((ref) => null);

/// Set by `HandsFreeController` to signal session lifecycle.
/// Observed by `ActivationController` to restart wake word detection after
/// a session completes or transition to error on failure.
final handsFreeSessionStatusProvider =
    StateProvider<HandsFreeSessionStatus>((ref) {
  return const HandsFreeSessionInactive();
});

/// Set by `RecordingController` before manual recording with a fresh
/// `Completer<void>`. `ActivationController` stops Porcupine then completes
/// the completer, letting the recording controller proceed.
/// Reset to `null` by `RecordingController` when recording ends.
final wakeWordPauseRequestProvider =
    StateProvider<Completer<void>?>((ref) => null);
