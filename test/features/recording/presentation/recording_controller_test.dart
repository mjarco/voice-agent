import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voice_agent/core/config/app_config.dart';
import 'package:voice_agent/core/config/app_config_provider.dart';
import 'package:voice_agent/core/config/app_config_service.dart';
import 'package:voice_agent/core/models/sync_queue_item.dart';
import 'package:voice_agent/core/models/transcript.dart';
import 'package:voice_agent/core/models/transcript_result.dart';
import 'package:voice_agent/core/models/transcript_with_status.dart';
import 'package:voice_agent/core/storage/storage_provider.dart';
import 'package:voice_agent/core/storage/storage_service.dart';
import 'package:voice_agent/features/recording/domain/recording_result.dart';
import 'package:voice_agent/features/recording/domain/recording_service.dart';
import 'package:voice_agent/features/recording/domain/recording_state.dart';
import 'package:voice_agent/features/recording/domain/stt_exception.dart';
import 'package:voice_agent/features/recording/domain/stt_service.dart';
import 'package:voice_agent/features/recording/presentation/recording_controller.dart';
import 'package:voice_agent/core/audio/audio_feedback_provider.dart';
import 'package:voice_agent/core/audio/audio_feedback_service.dart';
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

class FakeStorageService implements StorageService {
  final List<Transcript> savedTranscripts = [];
  final List<String> enqueuedIds = [];
  bool shouldThrowOnEnqueue = false;

  @override
  Future<String> getDeviceId() async => 'test-device';

  @override
  Future<void> saveTranscript(Transcript t) async {
    savedTranscripts.add(t);
  }

  @override
  Future<Transcript?> getTranscript(String id) async => null;

  @override
  Future<List<Transcript>> getTranscripts(
          {int limit = 50, int offset = 0}) async =>
      [];

  @override
  Future<void> deleteTranscript(String id) async {
    savedTranscripts.removeWhere((t) => t.id == id);
  }

  @override
  Future<void> enqueue(String transcriptId) async {
    if (shouldThrowOnEnqueue) throw Exception('enqueue failed');
    enqueuedIds.add(transcriptId);
  }

  @override
  Future<List<SyncQueueItem>> getPendingItems() async => [];

  @override
  Future<void> markSending(String id) async {}

  @override
  Future<void> markSent(String id) async {}

  @override
  Future<void> markFailed(String id, String error, {int? overrideAttempts}) async {}

  @override
  Future<void> markPendingForRetry(String id) async {}

  @override
  Future<void> reactivateForResend(String transcriptId) async {}

  @override
  Future<List<TranscriptWithStatus>> getTranscriptsWithStatus(
          {int limit = 20, int offset = 0}) async =>
      [];

  @override
  Future<int> recoverStaleSending() async => 0;

  @override
  Future<List<SyncQueueItem>> getFailedItems({int? maxAttempts}) async => [];
}

class _StubAudioFeedbackService implements AudioFeedbackService {
  @override Future<void> startProcessingFeedback() async {}
  @override Future<void> stopLoop() async {}
  @override Future<void> playSuccess() async {}
  @override Future<void> playError() async {}
  @override void dispose() {}
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
  FakeStorageService? fakeStorage,
  AppConfig config = const AppConfig(groqApiKey: 'test-key'),
}) {
  return ProviderContainer(
    overrides: [
      appConfigServiceProvider.overrideWithValue(_FixedConfigService(config)),
      recordingServiceProvider.overrideWithValue(fakeService),
      sttServiceProvider.overrideWithValue(fakeStt),
      storageServiceProvider.overrideWithValue(
        fakeStorage ?? FakeStorageService(),
      ),
      audioFeedbackServiceProvider.overrideWithValue(_StubAudioFeedbackService()),
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
  late FakeStorageService fakeStorage;
  late ProviderContainer container;
  late RecordingController controller;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    fakeService = FakeRecordingService();
    fakeStt = FakeSttService();
    fakeStorage = FakeStorageService();
    container = _makeContainer(
      fakeService: fakeService,
      fakeStt: fakeStt,
      fakeStorage: fakeStorage,
    );
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

  test(
      'stopAndTranscribe transitions through transcribing to idle and saves transcript',
      () async {
    fakeService.lastPath = '/tmp/test.wav';

    final states = <RecordingState>[];
    controller.addListener(states.add);

    await controller.stopAndTranscribe();

    expect(states.any((s) => s is RecordingTranscribing), isTrue);
    expect(controller.state, isA<RecordingIdle>());
    expect(fakeStorage.savedTranscripts, hasLength(1));
    expect(fakeStorage.savedTranscripts.first.text, 'Hello world');
    expect(fakeStorage.enqueuedIds, hasLength(1));
    expect(
      fakeStorage.enqueuedIds.first,
      fakeStorage.savedTranscripts.first.id,
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

  test('stopAndTranscribe rolls back transcript when enqueue fails', () async {
    fakeService.lastPath = '/tmp/test.wav';
    fakeStorage.shouldThrowOnEnqueue = true;

    await controller.stopAndTranscribe();

    expect(controller.state, isA<RecordingError>());
    expect(
      (controller.state as RecordingError).message,
      contains('Failed to enqueue transcript'),
    );
    // Rollback: transcript was deleted
    expect(fakeStorage.savedTranscripts, isEmpty);
  });

  test('stopAndTranscribe with silentOnEmpty returns idle for empty result',
      () async {
    fakeService.lastPath = '/tmp/test.wav';
    fakeStt.nextResult = const TranscriptResult(
      text: '',
      segments: [],
      detectedLanguage: 'en',
      audioDurationMs: 1000,
    );

    await controller.stopAndTranscribe(silentOnEmpty: true);

    expect(controller.state, isA<RecordingIdle>());
    expect(fakeStorage.savedTranscripts, isEmpty);
  });

  test(
      'stopAndTranscribe without silentOnEmpty emits error for empty result',
      () async {
    fakeService.lastPath = '/tmp/test.wav';
    fakeStt.nextResult = const TranscriptResult(
      text: '',
      segments: [],
      detectedLanguage: 'en',
      audioDurationMs: 1000,
    );

    await controller.stopAndTranscribe();

    expect(controller.state, isA<RecordingError>());
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
        case RecordingError():
          break;
      }
    }
    expect(states.length, 4);
  });
}
