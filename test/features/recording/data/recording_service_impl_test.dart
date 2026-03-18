import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';
import 'package:voice_agent/features/recording/data/recording_service_impl.dart';

/// Mock AudioRecorder that simulates state transitions without hardware.
class MockAudioRecorder implements AudioRecorder {
  bool started = false;
  String? lastPath;
  RecordConfig? lastConfig;

  @override
  Future<void> start(RecordConfig config, {required String path}) async {
    started = true;
    lastPath = path;
    lastConfig = config;
  }

  @override
  Future<String?> stop() async {
    started = false;
    return lastPath;
  }

  @override
  Future<bool> isRecording() async => started;

  @override
  Future<bool> isPaused() async => false;

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<void> cancel() async {
    started = false;
  }

  @override
  Future<Amplitude> getAmplitude() async =>
      Amplitude(current: -30, max: -10);

  @override
  Future<bool> isEncoderSupported(AudioEncoder encoder) async => true;

  @override
  Future<List<InputDevice>> listInputDevices() async => [];

  @override
  Stream<RecordState> onStateChanged() => const Stream.empty();

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late MockAudioRecorder mockRecorder;
  late RecordingServiceImpl service;

  setUp(() {
    mockRecorder = MockAudioRecorder();
    service = RecordingServiceImpl(recorder: mockRecorder);
  });

  group('RecordingServiceImpl', () {
    test('start sets isRecording and calls recorder with correct config',
        () async {
      expect(service.isRecording, isFalse);

      await service.start(outputPath: '/tmp/test.wav');

      expect(service.isRecording, isTrue);
      expect(mockRecorder.started, isTrue);
      expect(mockRecorder.lastPath, '/tmp/test.wav');
      expect(mockRecorder.lastConfig?.encoder, AudioEncoder.wav);
      expect(mockRecorder.lastConfig?.sampleRate, 16000);
      expect(mockRecorder.lastConfig?.numChannels, 1);
    });

    test('stop returns RecordingResult with correct data', () async {
      await service.start(outputPath: '/tmp/test.wav');

      // Small delay so duration > 0
      await Future.delayed(const Duration(milliseconds: 50));

      final result = await service.stop();

      expect(result.filePath, '/tmp/test.wav');
      expect(result.sampleRate, 16000);
      expect(result.duration.inMilliseconds, greaterThan(0));
      expect(service.isRecording, isFalse);
    });

    test('cancel clears state', () async {
      await service.start(outputPath: '/tmp/cancel-test.wav');
      expect(service.isRecording, isTrue);

      await service.cancel();

      expect(service.isRecording, isFalse);
      expect(mockRecorder.started, isFalse);
    });

    test('elapsed emits duration while recording', () async {
      final durations = <Duration>[];
      final sub = service.elapsed.listen(durations.add);

      await service.start(outputPath: '/tmp/elapsed-test.wav');

      // Wait for a few emissions (~200ms each)
      await Future.delayed(const Duration(milliseconds: 500));

      await service.stop();
      await sub.cancel();

      expect(durations, isNotEmpty);
      // Each emission should be greater than the previous
      for (var i = 1; i < durations.length; i++) {
        expect(
          durations[i].inMilliseconds,
          greaterThanOrEqualTo(durations[i - 1].inMilliseconds),
        );
      }
    });

    test('multi-session: start→stop→start→stop works on same subscription',
        () async {
      final durations = <Duration>[];
      final sub = service.elapsed.listen(durations.add);

      // Session 1
      await service.start(outputPath: '/tmp/session1.wav');
      await Future.delayed(const Duration(milliseconds: 500));
      await service.stop();

      final session1Count = durations.length;
      expect(session1Count, greaterThan(0), reason: 'Session 1 should emit');

      // Session 2 — same subscription, same stream
      await service.start(outputPath: '/tmp/session2.wav');
      await Future.delayed(const Duration(milliseconds: 500));
      await service.stop();

      await sub.cancel();

      expect(
        durations.length,
        greaterThan(session1Count),
        reason: 'Session 2 should also emit on the same subscription',
      );
    });
  });
}
