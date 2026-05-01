import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/app/app.dart';
import 'package:voice_agent/core/audio/audio_feedback_provider.dart';
import 'package:voice_agent/core/audio/audio_feedback_service.dart';
import 'package:voice_agent/core/background/background_service_provider.dart';
import 'package:voice_agent/core/config/app_config.dart';
import 'package:voice_agent/core/config/app_config_provider.dart';
import 'package:voice_agent/core/config/app_config_service.dart';
import 'package:voice_agent/core/config/vad_config.dart';
import 'package:voice_agent/core/models/sync_queue_item.dart';
import 'package:voice_agent/core/models/transcript.dart';
import 'package:voice_agent/core/models/transcript_result.dart';
import 'package:voice_agent/core/models/transcript_with_status.dart';
import 'package:voice_agent/core/network/connectivity_service.dart';
import 'package:voice_agent/core/providers/api_url_provider.dart';
import 'package:voice_agent/features/api_sync/sync_provider.dart';
import 'package:voice_agent/core/session_control/hands_free_control_port.dart';
import 'package:voice_agent/core/session_control/haptic_service.dart';
import 'package:voice_agent/core/session_control/session_control_provider.dart';
import 'package:voice_agent/core/session_control/session_id_coordinator.dart';
import 'package:voice_agent/core/session_control/toaster.dart';
import 'package:voice_agent/core/storage/storage_provider.dart';
import 'package:voice_agent/core/storage/storage_service.dart';
import 'package:voice_agent/core/tts/tts_provider.dart';
import 'package:voice_agent/core/tts/tts_service.dart';
import 'package:voice_agent/features/recording/domain/hands_free_engine.dart';
import 'package:voice_agent/features/recording/domain/recording_result.dart';
import 'package:voice_agent/core/media_button/media_button_provider.dart';
import 'package:voice_agent/features/recording/domain/recording_service.dart';
import 'package:voice_agent/features/recording/domain/stt_service.dart';
import 'package:voice_agent/features/recording/presentation/recording_providers.dart';

import '../../../helpers/stub_background_service.dart';
import '../../../helpers/stub_media_button.dart';

// ── Stubs ────────────────────────────────────────────────────────────────────

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

class _IdleHfEngine implements HandsFreeEngine {
  final _ctrl = StreamController<HandsFreeEngineEvent>.broadcast();
  @override
  Future<bool> hasPermission() async => true;
  @override
  Stream<HandsFreeEngineEvent> start({required VadConfig config}) =>
      _ctrl.stream;
  @override
  Future<void> stop() async {}
  @override
  Future<void> interruptCapture() async {}
  @override
  void dispose() => _ctrl.close();
}

/// Fake [HandsFreeEngine] that tests control via [emit].
class _FakeHfEngine implements HandsFreeEngine {
  final _ctrl = StreamController<HandsFreeEngineEvent>.broadcast();

  void emit(HandsFreeEngineEvent e) => _ctrl.add(e);

  @override
  Future<bool> hasPermission() async => true;
  @override
  Stream<HandsFreeEngineEvent> start({required VadConfig config}) =>
      _ctrl.stream;
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
      Completer<TranscriptResult>().future; // never resolves
}

// ── Spy doubles ──────────────────────────────────────────────────────────────

class _SpySessionIdCoordinator extends SessionIdCoordinator {
  int resetCount = 0;

  @override
  Future<void> resetSession() async {
    resetCount++;
    await super.resetSession();
  }
}

class _SpyToaster extends Toaster {
  _SpyToaster() : super(GlobalKey<ScaffoldMessengerState>());

  final List<String> messages = [];

  @override
  void show(String message, {Duration duration = const Duration(seconds: 2)}) {
    messages.add(message);
  }
}

class _SpyHapticService extends HapticService {
  int lightImpactCount = 0;

  @override
  Future<void> lightImpact() async {
    lightImpactCount++;
  }
}

// ── Helpers ──────────────────────────────────────────────────────────────────

List<Override> _baseOverrides({
  HandsFreeEngine? engine,
  SessionIdCoordinator? coordinator,
  Toaster? toaster,
  HapticService? hapticService,
}) =>
    [
      storageServiceProvider.overrideWithValue(_StubStorage()),
      connectivityServiceProvider.overrideWith((_) => _NoOpConnectivity()),
      apiUrlConfiguredProvider.overrideWithValue(true),
      appConfigServiceProvider.overrideWithValue(
        _FixedConfigService(const AppConfig(groqApiKey: 'gsk_test_key', apiUrl: 'https://test.example.com/api')),
      ),
      handsFreeEngineProvider.overrideWithValue(engine ?? _IdleHfEngine()),
      sttServiceProvider.overrideWithValue(_NoOpSttService()),
      recordingServiceProvider.overrideWithValue(_NoOpRecordingService()),
      ttsServiceProvider.overrideWithValue(_StubTtsService()),
      audioFeedbackServiceProvider
          .overrideWithValue(_StubAudioFeedbackService()),
      backgroundServiceProvider.overrideWithValue(StubBackgroundService()),
      mediaButtonProvider.overrideWithValue(StubMediaButtonPort()),
      sessionIdCoordinatorProvider
          .overrideWithValue(coordinator ?? SessionIdCoordinator()),
      handsFreeControlPortProvider
          .overrideWithValue(_StubHandsFreeControlPort()),
      toasterProvider.overrideWithValue(
          toaster ?? _SpyToaster()),
      hapticServiceProvider
          .overrideWithValue(hapticService ?? _SpyHapticService()),
    ];

class _StubHandsFreeControlPort implements HandsFreeControlPort {
  @override
  bool get isSuspendedForManualRecording => false;

  @override
  Future<void> stopSession() async {}
}

// ── Tests ────────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() => WidgetsFlutterBinding.ensureInitialized());

  group('New conversation button', () {
    testWidgets('button exists in AppBar', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: _baseOverrides(),
          child: const App(),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('new-conversation-button')),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.add_comment_outlined), findsOneWidget);
    });

    testWidgets('button is enabled when idle (no active recording)',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: _baseOverrides(),
          child: const App(),
        ),
      );
      await tester.pumpAndSettle();

      final iconButton = tester.widget<IconButton>(
        find.byKey(const Key('new-conversation-button')),
      );
      expect(iconButton.onPressed, isNotNull);
    });

    testWidgets('button is enabled when hands-free is listening',
        (tester) async {
      final engine = _FakeHfEngine();
      await tester.pumpWidget(
        ProviderScope(
          overrides: _baseOverrides(engine: engine),
          child: const App(),
        ),
      );
      await tester.pumpAndSettle();

      engine.emit(const EngineListening());
      await tester.pumpAndSettle();

      final iconButton = tester.widget<IconButton>(
        find.byKey(const Key('new-conversation-button')),
      );
      expect(iconButton.onPressed, isNotNull);
    });

    testWidgets('button is disabled when hands-free is capturing',
        (tester) async {
      final engine = _FakeHfEngine();
      late ProviderContainer container;
      await tester.pumpWidget(
        ProviderScope(
          overrides: _baseOverrides(engine: engine),
          child: Builder(builder: (context) {
            container = ProviderScope.containerOf(context);
            return const App();
          }),
        ),
      );
      await tester.pumpAndSettle();

      // P037 v2: app opens in Idle. Engage so the controller subscribes
      // to the engine stream and reflects the emitted phase.
      await container
          .read(handsFreeControllerProvider.notifier)
          .startSession();
      await tester.pumpAndSettle();

      engine.emit(const EngineCapturing());
      await tester.pumpAndSettle();

      final iconButton = tester.widget<IconButton>(
        find.byKey(const Key('new-conversation-button')),
      );
      expect(iconButton.onPressed, isNull);
    });

    testWidgets('button is disabled when hands-free is stopping',
        (tester) async {
      final engine = _FakeHfEngine();
      late ProviderContainer container;
      await tester.pumpWidget(
        ProviderScope(
          overrides: _baseOverrides(engine: engine),
          child: Builder(builder: (context) {
            container = ProviderScope.containerOf(context);
            return const App();
          }),
        ),
      );
      await tester.pumpAndSettle();

      await container
          .read(handsFreeControllerProvider.notifier)
          .startSession();
      await tester.pumpAndSettle();

      engine.emit(const EngineStopping());
      await tester.pumpAndSettle();

      final iconButton = tester.widget<IconButton>(
        find.byKey(const Key('new-conversation-button')),
      );
      expect(iconButton.onPressed, isNull);
    });

    testWidgets('tap calls resetSession, shows toast, fires haptic',
        (tester) async {
      final coordinator = _SpySessionIdCoordinator();
      final toaster = _SpyToaster();
      final haptic = _SpyHapticService();

      await tester.pumpWidget(
        ProviderScope(
          overrides: _baseOverrides(
            coordinator: coordinator,
            toaster: toaster,
            hapticService: haptic,
          ),
          child: const App(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('new-conversation-button')));
      await tester.pumpAndSettle();

      expect(coordinator.resetCount, 1);
      expect(toaster.messages, ['New conversation']);
      expect(haptic.lightImpactCount, 1);
    });

    testWidgets('tap does nothing when button is disabled (capturing)',
        (tester) async {
      final coordinator = _SpySessionIdCoordinator();
      final toaster = _SpyToaster();
      final haptic = _SpyHapticService();
      final engine = _FakeHfEngine();
      late ProviderContainer container;

      await tester.pumpWidget(
        ProviderScope(
          overrides: _baseOverrides(
            engine: engine,
            coordinator: coordinator,
            toaster: toaster,
            hapticService: haptic,
          ),
          child: Builder(builder: (context) {
            container = ProviderScope.containerOf(context);
            return const App();
          }),
        ),
      );
      await tester.pumpAndSettle();

      await container
          .read(handsFreeControllerProvider.notifier)
          .startSession();
      await tester.pumpAndSettle();

      engine.emit(const EngineCapturing());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('new-conversation-button')));
      await tester.pumpAndSettle();

      expect(coordinator.resetCount, 0);
      expect(toaster.messages, isEmpty);
      expect(haptic.lightImpactCount, 0);
    });
  });
}
