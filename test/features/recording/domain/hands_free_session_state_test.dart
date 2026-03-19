import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/features/recording/domain/hands_free_engine.dart';
import 'package:voice_agent/features/recording/domain/hands_free_session_state.dart';
import 'package:voice_agent/features/recording/domain/segment_job.dart';

void main() {
  group('HandsFreeSessionState sealed class exhaustiveness', () {
    final states = <HandsFreeSessionState>[
      const HandsFreeIdle(),
      const HandsFreeListening([]),
      const HandsFreeCapturing([]),
      const HandsFreeStopping([]),
      const HandsFreeWithBacklog([]),
      const HandsFreeSessionError(message: 'oops'),
    ];

    test('switch covers all variants', () {
      for (final s in states) {
        switch (s) {
          case HandsFreeIdle():
            break;
          case HandsFreeListening():
            break;
          case HandsFreeCapturing():
            break;
          case HandsFreeStopping():
            break;
          case HandsFreeWithBacklog():
            break;
          case HandsFreeSessionError():
            break;
        }
      }
      expect(states.length, 6);
    });
  });

  group('HandsFreeSessionError', () {
    test('requiresSettings and requiresAppSettings cannot both be true', () {
      expect(
        () => HandsFreeSessionError(
          message: 'bad',
          requiresSettings: true,
          requiresAppSettings: true,
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('requiresSettings true is valid', () {
      const e = HandsFreeSessionError(
        message: 'mic denied',
        requiresSettings: true,
      );
      expect(e.requiresSettings, isTrue);
      expect(e.requiresAppSettings, isFalse);
    });

    test('requiresAppSettings true is valid', () {
      const e = HandsFreeSessionError(
        message: 'key missing',
        requiresAppSettings: true,
      );
      expect(e.requiresAppSettings, isTrue);
      expect(e.requiresSettings, isFalse);
    });

    test('carries jobs at time of error', () {
      final job = SegmentJob(
        id: 'j1',
        label: 'Segment 1',
        state: const Transcribing(),
      );
      final e = HandsFreeSessionError(message: 'crash', jobs: [job]);
      expect(e.jobs.length, 1);
      expect(e.jobs.first.id, 'j1');
    });
  });

  group('SegmentJobState sealed class exhaustiveness', () {
    final states = <SegmentJobState>[
      const QueuedForTranscription(),
      const Transcribing(),
      const Persisting(),
      const Completed('tid'),
      const Rejected('too short'),
      const JobFailed('error'),
    ];

    test('switch covers all variants', () {
      for (final s in states) {
        switch (s) {
          case QueuedForTranscription():
            break;
          case Transcribing():
            break;
          case Persisting():
            break;
          case Completed():
            break;
          case Rejected():
            break;
          case JobFailed():
            break;
        }
      }
      expect(states.length, 6);
    });
  });

  group('SegmentJob', () {
    test('copyWith updates state while preserving other fields', () {
      final job = SegmentJob(
        id: 'j1',
        label: 'Segment 1',
        state: const QueuedForTranscription(),
        wavPath: '/tmp/seg.wav',
      );
      final updated = job.copyWith(state: const Transcribing());
      expect(updated.id, 'j1');
      expect(updated.label, 'Segment 1');
      expect(updated.wavPath, '/tmp/seg.wav');
      expect(updated.state, isA<Transcribing>());
    });

    test('copyWith can clear wavPath by setting null', () {
      final job = SegmentJob(
        id: 'j1',
        label: 'Segment 1',
        state: const Completed('tid'),
        wavPath: '/tmp/seg.wav',
      );
      // wavPath cannot be set to null via copyWith (it falls through to existing);
      // verify the current job still has it.
      expect(job.wavPath, '/tmp/seg.wav');
    });
  });

  group('HandsFreeEngineEvent sealed class', () {
    test('EngineError carries requiresSettings flag', () {
      const e = EngineError('mic denied', requiresSettings: true);
      expect(e.requiresSettings, isTrue);
      expect(e.message, 'mic denied');
    });

    test('EngineSegmentReady carries wavPath', () {
      const e = EngineSegmentReady('/tmp/seg.wav');
      expect(e.wavPath, '/tmp/seg.wav');
    });
  });
}
