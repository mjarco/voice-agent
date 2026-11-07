import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/session_control/mic_mode.dart';
import 'package:voice_agent/features/recording/domain/mic_mode_machine.dart';

void main() {
  // The eight rows of the model (ADR-AUDIO-013). Every other pair of
  // (mode, event) must be ignored.
  const allowed = <(MicMode, MicModeEvent), MicMode>{
    (MicMode.off, MicModeEvent.start): MicMode.listening,
    (MicMode.listening, MicModeEvent.pause): MicMode.standby,
    (MicMode.listening, MicModeEvent.interrupted): MicMode.standby,
    (MicMode.listening, MicModeEvent.error): MicMode.standby,
    (MicMode.standby, MicModeEvent.resume): MicMode.listening,
    (MicMode.listening, MicModeEvent.stop): MicMode.off,
    (MicMode.standby, MicModeEvent.stop): MicMode.off,
    (MicMode.listening, MicModeEvent.farewell): MicMode.off,
    (MicMode.listening, MicModeEvent.taskRemoved): MicMode.off,
    (MicMode.standby, MicModeEvent.taskRemoved): MicMode.off,
  };

  group('nextMicMode', () {
    for (final entry in allowed.entries) {
      final (from, event) = entry.key;
      test('${from.name} + ${event.name} → ${entry.value.name}', () {
        expect(nextMicMode(from, event), entry.value);
      });
    }

    for (final from in MicMode.values) {
      for (final event in MicModeEvent.values) {
        if (allowed.containsKey((from, event))) continue;
        test('${from.name} + ${event.name} is ignored', () {
          expect(nextMicMode(from, event), isNull);
        });
      }
    }

    test('a start from Standby is impossible: Standby only resumes', () {
      expect(nextMicMode(MicMode.standby, MicModeEvent.start), isNull);
      expect(nextMicMode(MicMode.standby, MicModeEvent.resume),
          MicMode.listening);
    });

    test('nothing leaves Off but a start', () {
      for (final event in MicModeEvent.values) {
        if (event == MicModeEvent.start) continue;
        expect(nextMicMode(MicMode.off, event), isNull, reason: event.name);
      }
    });
  });
}
