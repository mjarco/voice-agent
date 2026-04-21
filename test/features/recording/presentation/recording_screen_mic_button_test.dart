import 'package:flutter/foundation.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/app/app.dart';
import 'package:voice_agent/core/config/app_config.dart';
import 'package:voice_agent/core/config/app_config_provider.dart';
import 'package:voice_agent/core/config/app_config_service.dart';
import 'package:voice_agent/core/config/vad_config.dart';
import 'package:voice_agent/core/models/sync_queue_item.dart';
import 'package:voice_agent/core/models/transcript.dart';
import 'package:voice_agent/core/models/transcript_result.dart';
import 'package:voice_agent/core/models/transcript_with_status.dart';
import 'package:voice_agent/core/network/connectivity_service.dart';
import 'package:voice_agent/core/providers/agent_reply_provider.dart';
import 'package:voice_agent/core/providers/api_url_provider.dart';
import 'package:voice_agent/core/storage/storage_provider.dart';
import 'package:voice_agent/features/api_sync/sync_provider.dart';
import 'package:voice_agent/core/storage/storage_service.dart';
import 'package:voice_agent/features/recording/domain/hands_free_engine.dart';
import 'package:voice_agent/features/recording/domain/recording_result.dart';
import 'package:voice_agent/features/recording/domain/recording_service.dart';
import 'package:voice_agent/features/recording/domain/recording_state.dart';
import 'package:voice_agent/features/recording/domain/stt_service.dart';
import 'package:voice_agent/core/audio/audio_feedback_provider.dart';
import 'package:voice_agent/core/audio/audio_feedback_service.dart';
import 'package:voice_agent/core/tts/tts_provider.dart';
import 'package:voice_agent/core/tts/tts_service.dart';
import 'package:voice_agent/features/recording/presentation/recording_controller.dart';
import 'package:voice_agent/features/recording/presentation/recording_providers.dart';
import 'package:voice_agent/core/background/background_service_provider.dart';

import '../../../helpers/stub_background_service.dart';

// ── Stubs ────────────────────────────────────────────────────────────────────

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

class _IdleHfEngine implements HandsFreeEngine {
  final _ctrl = StreamController<HandsFreeEngineEvent>.broadcast();
  @override Future<bool> hasPermission() async => true;
  @override Stream<HandsFreeEngineEvent> start({required VadConfig config}) => _ctrl.stream;
  @override Future<void> stop() async {}
  @override Future<void> interruptCapture() async {}
  @override void dispose() => _ctrl.close();
}

class _FixedConfigService extends AppConfigService {
  _FixedConfigService(this._config);
  final AppConfig _config;
  @override
  Future<AppConfig> load() async => _config;
}

class _NoOpRecordingService implements RecordingService {
  @override Future<bool> requestPermission() async => true;
  @override Future<void> start({required String outputPath}) async {}
  @override Future<RecordingResult> stop() async =>
      RecordingResult(filePath: '/tmp/x.wav', duration: Duration.zero, sampleRate: 16000);
  @override Future<void> cancel() async {}
  @override Stream<Duration> get elapsed => const Stream.empty();
  @override bool get isRecording => false;
}

class _NoOpSttService implements SttService {
  @override Future<bool> isModelLoaded() async => true;
  @override Future<void> loadModel() async {}
  @override Future<TranscriptResult> transcribe(String path, {String? languageCode}) async =>
      const TranscriptResult(text: '', segments: [], detectedLanguage: 'en', audioDurationMs: 0);
}

/// [RecordingController] that bypasses path_provider and async I/O.
/// [startRecording] immediately sets state to [RecordingActive].
/// [stopAndTranscribe] immediately sets state to [RecordingIdle].
class _FakeRecordingController extends RecordingController {
  _FakeRecordingController(super.svc, super.stt, super.ref);

  @override
  Future<void> startRecording() async {
    state = const RecordingState.recording();
  }

  @override
  Future<void> stopAndTranscribe({bool silentOnEmpty = false}) async {
    state = const RecordingState.idle();
  }
}

// ── Stubs ────────────────────────────────────────────────────────────────────

class _StubTtsService implements TtsService {
  @override ValueListenable<bool> get isSpeaking => ValueNotifier(false);
  @override Future<void> speak(String text, {String? languageCode}) async {}
  @override Future<void> stop() async {}
  @override void dispose() {}
}

class _SpyTtsService implements TtsService {
  @override ValueListenable<bool> get isSpeaking => ValueNotifier(false);
  int stopCount = 0;
  @override Future<void> speak(String text, {String? languageCode}) async {}
  @override Future<void> stop() async { stopCount++; }
  @override void dispose() {}
}

class _StubAudioFeedbackService implements AudioFeedbackService {
  @override Future<void> startProcessingFeedback() async {}
  @override Future<void> stopLoop() async {}
  @override Future<void> playSuccess() async {}
  @override Future<void> playError() async {}
  @override Future<void> playWakeWordAcknowledgment() async {}
  @override void dispose() {}
}

// ── Helpers ───────────────────────────────────────────────────────────────────

List<Override> get _baseOverrides => [
  storageServiceProvider.overrideWithValue(_StubStorage()),
  connectivityServiceProvider.overrideWith((_) => _NoOpConnectivity()),
  apiUrlConfiguredProvider.overrideWithValue(true),
  appConfigServiceProvider.overrideWithValue(
    _FixedConfigService(const AppConfig(groqApiKey: 'gsk_test_key')),
  ),
  handsFreeEngineProvider.overrideWithValue(_IdleHfEngine()),
  recordingServiceProvider.overrideWithValue(_NoOpRecordingService()),
  sttServiceProvider.overrideWithValue(_NoOpSttService()),
  recordingControllerProvider.overrideWith((ref) => _FakeRecordingController(
    ref.read(recordingServiceProvider),
    ref.read(sttServiceProvider),
    ref,
  )),
  ttsServiceProvider.overrideWithValue(_StubTtsService()),
  audioFeedbackServiceProvider.overrideWithValue(_StubAudioFeedbackService()),
  backgroundServiceProvider.overrideWithValue(StubBackgroundService()),
];

Future<void> pumpApp(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: _baseOverrides,
      child: const App(),
    ),
  );
  await tester.pumpAndSettle();
}

Future<_SpyTtsService> _pumpAppWithSpyTts(WidgetTester tester) async {
  final spy = _SpyTtsService();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        storageServiceProvider.overrideWithValue(_StubStorage()),
        connectivityServiceProvider.overrideWith((_) => _NoOpConnectivity()),
        apiUrlConfiguredProvider.overrideWithValue(true),
        appConfigServiceProvider.overrideWithValue(
          _FixedConfigService(const AppConfig(groqApiKey: 'gsk_test_key')),
        ),
        handsFreeEngineProvider.overrideWithValue(_IdleHfEngine()),
        recordingServiceProvider.overrideWithValue(_NoOpRecordingService()),
        sttServiceProvider.overrideWithValue(_NoOpSttService()),
        recordingControllerProvider.overrideWith((ref) => _FakeRecordingController(
          ref.read(recordingServiceProvider),
          ref.read(sttServiceProvider),
          ref,
        )),
        ttsServiceProvider.overrideWithValue(spy),
        audioFeedbackServiceProvider.overrideWithValue(_StubAudioFeedbackService()),
        backgroundServiceProvider.overrideWithValue(StubBackgroundService()),
      ],
      child: const App(),
    ),
  );
  await tester.pumpAndSettle();
  return spy;
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() => WidgetsFlutterBinding.ensureInitialized());

  group('tap-to-record', () {
    testWidgets('idle → tap → button turns red', (tester) async {
      await pumpApp(tester);

      await tester.tap(find.byKey(const Key('record-button')));
      await tester.pumpAndSettle();

      final container = tester.widget<AnimatedContainer>(
        find.byKey(const Key('record-button')),
      );
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.color, equals(Colors.red));
    });

    testWidgets('idle → tap → shows "Tap to stop" label', (tester) async {
      await pumpApp(tester);

      await tester.tap(find.byKey(const Key('record-button')));
      await tester.pumpAndSettle();

      expect(find.text('Tap to stop'), findsOneWidget);
      expect(find.text('Tap to record'), findsNothing);
    });
  });

  group('press-and-hold', () {
    testWidgets('long press start → label changes to "Release to stop"', (tester) async {
      await pumpApp(tester);

      // Hold the gesture without releasing so the button stays in press-and-hold state.
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('record-button'))),
      );
      // Wait past Flutter's long-press threshold (500ms default).
      await tester.pump(const Duration(milliseconds: 600));
      // Give async work (startRecording) time to complete.
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      expect(find.text('Release to stop'), findsOneWidget);

      // Clean up: release gesture.
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('long press start → button turns orange', (tester) async {
      await pumpApp(tester);

      // Hold the gesture without releasing so the button stays in press-and-hold state.
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('record-button'))),
      );
      // Wait past Flutter's long-press threshold (500ms default).
      await tester.pump(const Duration(milliseconds: 600));
      // Give async work (startRecording) time to complete.
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      final container = tester.widget<AnimatedContainer>(
        find.byKey(const Key('record-button')),
      );
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.color, equals(Colors.orange));

      // Clean up: release gesture.
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('empty transcription after long press → no error shown', (tester) async {
      await pumpApp(tester);

      // Start long press (onLongPressStart → RecordingActive)
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('record-button'))),
      );
      await tester.pump(const Duration(milliseconds: 600)); // pass Flutter's long-press threshold

      // Release (onLongPressEnd → stopAndTranscribe(silentOnEmpty: true))
      await gesture.up();
      await tester.pumpAndSettle();

      // silentOnEmpty → RecordingIdle, no error
      expect(find.byIcon(Icons.error), findsNothing);
      expect(find.text('Tap to record'), findsOneWidget);
    });
  });

  group('Agent reply clearing', () {
    testWidgets('tap clears latestAgentReplyProvider', (tester) async {
      late ProviderContainer container;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ..._baseOverrides,
            latestAgentReplyProvider.overrideWith((_) => 'old reply'),
          ],
          child: Builder(builder: (context) {
            container = ProviderScope.containerOf(context);
            return const App();
          }),
        ),
      );
      await tester.pumpAndSettle();

      // Verify reply card is visible
      expect(find.byKey(const Key('agent-reply-card')), findsOneWidget);

      await tester.tap(find.byKey(const Key('record-button')));
      await tester.pumpAndSettle();

      expect(container.read(latestAgentReplyProvider), isNull);
    });

    testWidgets('long-press clears latestAgentReplyProvider', (tester) async {
      late ProviderContainer container;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ..._baseOverrides,
            latestAgentReplyProvider.overrideWith((_) => 'old reply'),
          ],
          child: Builder(builder: (context) {
            container = ProviderScope.containerOf(context);
            return const App();
          }),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('agent-reply-card')), findsOneWidget);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('record-button'))),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      expect(container.read(latestAgentReplyProvider), isNull);

      await gesture.up();
      await tester.pumpAndSettle();
    });
  });

  group('TTS interruption', () {
    testWidgets('tap → TtsService.stop() called before startRecording', (tester) async {
      final spy = await _pumpAppWithSpyTts(tester);

      await tester.tap(find.byKey(const Key('record-button')));
      await tester.pumpAndSettle();

      expect(spy.stopCount, greaterThanOrEqualTo(1));
    });

    testWidgets('long press start → TtsService.stop() called before startRecording', (tester) async {
      final spy = await _pumpAppWithSpyTts(tester);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('record-button'))),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      expect(spy.stopCount, greaterThanOrEqualTo(1));

      await gesture.up();
      await tester.pumpAndSettle();
    });
  });
}
