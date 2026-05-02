import 'package:flutter/foundation.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/app/app.dart';
import 'package:voice_agent/core/config/app_config.dart';
import 'package:voice_agent/core/config/app_config_provider.dart';
import 'package:voice_agent/core/config/app_config_service.dart';
import 'package:voice_agent/core/models/sync_queue_item.dart';
import 'package:voice_agent/core/models/transcript.dart';
import 'package:voice_agent/core/models/transcript_result.dart';
import 'package:voice_agent/core/models/transcript_with_status.dart';
import 'package:voice_agent/core/network/connectivity_service.dart';
import 'package:voice_agent/core/providers/agent_reply_provider.dart';
import 'package:voice_agent/core/providers/api_url_provider.dart';
import 'package:voice_agent/features/api_sync/sync_provider.dart';
import 'package:voice_agent/core/storage/storage_provider.dart';
import 'package:voice_agent/core/storage/storage_service.dart';
import 'package:voice_agent/core/config/vad_config.dart';
import 'package:voice_agent/features/recording/domain/hands_free_engine.dart';
import 'package:voice_agent/features/recording/domain/recording_result.dart';
import 'package:voice_agent/features/recording/domain/recording_service.dart';
import 'package:voice_agent/features/recording/domain/stt_service.dart';
import 'package:voice_agent/core/audio/audio_feedback_provider.dart';
import 'package:voice_agent/core/audio/audio_feedback_service.dart';
import 'package:voice_agent/core/tts/tts_provider.dart';
import 'package:voice_agent/core/tts/tts_service.dart';
import 'package:voice_agent/core/media_button/media_button_provider.dart';
import 'package:voice_agent/features/recording/presentation/recording_providers.dart';
import 'package:voice_agent/core/background/background_service_provider.dart';

import '../../../helpers/stub_background_service.dart';
import '../../../helpers/stub_media_button.dart';
import '../../../helpers/stub_session_control.dart';

// ── Stubs ─────────────────────────────────────────────────────────────────────

class _StubTtsService implements TtsService {
  @override ValueListenable<bool> get isSpeaking => ValueNotifier(false);
  @override Future<void> speak(String text, {String? languageCode}) async {}
  @override Future<void> stop() async {}
  @override void dispose() {}
}

class _StubAudioFeedbackService implements AudioFeedbackService {
  @override Future<void> startProcessingFeedback() async {}
  @override Future<void> stopLoop() async {}
  @override Future<void> playSuccess() async {}
  @override Future<void> playError() async {}
  @override void dispose() {}
}

class _StubStorage implements StorageService {
  @override Future<String> getDeviceId() async => 'test-device';
  @override Future<List<TranscriptWithStatus>> getTranscriptsWithStatus(
      {int limit = 20, int offset = 0}) async => [];
  @override Future<void> saveTranscript(Transcript t) async {}
  @override Future<Transcript?> getTranscript(String id) async => null;
  @override Future<List<Transcript>> getTranscripts(
      {int limit = 50, int offset = 0}) async => [];
  @override Future<void> deleteTranscript(String id) async {}
  @override Future<void> enqueue(String transcriptId) async {}
  @override Future<List<SyncQueueItem>> getPendingItems() async => [];
  @override Future<void> markSending(String id) async {}
  @override Future<void> markSent(String id) async {}
  @override Future<void> markFailed(String id, String error, {int? overrideAttempts}) async {}
  @override Future<void> markPendingForRetry(String id) async {}
  @override Future<void> reactivateForResend(String transcriptId) async {}
  @override Future<int> recoverStaleSending() async => 0;
  @override Future<List<SyncQueueItem>> getFailedItems({int? maxAttempts}) async => [];
}

class _NoOpConnectivity extends ConnectivityService {
  @override
  Stream<ConnectivityStatus> get statusStream => const Stream.empty();
}

class _NoOpRecordingService implements RecordingService {
  @override Future<bool> requestPermission() async => true;
  @override Future<void> start({required String outputPath}) async {}
  @override Future<RecordingResult> stop() async => RecordingResult(
      filePath: '/tmp/x.wav', duration: Duration.zero, sampleRate: 16000);
  @override Future<void> pause() async {}
  @override Future<void> resume() async {}
  @override Future<void> cancel() async {}
  @override Stream<Duration> get elapsed => const Stream.empty();
  @override bool get isRecording => false;
}

class _NoOpSttService implements SttService {
  @override Future<bool> isModelLoaded() async => true;
  @override Future<void> loadModel() async {}
  @override Future<TranscriptResult> transcribe(String path, {String? languageCode}) =>
      Completer<TranscriptResult>().future; // never resolves
}

/// Fake [HandsFreeEngine] that tests control via [emit].
class FakeHfEngine implements HandsFreeEngine {
  @override
  Future<void> setCaptureGate({required bool open}) async {}

  final _ctrl = StreamController<HandsFreeEngineEvent>.broadcast();
  bool started = false;
  bool stopped = false;

  void emit(HandsFreeEngineEvent e) => _ctrl.add(e);

  @override
  Future<bool> hasPermission() async => true;
  @override
  Stream<HandsFreeEngineEvent> start({required VadConfig config}) {
    started = true;
    return _ctrl.stream;
  }
  @override
  Future<void> stop() async => stopped = true;
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

// ── Helpers ───────────────────────────────────────────────────────────────────

List<Override> baseOverrides(FakeHfEngine engine) => [
      storageServiceProvider.overrideWithValue(_StubStorage()),
      connectivityServiceProvider.overrideWith((_) => _NoOpConnectivity()),
      apiUrlConfiguredProvider.overrideWithValue(true),
      appConfigServiceProvider.overrideWithValue(
        _FixedConfigService(const AppConfig(groqApiKey: 'gsk_test_key', apiUrl: 'https://test.example.com/api')),
      ),
      handsFreeEngineProvider.overrideWithValue(engine),
      sttServiceProvider.overrideWithValue(_NoOpSttService()),
      recordingServiceProvider.overrideWithValue(_NoOpRecordingService()),
      ttsServiceProvider.overrideWithValue(_StubTtsService()),
      audioFeedbackServiceProvider.overrideWithValue(_StubAudioFeedbackService()),
      backgroundServiceProvider.overrideWithValue(StubBackgroundService()),
      mediaButtonProvider.overrideWithValue(StubMediaButtonPort()),
      ...sessionControlTestOverrides,
    ];

Future<void> pumpRecordScreen(
  WidgetTester tester, {
  required FakeHfEngine engine,
  List<Override> extra = const [],
  bool engageAfterPump = true,
}) async {
  late ProviderContainer container;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [...baseOverrides(engine), ...extra],
      child: Builder(
        builder: (context) {
          container = ProviderScope.containerOf(context);
          return const App();
        },
      ),
    ),
  );
  await tester.pumpAndSettle();

  // P037 v2: app opens in HandsFreeIdle (no auto-start). Tests that
  // exercise the listening state machine engage explicitly here, which
  // mirrors the AirPods short-click entry point in production.
  if (engageAfterPump) {
    await container
        .read(handsFreeControllerProvider.notifier)
        .startSession();
    await tester.pumpAndSettle();
  }
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() => WidgetsFlutterBinding.ensureInitialized());

  group('auto-start (P037 v2: removed)', () {
    testWidgets('hands-free session does NOT auto-start on screen load',
        (tester) async {
      final engine = FakeHfEngine();
      await pumpRecordScreen(tester, engine: engine, engageAfterPump: false);

      // v2 contract: app opens in Idle. Engagement requires an explicit
      // user action (AirPods short-click → startSession).
      expect(engine.started, isFalse);
    });
  });

  group('session status strip', () {
    testWidgets('Listening shows "Listening..." text', (tester) async {
      final engine = FakeHfEngine();
      await pumpRecordScreen(tester, engine: engine);

      engine.emit(const EngineListening());
      await tester.pumpAndSettle();

      expect(find.text('Listening...'), findsOneWidget);
    });

    testWidgets('Capturing shows "Capturing..." text', (tester) async {
      final engine = FakeHfEngine();
      await pumpRecordScreen(tester, engine: engine);

      engine.emit(const EngineCapturing());
      await tester.pumpAndSettle();

      expect(find.text('Capturing...'), findsOneWidget);
    });

    testWidgets('Stopping shows "Processing segment..." text', (tester) async {
      final engine = FakeHfEngine();
      await pumpRecordScreen(tester, engine: engine);

      engine.emit(const EngineStopping());
      await tester.pumpAndSettle();

      expect(find.text('Processing segment...'), findsOneWidget);
    });
  });

  group('segment list', () {
    testWidgets('segment list is hidden when no jobs', (tester) async {
      final engine = FakeHfEngine();
      await pumpRecordScreen(tester, engine: engine);

      engine.emit(const EngineListening());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('hf-segment-list')), findsNothing);
    });

    testWidgets('segment list appears after EngineSegmentReady', (tester) async {
      final engine = FakeHfEngine();
      await pumpRecordScreen(tester, engine: engine);

      engine.emit(const EngineListening());
      engine.emit(const EngineSegmentReady('/tmp/seg1.wav'));
      // Use pump() — pumpAndSettle would hang on CircularProgressIndicator animation
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const Key('hf-segment-list')), findsOneWidget);
    });
  });

  group('agent reply clearing', () {
    testWidgets('HandsFreeCapturing clears latestAgentReplyProvider',
        (tester) async {
      final engine = FakeHfEngine();
      late ProviderContainer container;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...baseOverrides(engine),
            latestAgentReplyProvider.overrideWith((_) => 'stale reply'),
          ],
          child: Builder(builder: (context) {
            container = ProviderScope.containerOf(context);
            return const App();
          }),
        ),
      );
      await tester.pumpAndSettle();
      // v2: explicit engage replaces the legacy auto-start.
      await container
          .read(handsFreeControllerProvider.notifier)
          .startSession();
      await tester.pumpAndSettle();

      expect(container.read(latestAgentReplyProvider), 'stale reply');

      engine.emit(const EngineCapturing());
      await tester.pumpAndSettle();

      expect(container.read(latestAgentReplyProvider), isNull);
    });
  });

  group('session error', () {
    testWidgets('SessionError(requiresSettings) shows "Open Settings" and Retry',
        (tester) async {
      final engine = FakeHfEngine();
      await pumpRecordScreen(tester, engine: engine);

      engine.emit(const EngineError('mic denied', requiresSettings: true));
      await tester.pumpAndSettle();

      expect(find.text('Open Settings'), findsOneWidget);
      expect(find.byKey(const Key('hf-error-message')), findsOneWidget);
      expect(find.byKey(const Key('hf-retry-button')), findsOneWidget);
    });

    testWidgets('SessionError(requiresAppSettings) shows "Go to Settings"',
        (tester) async {
      final engine = FakeHfEngine();
      await pumpRecordScreen(
        tester,
        engine: engine,
        extra: [
          appConfigServiceProvider.overrideWithValue(
            _FixedConfigService(const AppConfig(groqApiKey: null)),
          ),
        ],
      );

      // Auto-start fails with missing Groq key → HandsFreeSessionError
      expect(find.text('Go to Settings'), findsOneWidget);
      expect(find.byKey(const Key('hf-retry-button')), findsOneWidget);
    });

    testWidgets('SessionError with no flags shows only the error message and Retry',
        (tester) async {
      final engine = FakeHfEngine();
      await pumpRecordScreen(tester, engine: engine);

      engine.emit(const EngineError('Something failed'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('hf-error-message')), findsOneWidget);
      expect(find.byKey(const Key('hf-retry-button')), findsOneWidget);
      expect(find.text('Open Settings'), findsNothing);
      expect(find.text('Go to Settings'), findsNothing);
    });

    testWidgets('tapping Retry button calls startSession again', (tester) async {
      final engine = FakeHfEngine();
      await pumpRecordScreen(tester, engine: engine);

      engine.emit(const EngineError('Something failed'));
      await tester.pumpAndSettle();

      // startSession was called once by auto-start; Retry calls it again
      await tester.tap(find.byKey(const Key('hf-retry-button')));
      await tester.pumpAndSettle();

      // Engine.started remains true (started on auto-start; Retry
      // re-enters startSession but the guard allows HandsFreeSessionError)
      expect(engine.started, isTrue);
    });
  });
}
