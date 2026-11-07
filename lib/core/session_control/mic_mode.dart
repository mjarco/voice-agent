import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The microphone mode the user sees on Android (ADR-AUDIO-013).
///
/// Like a media player: [listening] is playing, [standby] is paused, [off]
/// is closed. Only `HandsFreeController` writes it; it lives in core because
/// the sync worker (another feature) reads it to stay quiet in [standby].
enum MicMode {
  /// No session: microphone released, foreground service stopped.
  off,

  /// The recorder runs and every utterance is transcribed.
  listening,

  /// The recorder is stopped and the microphone released; the foreground
  /// service and the job queue stay, so the session resumes from anywhere.
  standby,
}

/// The current [MicMode]. Stays [MicMode.off] on platforms without the
/// three modes (iOS keeps ADR-AUDIO-011).
final micModeProvider = StateProvider<MicMode>((ref) => MicMode.off);

/// Whether the three microphone modes are in force: Android only
/// (ADR-AUDIO-013). Overridden in tests.
final micModesEnabledProvider = Provider<bool>((ref) => Platform.isAndroid);
