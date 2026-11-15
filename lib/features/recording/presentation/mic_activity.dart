import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/core/session_control/mic_mode.dart';
import 'package:voice_agent/features/recording/domain/hands_free_session_state.dart';
import 'package:voice_agent/features/recording/domain/recording_state.dart';
import 'package:voice_agent/features/recording/presentation/recording_providers.dart';

/// What the microphone does now, one answer for every place that shows it:
/// the conversation field, the strip at the top of the app, the mic button.
/// The owner's remark of 2026-11-15 (V1 device check, T6): a held button is
/// under the finger, so the state must show where the finger is not.
enum MicActivity {
  /// Nothing is captured; a tap starts listening.
  idle,

  /// Listening paused by the owner (standby).
  standby,

  /// The session listens and hears nothing yet.
  listening,

  /// The session hears speech (voice activity) and captures it.
  hearing,

  /// A held press (or a manual recording) records.
  recording,

  /// What was said is being turned into text.
  processing;

  /// True while sound is being captured: the field and the strip turn red.
  bool get capturing => this == hearing || this == recording;
}

MicActivity micActivityOf(RecordingState rec, HandsFreeSessionState hf, MicMode? mode) {
  if (rec is RecordingActive) return MicActivity.recording;
  if (rec is RecordingTranscribing) return MicActivity.processing;
  if (rec is RecordingPaused) return MicActivity.standby;
  if (hf is HandsFreeListening) {
    return switch (hf.phase) {
      HandsFreeListeningPhase.capturing => MicActivity.hearing,
      HandsFreeListeningPhase.stopping => MicActivity.processing,
      HandsFreeListeningPhase.listening => MicActivity.listening,
    };
  }
  if (mode == MicMode.standby) return MicActivity.standby;
  if (mode == MicMode.listening) return MicActivity.listening;
  return MicActivity.idle;
}

final micActivityProvider = Provider<MicActivity>((ref) => micActivityOf(
      ref.watch(recordingControllerProvider),
      ref.watch(handsFreeControllerProvider),
      ref.watch(micModesEnabledProvider) ? ref.watch(micModeProvider) : null,
    ));

/// The colour of an activity, or null when nothing needs showing.
Color? micActivityColor(MicActivity a) => switch (a) {
      MicActivity.recording || MicActivity.hearing => Colors.red.shade600,
      MicActivity.listening => Colors.orange.shade600,
      MicActivity.processing => Colors.blueGrey,
      MicActivity.idle || MicActivity.standby => null,
    };

/// A thin strip at the top edge of the app, over every screen, in the
/// activity's colour: red while sound is captured, orange while listening,
/// grey while processing; nothing when the mic is off or paused. The app
/// lays it over its navigator.
class MicActivityStrip extends ConsumerWidget {
  const MicActivityStrip({super.key});

  static const height = 4.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = micActivityColor(ref.watch(micActivityProvider));
    return IgnorePointer(
      child: AnimatedContainer(
        key: const Key('mic-activity-strip'),
        duration: const Duration(milliseconds: 150),
        height: color == null ? 0 : height,
        color: color ?? Colors.transparent,
      ),
    );
  }
}
