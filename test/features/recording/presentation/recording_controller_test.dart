import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/features/recording/domain/recording_result.dart';
import 'package:voice_agent/features/recording/domain/recording_service.dart';
import 'package:voice_agent/features/recording/domain/recording_state.dart';
import 'package:voice_agent/features/recording/domain/stt_service.dart';
import 'package:voice_agent/core/models/transcript_result.dart';
import 'package:voice_agent/features/recording/presentation/recording_controller.dart';

class FakeRecordingService implements RecordingService {
  bool _isRecording = false;
  String? lastPath;
  bool shouldThrowOnStop = false;
  final _elapsedController = StreamController<Duration>.broadcast();

  @override
  Future<void> start({required String outputPath}) async {
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

class FakeSttService implements SttService {
  bool _loaded = true;
  TranscriptResult? nextResult;
  bool shouldThrow = false;

  @override
  Future<bool> isModelLoaded() async => _loaded;

  @override
  Future<void> loadModel() async {
    _loaded = true;
  }

  @override
  Future<TranscriptResult> transcribe(
    String audioFilePath, {
    String? languageCode,
  }) async {
    if (shouldThrow) throw Exception('transcription failed');
    return nextResult ??
        const TranscriptResult(
          text: 'Hello world',
          segments: [],
          detectedLanguage: 'en',
          audioDurationMs: 5000,
        );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeRecordingService fakeService;
  late FakeSttService fakeStt;
  late RecordingController controller;

  setUp(() {
    fakeService = FakeRecordingService();
    fakeStt = FakeSttService();
    controller = RecordingController(fakeService, fakeStt);
  });

  tearDown(() {
    controller.dispose();
  });

  test('initial state is idle', () {
    expect(controller.state, isA<RecordingIdle>());
  });

  test('cancelRecording returns to idle', () async {
    await controller.cancelRecording();
    expect(controller.state, isA<RecordingIdle>());
  });

  test('resetToIdle sets state to idle', () {
    controller.resetToIdle();
    expect(controller.state, isA<RecordingIdle>());
  });

  test('stopAndTranscribe transitions through transcribing to completed',
      () async {
    fakeService.lastPath = '/tmp/test.wav';

    final states = <RecordingState>[];
    controller.addListener(states.add);

    await controller.stopAndTranscribe();

    // Should have gone through: transcribing, completed
    expect(states.any((s) => s is RecordingTranscribing), isTrue);
    expect(controller.state, isA<RecordingCompleted>());
    expect(
      (controller.state as RecordingCompleted).result.text,
      'Hello world',
    );
  });

  test('stopAndTranscribe transitions to error on STT failure', () async {
    fakeService.lastPath = '/tmp/test.wav';
    fakeStt.shouldThrow = true;

    await controller.stopAndTranscribe();

    expect(controller.state, isA<RecordingError>());
    expect(
      (controller.state as RecordingError).message,
      contains('Transcription failed'),
    );
  });

  test('stopAndTranscribe transitions to error on recording stop failure',
      () async {
    fakeService.shouldThrowOnStop = true;

    await controller.stopAndTranscribe();

    expect(controller.state, isA<RecordingError>());
    expect(
      (controller.state as RecordingError).message,
      contains('Transcription failed'),
    );
  });

  test('RecordingState sealed class exhaustiveness', () {
    const states = <RecordingState>[
      RecordingIdle(),
      RecordingActive(),
      RecordingTranscribing(),
      RecordingCompleted(
        TranscriptResult(
          text: 'test',
          segments: [],
          detectedLanguage: 'en',
          audioDurationMs: 0,
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
        case RecordingTranscribing():
          break;
        case RecordingCompleted():
          break;
        case RecordingError():
          break;
      }
    }
    expect(states.length, 5);
  });
}
