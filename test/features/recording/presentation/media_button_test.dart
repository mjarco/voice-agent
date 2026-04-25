import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/app/app.dart';
import 'package:voice_agent/core/audio/audio_feedback_provider.dart';
import 'package:voice_agent/core/audio/audio_feedback_service.dart';
import 'package:voice_agent/core/config/app_config.dart';
import 'package:voice_agent/core/config/app_config_provider.dart';
import 'package:voice_agent/core/config/app_config_service.dart';
import 'package:voice_agent/core/config/vad_config.dart';
import 'package:voice_agent/core/media_button/media_button_port.dart';
import 'package:voice_agent/core/media_button/media_button_provider.dart';
import 'package:voice_agent/core/models/sync_queue_item.dart';
import 'package:voice_agent/core/models/transcript.dart';
import 'package:voice_agent/core/models/transcript_result.dart';
import 'package:voice_agent/core/models/transcript_with_status.dart';
import 'package:voice_agent/core/network/connectivity_service.dart';
import 'package:voice_agent/core/providers/api_url_provider.dart';
import 'package:voice_agent/core/session_control/haptic_service.dart';
import 'package:voice_agent/core/session_control/session_control_provider.dart';
import 'package:voice_agent/core/storage/storage_provider.dart';
import 'package:voice_agent/core/storage/storage_service.dart';
import 'package:voice_agent/core/tts/tts_provider.dart';
import 'package:voice_agent/core/tts/tts_service.dart';
import 'package:voice_agent/features/api_sync/sync_provider.dart';
import 'package:voice_agent/features/recording/domain/hands_free_engine.dart';
import 'package:voice_agent/features/recording/domain/hands_free_session_state.dart';
import 'package:voice_agent/features/recording/domain/recording_result.dart';
import 'package:voice_agent/features/recording/domain/recording_service.dart';
import 'package:voice_agent/features/recording/domain/recording_state.dart';
import 'package:voice_agent/features/recording/domain/stt_service.dart';
import 'package:voice_agent/features/recording/presentation/recording_controller.dart';
import 'package:voice_agent/features/recording/presentation/recording_providers.dart';
import 'package:voice_agent/core/background/background_service_provider.dart';

import '../../../helpers/stub_background_service.dart';
import '../../../helpers/stub_session_control.dart';

// ── Stubs ────────────────────────────────────────────────────────────────────

class _StubTtsService implements TtsService {
  @override
  ValueListenable<bool> get isSpeaking => ValueNotifier(false);

  @override
  Future<void> speak(String text, {String? languageCode}) async {}

  @override
  Future<void> stop() async {}

  @override
  void dispose() {}
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

class _StubStorage implements StorageService {
  @override
  Future<String> getDeviceId() async => 'test-device';

  @override
  Future<List<TranscriptWithStatus>> getTranscriptsWithStatus(
          {int limit = 20, int offset = 0}) async =>
      [];

  @override
  Future<void> saveTranscript(Transcript t) async {}

  @override
  Future<Transcript?> getTranscript(String id) async => null;

  @override
  Future<List<Transcript>> getTranscripts(
          {int limit = 50, int offset = 0}) async =>
      [];

  @override
  Future<void> deleteTranscript(String id) async {}

  @override
  Future<void> enqueue(String transcriptId) async {}

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
  Future<int> recoverStaleSending() async => 0;

  @override
  Future<List<SyncQueueItem>> getFailedItems({int? maxAttempts}) async => [];
}

class _NoOpConnectivity extends ConnectivityService {
  @override
  Stream<ConnectivityStatus> get statusStream => const Stream.empty();
}

class _NoOpRecordingService implements RecordingService {
  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> start({required String outputPath}) async {}

  @override
  Future<RecordingResult> stop() async => RecordingResult(
      filePath: '/tmp/x.wav', duration: Duration.zero, sampleRate: 16000);

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<void> cancel() async {}

  @override
  Stream<Duration> get elapsed => const Stream.empty();

  @override
  bool get isRecording => false;
}

class _NoOpSttService implements SttService {
  @override
  Future<bool> isModelLoaded() async => true;

  @override
  Future<void> loadModel() async {}

  @override
  Future<TranscriptResult> transcribe(String path,
          {String? languageCode}) =>
      Completer<TranscriptResult>().future;
}

class _FakeHfEngine implements HandsFreeEngine {
  final _ctrl = StreamController<HandsFreeEngineEvent>.broadcast();
  bool started = false;

  void emit(HandsFreeEngineEvent e) => _ctrl.add(e);

  @override
  Future<bool> hasPermission() async => true;

  @override
  Stream<HandsFreeEngineEvent> start({required VadConfig config}) {
    started = true;
    return _ctrl.stream;
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> interruptCapture() async {}

  @override
  void dispose() => _ctrl.close();
}

class _FixedConfigService extends AppConfigService {
  _FixedConfigService(this._config);
  final AppConfig _config;

  @override
  Future<AppConfig> load() async => _config;
}

class _StubHapticService extends HapticService {
  @override
  Future<void> lightImpact() async {}
}

/// Bypasses path_provider and async I/O for tests.
class _FakeRecordingController extends RecordingController {
  _FakeRecordingController(super.svc, super.stt, super.ref);

  @override
  Future<void> startRecording() async {
    state = const RecordingState.recording();
  }

  @override
  Future<void> stopAndTranscribe({bool silentOnEmpty = false}) async {
    state = const RecordingState.transcribing();
  }
}

/// Media button port with a **synchronous** broadcast controller so events
/// fire immediately inside FakeAsync test zones.
class _SyncMediaButtonPort implements MediaButtonPort {
  final _controller =
      StreamController<MediaButtonEvent>.broadcast(sync: true);

  @override
  Stream<MediaButtonEvent> get events => _controller.stream;

  @override
  Future<void> activate() async {}

  @override
  Future<void> deactivate() async {}

  void emit(MediaButtonEvent event) => _controller.add(event);

  void dispose() => _controller.close();
}

// ── Helpers ──────────────────────────────────────────────────────────────────

List<Override> _baseOverrides({
  required _FakeHfEngine engine,
  required _SyncMediaButtonPort mediaButton,
}) =>
    [
      storageServiceProvider.overrideWithValue(_StubStorage()),
      connectivityServiceProvider.overrideWith((_) => _NoOpConnectivity()),
      apiUrlConfiguredProvider.overrideWithValue(true),
      appConfigServiceProvider.overrideWithValue(
        _FixedConfigService(const AppConfig(groqApiKey: 'gsk_test_key')),
      ),
      handsFreeEngineProvider.overrideWithValue(engine),
      sttServiceProvider.overrideWithValue(_NoOpSttService()),
      recordingServiceProvider.overrideWithValue(_NoOpRecordingService()),
      recordingControllerProvider.overrideWith((ref) =>
          _FakeRecordingController(
            ref.read(recordingServiceProvider),
            ref.read(sttServiceProvider),
            ref,
          )),
      ttsServiceProvider.overrideWithValue(_StubTtsService()),
      audioFeedbackServiceProvider
          .overrideWithValue(_StubAudioFeedbackService()),
      backgroundServiceProvider.overrideWithValue(StubBackgroundService()),
      mediaButtonProvider.overrideWithValue(mediaButton),
      hapticServiceProvider.overrideWithValue(_StubHapticService()),
      ...sessionControlTestOverrides,
    ];

Future<ProviderContainer> _pumpApp(
  WidgetTester tester, {
  required _FakeHfEngine engine,
  required _SyncMediaButtonPort mediaButton,
}) async {
  late ProviderContainer container;
  await tester.pumpWidget(
    ProviderScope(
      overrides: _baseOverrides(engine: engine, mediaButton: mediaButton),
      child: Builder(builder: (context) {
        container = ProviderScope.containerOf(context);
        return const App();
      }),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// Emits a media button event inside [runAsync] so the async handler chain
/// completes outside FakeAsync, then pumps the widget tree.
Future<void> _emitMediaButton(
  WidgetTester tester,
  _SyncMediaButtonPort mediaButton,
) async {
  await tester.runAsync(() async {
    mediaButton.emit(MediaButtonEvent.togglePlayPause);
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });
  await tester.pump();
}

// ── Tests ────────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() => WidgetsFlutterBinding.ensureInitialized());

  group('media button during hands-free listening', () {
    testWidgets('suspends session', (tester) async {
      final engine = _FakeHfEngine();
      final mediaButton = _SyncMediaButtonPort();
      final container = await _pumpApp(tester,
          engine: engine, mediaButton: mediaButton);

      engine.emit(const EngineListening());
      await tester.pumpAndSettle();
      expect(container.read(handsFreeControllerProvider),
          isA<HandsFreeListening>());

      await _emitMediaButton(tester, mediaButton);

      expect(container.read(handsFreeControllerProvider),
          isA<HandsFreeSuspendedByUser>());
    });

    testWidgets('resumes from user suspension', (tester) async {
      final engine = _FakeHfEngine();
      final mediaButton = _SyncMediaButtonPort();
      final container = await _pumpApp(tester,
          engine: engine, mediaButton: mediaButton);

      engine.emit(const EngineListening());
      await tester.pumpAndSettle();

      await _emitMediaButton(tester, mediaButton);
      expect(container.read(handsFreeControllerProvider),
          isA<HandsFreeSuspendedByUser>());

      await _emitMediaButton(tester, mediaButton);

      final state = container.read(handsFreeControllerProvider);
      expect(
          state,
          anyOf(
            isA<HandsFreeListening>(),
            isA<HandsFreeWithBacklog>(),
          ));
    });
  });

  group('media button during manual recording', () {
    testWidgets('pauses active recording', (tester) async {
      final engine = _FakeHfEngine();
      final mediaButton = _SyncMediaButtonPort();
      final container = await _pumpApp(tester,
          engine: engine, mediaButton: mediaButton);

      await tester.tap(find.byKey(const Key('record-button')));
      await tester.pumpAndSettle();
      expect(container.read(recordingControllerProvider),
          isA<RecordingActive>());

      await _emitMediaButton(tester, mediaButton);

      expect(container.read(recordingControllerProvider),
          isA<RecordingPaused>());
    });

    testWidgets('resumes paused recording', (tester) async {
      final engine = _FakeHfEngine();
      final mediaButton = _SyncMediaButtonPort();
      final container = await _pumpApp(tester,
          engine: engine, mediaButton: mediaButton);

      await tester.tap(find.byKey(const Key('record-button')));
      await tester.pumpAndSettle();
      await tester.runAsync(() =>
          container.read(recordingControllerProvider.notifier).pauseRecording());
      await tester.pump();
      expect(container.read(recordingControllerProvider),
          isA<RecordingPaused>());

      await _emitMediaButton(tester, mediaButton);

      expect(container.read(recordingControllerProvider),
          isA<RecordingActive>());
    });
  });

  group('media button during transcription', () {
    testWidgets('cancels in-flight transcription', (tester) async {
      final engine = _FakeHfEngine();
      final mediaButton = _SyncMediaButtonPort();
      final container = await _pumpApp(tester,
          engine: engine, mediaButton: mediaButton);

      // Tap record, then tap again — _FakeRecordingController sets
      // state to transcribing and stays there (STT never resolves).
      await tester.tap(find.byKey(const Key('record-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('record-button')));
      // Use pump() — pumpAndSettle would hang on the spinner animation.
      await tester.pump();
      await tester.pump();
      expect(container.read(recordingControllerProvider),
          isA<RecordingTranscribing>());

      await _emitMediaButton(tester, mediaButton);

      expect(
          container.read(recordingControllerProvider), isA<RecordingIdle>());
    });
  });

  group('media button during HF stopping', () {
    testWidgets('suspends during HandsFreeStopping', (tester) async {
      final engine = _FakeHfEngine();
      final mediaButton = _SyncMediaButtonPort();
      final container = await _pumpApp(tester,
          engine: engine, mediaButton: mediaButton);

      engine.emit(const EngineStopping());
      await tester.pumpAndSettle();
      expect(container.read(handsFreeControllerProvider),
          isA<HandsFreeStopping>());

      await _emitMediaButton(tester, mediaButton);

      expect(container.read(handsFreeControllerProvider),
          isA<HandsFreeSuspendedByUser>());
    });
  });
}
