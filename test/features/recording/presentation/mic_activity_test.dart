import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/theme/app_colors.dart';
import 'package:voice_agent/core/session_control/mic_mode.dart';
import 'package:voice_agent/features/recording/domain/hands_free_session_state.dart';
import 'package:voice_agent/features/recording/domain/recording_state.dart';
import 'package:voice_agent/features/recording/presentation/mic_activity.dart';

void main() {
  const idleHf = HandsFreeIdle();

  test('a held recording records, and it is capturing', () {
    final a = micActivityOf(const RecordingState.recording(), idleHf, MicMode.off);
    expect(a, MicActivity.recording);
    expect(a.capturing, isTrue);
  });

  test('transcribing is processing', () {
    expect(micActivityOf(const RecordingState.transcribing(), idleHf, null),
        MicActivity.processing);
  });

  test('the session: listening, hearing speech, writing a segment', () {
    for (final (phase, want) in [
      (HandsFreeListeningPhase.listening, MicActivity.listening),
      (HandsFreeListeningPhase.capturing, MicActivity.hearing),
      (HandsFreeListeningPhase.stopping, MicActivity.processing),
    ]) {
      expect(
        micActivityOf(const RecordingState.idle(), HandsFreeListening(const [], phase: phase), MicMode.listening),
        want,
        reason: '$phase',
      );
    }
  });

  test('standby and off show nothing', () {
    expect(micActivityOf(const RecordingState.idle(), idleHf, MicMode.standby), MicActivity.standby);
    expect(micActivityOf(const RecordingState.idle(), idleHf, MicMode.off), MicActivity.idle);
    expect(micActivityColor(MicActivity.standby, AppColors.light), isNull);
    expect(micActivityColor(MicActivity.idle, AppColors.light), isNull);
  });
}
