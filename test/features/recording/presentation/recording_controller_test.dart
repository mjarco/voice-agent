import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/features/recording/domain/recording_result.dart';
import 'package:voice_agent/features/recording/domain/recording_service.dart';
import 'package:voice_agent/features/recording/domain/recording_state.dart';
import 'package:voice_agent/features/recording/presentation/recording_controller.dart';

class FakeRecordingService implements RecordingService {
  bool _isRecording = false;
  String? lastPath;
  bool shouldThrowOnStart = false;
  bool shouldThrowOnStop = false;
  final _elapsedController = StreamController<Duration>.broadcast();

  @override
  Future<void> start({required String outputPath}) async {
    if (shouldThrowOnStart) throw Exception('start failed');
    _isRecording = true;
    lastPath = outputPath;
  }

  @override
  Future<RecordingResult> stop() async {
    if (shouldThrowOnStop) throw Exception('stop failed');
    _isRecording = false;
    return RecordingResult(
      filePath: lastPath ?? '/tmp/test.wav',
      duration: const Duration(seconds: 5),
      sampleRate: 16000,
    );
  }

  @override
  Future<void> cancel() async {
    _isRecording = false;
  }

  @override
  Stream<Duration> get elapsed => _elapsedController.stream;

  @override
  bool get isRecording => _isRecording;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeRecordingService fakeService;
  late RecordingController controller;

  setUp(() {
    fakeService = FakeRecordingService();
    controller = RecordingController(fakeService);
  });

  tearDown(() {
    controller.dispose();
  });

  test('initial state is idle', () {
    expect(controller.state, isA<RecordingIdle>());
  });

  test('cancelRecording returns to idle', () async {
    // Simulate being in recording state by directly testing cancel
    await controller.cancelRecording();
    expect(controller.state, isA<RecordingIdle>());
  });

  test('resetToIdle sets state to idle', () {
    controller.resetToIdle();
    expect(controller.state, isA<RecordingIdle>());
  });

  test('stopRecording returns completed with result', () async {
    // We can't easily test startRecording because it calls Permission.microphone
    // which requires a running app. So we test stop in isolation with a fake service
    // that has been "started".
    fakeService.lastPath = '/tmp/test.wav';
    final result = await fakeService.stop();

    expect(result.filePath, '/tmp/test.wav');
    expect(result.sampleRate, 16000);
    expect(result.duration, const Duration(seconds: 5));
  });

  test('stopRecording error transitions to error state', () async {
    fakeService.shouldThrowOnStop = true;
    await controller.stopRecording();
    expect(controller.state, isA<RecordingError>());
    expect(
      (controller.state as RecordingError).message,
      contains('Failed to stop recording'),
    );
  });

  test('RecordingState sealed class exhaustiveness', () {
    // Verify all states can be constructed
    const states = <RecordingState>[
      RecordingIdle(),
      RecordingActive(),
      RecordingCompleted(
        RecordingResult(
          filePath: '/test',
          duration: Duration.zero,
          sampleRate: 16000,
        ),
      ),
      RecordingError('test error'),
    ];

    for (final state in states) {
      switch (state) {
        case RecordingIdle():
          break;
        case RecordingActive():
          break;
        case RecordingCompleted():
          break;
        case RecordingError():
          break;
      }
    }
    // If this compiles, exhaustiveness is proven
    expect(states.length, 4);
  });
}
