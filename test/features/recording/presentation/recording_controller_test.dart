import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voice_agent/core/config/app_config.dart';
import 'package:voice_agent/core/config/app_config_provider.dart';
import 'package:voice_agent/core/config/app_config_service.dart';
import 'package:voice_agent/core/models/transcript_result.dart';
import 'package:voice_agent/features/recording/domain/recording_result.dart';
import 'package:voice_agent/features/recording/domain/recording_service.dart';
import 'package:voice_agent/features/recording/domain/recording_state.dart';
import 'package:voice_agent/features/recording/domain/stt_exception.dart';
import 'package:voice_agent/features/recording/domain/stt_service.dart';
import 'package:voice_agent/features/recording/presentation/recording_controller.dart';
import 'package:voice_agent/features/recording/presentation/recording_providers.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class FakeRecordingService implements RecordingService {
  bool _isRecording = false;
  String? lastPath;
  bool shouldThrowOnStop = false;
  bool permissionGranted = true;
  final _elapsedController = StreamController<Duration>.broadcast();

  @override
  Future<bool> requestPermission() async => permissionGranted;

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
  SttException? throwSttException;

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
    if (throwSttException != null) throw throwSttException!;
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

class _FixedConfigService extends AppConfigService {
  _FixedConfigService(this._config);

  final AppConfig _config;

  @override
  Future<AppConfig> load() async => _config;

  @override
  Future<void> saveGroqApiKey(String key) async {}

  @override
  Future<void> saveApiUrl(String url) async {}

  @override
  Future<void> saveApiToken(String token) async {}
}

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

/// Creates a [ProviderContainer] pre-wired with the given fakes.
/// [config] defaults to one with a valid Groq key so most tests pass the guard.
ProviderContainer _makeContainer({
  required FakeRecordingService fakeService,
  required FakeSttService fakeStt,
  AppConfig config = const AppConfig(groqApiKey: 'test-key'),
}) {
  return ProviderContainer(
    overrides: [
      appConfigServiceProvider.overrideWithValue(_FixedConfigService(config)),
      recordingServiceProvider.overrideWithValue(fakeService),
      sttServiceProvider.overrideWithValue(fakeStt),
    ],
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeRecordingService fakeService;
  late FakeSttService fakeStt;
  late ProviderContainer container;
  late RecordingController controller;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    fakeService = FakeRecordingService();
    fakeStt = FakeSttService();
    container = _makeContainer(fakeService: fakeService, fakeStt: fakeStt);
    controller = container.read(recordingControllerProvider.notifier);
  });

  tearDown(() {
    container.dispose();
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

  test('stopAndTranscribe unwraps SttException message verbatim', () async {
    fakeService.lastPath = '/tmp/test.wav';
    fakeStt.throwSttException = const SttException('custom message');

    await controller.stopAndTranscribe();

    expect(controller.state, isA<RecordingError>());
    expect(
      (controller.state as RecordingError).message,
      'custom message',
    );
  });

  test(
      'startRecording emits RecordingError(requiresAppSettings) when Groq key missing',
      () async {
    final noKeyContainer = _makeContainer(
      fakeService: fakeService,
      fakeStt: fakeStt,
      config: const AppConfig(groqApiKey: null),
    );
    addTearDown(noKeyContainer.dispose);
    final ctrl = noKeyContainer.read(recordingControllerProvider.notifier);

    await ctrl.startRecording();

    expect(ctrl.state, isA<RecordingError>());
    final error = ctrl.state as RecordingError;
    expect(error.requiresAppSettings, isTrue);
    expect(error.requiresSettings, isFalse);
    expect(error.message, 'Groq API key not set.');
  });

  test(
      'startRecording emits RecordingError(requiresAppSettings) when Groq key empty',
      () async {
    final noKeyContainer = _makeContainer(
      fakeService: fakeService,
      fakeStt: fakeStt,
      config: const AppConfig(groqApiKey: ''),
    );
    addTearDown(noKeyContainer.dispose);
    final ctrl = noKeyContainer.read(recordingControllerProvider.notifier);

    await ctrl.startRecording();

    expect(ctrl.state, isA<RecordingError>());
    final error = ctrl.state as RecordingError;
    expect(error.requiresAppSettings, isTrue);
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
