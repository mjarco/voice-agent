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
import 'package:voice_agent/core/media_button/media_button_port.dart';
import 'package:voice_agent/core/media_button/media_button_provider.dart';
import 'package:voice_agent/core/session_control/mic_mode.dart';
import 'package:voice_agent/features/recording/presentation/recording_controller.dart';
import 'package:voice_agent/features/recording/presentation/recording_providers.dart';
import 'package:voice_agent/core/background/background_service_provider.dart';

import '../../../helpers/stub_background_service.dart';
import '../../../helpers/stub_media_button.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;

import '../../../helpers/stub_notifications.dart';
import '../../../helpers/stub_session_control.dart';

// ── Stubs ────────────────────────────────────────────────────────────────────

class _StubStorage with TelemetryStorageNoop implements StorageService {
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

/// A fresh single-subscription stream per start, like the orchestrator.
/// Its `onCancel` is an async closure of the test zone: a cancel without
/// one returns a future of the root zone, which the fake-async zone of a
/// widget test never completes, and the controller's pause would hang.
class _IdleHfEngine implements HandsFreeEngine {
  StreamController<HandsFreeEngineEvent>? _ctrl;

  @override
  Future<void> setCaptureGate({required bool open}) async {}

  @override
  Future<bool> hasPermission() async => true;

  @override
  Stream<HandsFreeEngineEvent> start({required VadConfig config}) {
    final ctrl = StreamController<HandsFreeEngineEvent>(onCancel: () async {});
    _ctrl = ctrl;
    Future.microtask(() {
      if (!ctrl.isClosed) ctrl.add(const EngineListening());
    });
    return ctrl.stream;
  }

  @override
  Future<void> stop() async {
    final ctrl = _ctrl;
    _ctrl = null;
    if (ctrl != null && !ctrl.isClosed) unawaited(ctrl.close());
  }

  @override
  Future<void> interruptCapture() => stop();

  @override
  void dispose() {}
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
  @override Future<void> pause() async {}
  @override Future<void> resume() async {}
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

class _StubAudioFeedbackService implements AudioFeedbackService {
  @override Future<void> startProcessingFeedback() async {}
  @override Future<void> stopLoop() async {}
  @override Future<void> playSuccess() async {}
  @override Future<void> playError() async {}
  @override void dispose() {}
}

// ── Helpers ───────────────────────────────────────────────────────────────────

// Android three-mode Record screen (ADR-AUDIO-013): the label per mode, the
// Stop button, the tap and the headset toggle.

Future<(ProviderContainer, StubMediaButtonPort)> _pumpApp(
    WidgetTester tester, {bool micModes = true}) async {
  final mediaButton = StubMediaButtonPort();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        micModesEnabledProvider.overrideWithValue(micModes),
        storageServiceProvider.overrideWithValue(_StubStorage()),
        connectivityServiceProvider.overrideWith((_) => _NoOpConnectivity()),
        apiUrlConfiguredProvider.overrideWithValue(true),
        appConfigServiceProvider.overrideWithValue(
          _FixedConfigService(const AppConfig(
              groqApiKey: 'gsk_test_key',
              apiUrl: 'https://test.example.com/api')),
        ),
        handsFreeEngineProvider.overrideWithValue(_IdleHfEngine()),
        recordingServiceProvider.overrideWithValue(_NoOpRecordingService()),
        sttServiceProvider.overrideWithValue(_NoOpSttService()),
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
        ...notificationStubOverrides(),
        ...sessionControlTestOverrides,
      ],
      child: const App(),
    ),
  );
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(
      tester.element(find.byKey(const Key('record-button'))));
  return (container, mediaButton);
}

Color? _buttonColor(WidgetTester tester) {
  final c = tester.widget<AnimatedContainer>(
    find.byKey(const Key('record-button')),
  );
  return (c.decoration as BoxDecoration).color;
}

Future<void> _tapMic(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('record-button')));
  await tester.pumpAndSettle();
}

final _stop = find.byKey(const Key('hf-stop-button'));

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tz_data.initializeTimeZones();

  group('Record screen in the three modes', () {
    testWidgets('Off: start label, green, no Stop', (tester) async {
      final (c, _) = await _pumpApp(tester);

      expect(c.read(micModeProvider), MicMode.off);
      expect(find.text('Tap to start listening'), findsOneWidget);
      expect(_buttonColor(tester), Colors.green);
      expect(_stop, findsNothing);
    });

    testWidgets('a tap in Off starts Listening, with Stop shown',
        (tester) async {
      final (c, _) = await _pumpApp(tester);
      await _tapMic(tester);

      expect(c.read(micModeProvider), MicMode.listening);
      expect(find.text('Listening — tap to pause'), findsOneWidget);
      expect(_buttonColor(tester), Colors.orange);
      expect(_stop, findsOneWidget);
    });

    testWidgets('a tap in Listening pauses: Standby, Stop still shown',
        (tester) async {
      final (c, _) = await _pumpApp(tester);
      await _tapMic(tester);
      await _tapMic(tester);

      expect(c.read(micModeProvider), MicMode.standby);
      expect(find.text('Standby — tap to resume'), findsOneWidget);
      expect(_buttonColor(tester), Colors.blueGrey);
      expect(_stop, findsOneWidget);
    });

    testWidgets('a tap in Standby resumes Listening', (tester) async {
      final (c, _) = await _pumpApp(tester);
      await _tapMic(tester);
      await _tapMic(tester);
      await _tapMic(tester);

      expect(c.read(micModeProvider), MicMode.listening);
      expect(find.text('Listening — tap to pause'), findsOneWidget);
    });

    testWidgets('Stop from Listening ends in Off and hides Stop',
        (tester) async {
      final (c, _) = await _pumpApp(tester);
      await _tapMic(tester);

      await tester.tap(_stop);
      await tester.pumpAndSettle();

      expect(c.read(micModeProvider), MicMode.off);
      expect(find.text('Tap to start listening'), findsOneWidget);
      expect(_stop, findsNothing);
    });

    testWidgets('Stop from Standby ends in Off', (tester) async {
      final (c, _) = await _pumpApp(tester);
      await _tapMic(tester);
      await _tapMic(tester);

      await tester.tap(_stop);
      await tester.pumpAndSettle();

      expect(c.read(micModeProvider), MicMode.off);
      expect(_stop, findsNothing);
    });
  });

  group('the headset button', () {
    testWidgets('toggles Listening ↔ Standby', (tester) async {
      final (c, button) = await _pumpApp(tester);
      await _tapMic(tester);

      button.emit(MediaButtonEvent.togglePlayPause);
      await tester.pumpAndSettle();
      expect(c.read(micModeProvider), MicMode.standby);

      button.emit(MediaButtonEvent.togglePlayPause);
      await tester.pumpAndSettle();
      expect(c.read(micModeProvider), MicMode.listening);
    });

    testWidgets('does not start a session from Off', (tester) async {
      final (c, button) = await _pumpApp(tester);

      button.emit(MediaButtonEvent.togglePlayPause);
      await tester.pumpAndSettle();

      expect(c.read(micModeProvider), MicMode.off);
    });

    // ADR-AUDIO-015: the controller owns the media session on Android.
    testWidgets('opening the app claims nothing; Listening does, Stop releases',
        (tester) async {
      final (_, button) = await _pumpApp(tester);
      expect(button.calls, isEmpty);

      await _tapMic(tester);
      expect(button.calls, ['claim']);

      await tester.tap(_stop);
      await tester.pumpAndSettle();
      expect(button.calls, ['claim', 'deactivate']);
    });

    testWidgets('without the modes (iOS) the screen activates the session',
        (tester) async {
      final (_, button) = await _pumpApp(tester, micModes: false);
      expect(button.calls, ['activate']);
    });
  });

  group('push-to-talk', () {
    testWidgets('a long press in Listening records in Standby, then returns',
        (tester) async {
      final (c, _) = await _pumpApp(tester);
      await _tapMic(tester);

      final gesture = await tester.startGesture(
          tester.getCenter(find.byKey(const Key('record-button'))));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(c.read(micModeProvider), MicMode.standby);
      expect(c.read(recordingControllerProvider), isA<RecordingActive>());

      await gesture.up();
      await tester.pumpAndSettle();

      expect(c.read(micModeProvider), MicMode.listening);
    });
  });
}
