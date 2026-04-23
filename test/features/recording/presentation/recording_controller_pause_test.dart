import 'dart:async';

import 'package:flutter/widgets.dart';
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
import 'package:voice_agent/features/recording/domain/stt_service.dart';
import 'package:voice_agent/features/recording/presentation/recording_controller.dart';
import 'package:voice_agent/core/audio/audio_feedback_provider.dart';
import 'package:voice_agent/core/audio/audio_feedback_service.dart';
import 'package:voice_agent/features/recording/presentation/recording_providers.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _FakeRecordingService implements RecordingService {
  bool _isRecording = false;
  String? lastPath;
  bool permissionGranted = true;
  int pauseCount = 0;
  int resumeCount = 0;
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
    _isRecording = false;
    return RecordingResult(
      filePath: lastPath ?? '/tmp/test.wav',
      duration: const Duration(seconds: 5),
      sampleRate: 16000,
    );
  }

  @override
  Future<void> pause() async {
    pauseCount++;
  }

  @override
  Future<void> resume() async {
    resumeCount++;
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

class _FakeSttService implements SttService {
  @override
  Future<bool> isModelLoaded() async => true;

  @override
  Future<void> loadModel() async {}

  @override
  Future<TranscriptResult> transcribe(
    String audioFilePath, {
    String? languageCode,
  }) async {
    return const TranscriptResult(
      text: 'Hello world',
      segments: [],
      detectedLanguage: 'en',
      audioDurationMs: 5000,
    );
  }
}

class _FakeStorageService implements StorageService {
  final List<Transcript> savedTranscripts = [];
  final List<String> enqueuedIds = [];

  @override
  Future<String> getDeviceId() async => 'test-device';
  @override
  Future<void> saveTranscript(Transcript t) async => savedTranscripts.add(t);
  @override
  Future<Transcript?> getTranscript(String id) async => null;
  @override
  Future<List<Transcript>> getTranscripts(
          {int limit = 50, int offset = 0}) async =>
      [];
  @override
  Future<void> deleteTranscript(String id) async {}
  @override
  Future<void> enqueue(String transcriptId) async =>
      enqueuedIds.add(transcriptId);
  @override
  Future<List<SyncQueueItem>> getPendingItems() async => [];
  @override
  Future<void> markSending(String id) async {}
  @override
  Future<void> markSent(String id) async {}
  @override
  Future<void> markFailed(String id, String error,
      {int? overrideAttempts}) async {}
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
  @override
  Future<void> startProcessingFeedback() async {}
  @override
  Future<void> stopLoop() async {}
  @override
  Future<void> playSuccess() async {}
  @override
  Future<void> playError() async {}
  @override
  void dispose() {}
}

class _FixedConfigService extends AppConfigService {
  _FixedConfigService(this._config);
  final AppConfig _config;

  @override
  Future<AppConfig> load() async => _config;
}

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

ProviderContainer _makeContainer({
  required _FakeRecordingService fakeService,
  required _FakeSttService fakeStt,
  _FakeStorageService? fakeStorage,
  AppConfig config = const AppConfig(groqApiKey: 'test-key'),
}) {
  return ProviderContainer(
    overrides: [
      appConfigServiceProvider.overrideWithValue(_FixedConfigService(config)),
      recordingServiceProvider.overrideWithValue(fakeService),
      sttServiceProvider.overrideWithValue(fakeStt),
      storageServiceProvider
          .overrideWithValue(fakeStorage ?? _FakeStorageService()),
      audioFeedbackServiceProvider
          .overrideWithValue(_StubAudioFeedbackService()),
    ],
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeRecordingService fakeService;
  late _FakeSttService fakeStt;
  late ProviderContainer container;
  late RecordingController controller;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    fakeService = _FakeRecordingService();
    fakeStt = _FakeSttService();
    container = _makeContainer(fakeService: fakeService, fakeStt: fakeStt);
    controller = container.read(recordingControllerProvider.notifier);
  });

  tearDown(() {
    container.dispose();
  });

  group('pauseRecording', () {
    test('transitions from RecordingActive to RecordingPaused', () async {
      // Simulate being in RecordingActive state
      // ignore: invalid_use_of_protected_member
      controller.state = const RecordingState.recording();
      expect(controller.state, isA<RecordingActive>());

      await controller.pauseRecording();

      expect(controller.state, isA<RecordingPaused>());
      expect(fakeService.pauseCount, 1);
    });

    test('is no-op when not RecordingActive', () async {
      // From idle
      await controller.pauseRecording();
      expect(controller.state, isA<RecordingIdle>());
      expect(fakeService.pauseCount, 0);
    });

    test('is no-op from RecordingPaused (already paused)', () async {
      // ignore: invalid_use_of_protected_member
      controller.state = const RecordingState.recording();
      await controller.pauseRecording();
      expect(controller.state, isA<RecordingPaused>());

      // Pause again — should not double-pause
      await controller.pauseRecording();
      expect(controller.state, isA<RecordingPaused>());
      expect(fakeService.pauseCount, 1);
    });
  });

  group('resumeRecording', () {
    test('transitions from RecordingPaused to RecordingActive', () async {
      // ignore: invalid_use_of_protected_member
      controller.state = const RecordingState.recording();
      await controller.pauseRecording();
      expect(controller.state, isA<RecordingPaused>());

      await controller.resumeRecording();

      expect(controller.state, isA<RecordingActive>());
      expect(fakeService.resumeCount, 1);
    });

    test('is no-op when not RecordingPaused', () async {
      // From idle
      await controller.resumeRecording();
      expect(controller.state, isA<RecordingIdle>());
      expect(fakeService.resumeCount, 0);
    });

    test('is no-op from RecordingActive (not paused)', () async {
      // ignore: invalid_use_of_protected_member
      controller.state = const RecordingState.recording();
      await controller.resumeRecording();
      expect(controller.state, isA<RecordingActive>());
      expect(fakeService.resumeCount, 0);
    });
  });

  group('app lifecycle', () {
    test('cancels from RecordingPaused state', () async {
      // ignore: invalid_use_of_protected_member
      controller.state = const RecordingState.recording();
      await controller.pauseRecording();
      expect(controller.state, isA<RecordingPaused>());

      controller.didChangeAppLifecycleState(AppLifecycleState.paused);
      await Future.delayed(Duration.zero);

      expect(controller.state, isA<RecordingIdle>());
    });

    test('cancels from RecordingActive state', () async {
      // ignore: invalid_use_of_protected_member
      controller.state = const RecordingState.recording();
      expect(controller.state, isA<RecordingActive>());

      controller.didChangeAppLifecycleState(AppLifecycleState.paused);
      await Future.delayed(Duration.zero);

      expect(controller.state, isA<RecordingIdle>());
    });

    test('does not cancel from RecordingIdle', () async {
      controller.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(controller.state, isA<RecordingIdle>());
    });
  });
}
