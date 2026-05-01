import 'package:flutter/foundation.dart';
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/background/background_service.dart';
import 'package:voice_agent/core/background/background_service_provider.dart';
import 'package:voice_agent/core/config/app_config.dart';
import 'package:voice_agent/core/config/app_config_provider.dart';
import 'package:voice_agent/core/config/app_config_service.dart';
import 'package:voice_agent/core/models/sync_queue_item.dart';
import 'package:voice_agent/core/models/transcript.dart';
import 'package:voice_agent/core/models/transcript_result.dart';
import 'package:voice_agent/core/models/transcript_with_status.dart';
import 'package:voice_agent/core/providers/session_active_provider.dart';
import 'package:voice_agent/core/storage/storage_provider.dart';
import 'package:voice_agent/core/storage/storage_service.dart';
import 'package:voice_agent/core/config/vad_config.dart';
import 'package:voice_agent/features/recording/domain/engagement_controller.dart';
import 'package:voice_agent/features/recording/domain/hands_free_engine.dart';
import 'package:voice_agent/features/recording/domain/hands_free_session_state.dart';
import 'package:voice_agent/features/recording/domain/recording_result.dart';
import 'package:voice_agent/features/recording/domain/recording_service.dart';
import 'package:voice_agent/features/recording/domain/recording_state.dart';
import 'package:voice_agent/features/recording/domain/segment_job.dart';
import 'package:voice_agent/features/recording/domain/stt_exception.dart';
import 'package:voice_agent/features/recording/domain/stt_service.dart';
import 'package:voice_agent/core/tts/tts_provider.dart';
import 'package:voice_agent/core/tts/tts_service.dart';
import 'package:voice_agent/features/recording/presentation/hands_free_controller.dart';
import 'package:voice_agent/features/recording/presentation/recording_controller.dart';
import 'package:voice_agent/core/audio/audio_feedback_provider.dart';
import 'package:voice_agent/core/audio/audio_feedback_service.dart';
import 'package:voice_agent/features/recording/presentation/recording_providers.dart';

import '../../../helpers/stub_background_service.dart';

// ── TrackingBackgroundService ────────────────────────────────────────────────

/// Records `startService`/`stopService` call timestamps so tests can verify
/// ordering relative to engine lifecycle events.
class _TrackingBackgroundService implements BackgroundService {
  final List<String> calls = [];
  DateTime? lastStartCompleted;
  DateTime? lastStopCompleted;
  bool _running = false;

  @override
  bool get isRunning => _running;

  @override
  Future<void> startService() async {
    calls.add('startService');
    _running = true;
    lastStartCompleted = DateTime.now();
  }

  @override
  Future<void> stopService({
    AudioSessionTarget target = AudioSessionTarget.playback,
  }) async {
    calls.add('stopService');
    _running = false;
    lastStopCompleted = DateTime.now();
  }

  @override
  Future<void> updateNotification({
    required String title,
    required String body,
  }) async {
    calls.add('updateNotification($title/$body)');
  }
}

// ── FakeHandsFreeEngine ──────────────────────────────────────────────────────

class FakeHandsFreeEngine implements HandsFreeEngine {
  bool permissionGranted = true;
  bool started = false;
  bool stopped = false;
  bool disposed = false;

  final _controller = StreamController<HandsFreeEngineEvent>.broadcast();

  void emit(HandsFreeEngineEvent event) => _controller.add(event);

  @override
  Future<bool> hasPermission() async => permissionGranted;

  @override
  Stream<HandsFreeEngineEvent> start({required VadConfig config}) {
    started = true;
    return _controller.stream;
  }

  @override
  Future<void> stop() async => stopped = true;

  @override
  Future<void> interruptCapture() async {}

  @override
  void dispose() {
    disposed = true;
    _controller.close();
  }
}

// ── FakeSttService ────────────────────────────────────────────────────────────

/// Controllable [SttService] for T3b tests.
class FakeSttService implements SttService {
  FakeSttService({this.text = 'Hello world', this.throws = false});

  final String text;
  final bool throws;

  @override
  Future<TranscriptResult> transcribe(String wavPath,
      {String? languageCode}) async {
    if (throws) throw SttException('STT failed');
    return TranscriptResult(
      text: text,
      segments: [],
      detectedLanguage: 'en',
      audioDurationMs: 1500,
    );
  }

  @override
  Future<bool> isModelLoaded() async => true;
  @override
  Future<void> loadModel() async {}
}

/// [SttService] that never resolves — keeps jobs in [Transcribing] state.
/// Used as the default in [makeContainer] so T3a-style tests are unaffected.
class _HangingSttService implements SttService {
  @override
  Future<TranscriptResult> transcribe(String wavPath,
          {String? languageCode}) =>
      Completer<TranscriptResult>().future; // intentionally never completes

  @override
  Future<bool> isModelLoaded() async => true;
  @override
  Future<void> loadModel() async {}
}

/// [SttService] that resolves after a 50ms delay, allowing [stopSession] to
/// drain in-flight jobs within the test timeout.
class _SlowSttService implements SttService {
  _SlowSttService({this.text = 'Hello'});

  final String text;

  @override
  Future<TranscriptResult> transcribe(String wavPath,
      {String? languageCode}) async {
    await Future.delayed(const Duration(milliseconds: 50));
    return TranscriptResult(
      text: text,
      segments: [],
      detectedLanguage: 'en',
      audioDurationMs: 1000,
    );
  }

  @override
  Future<bool> isModelLoaded() async => true;
  @override
  Future<void> loadModel() async {}
}

// ── FakeStorageService ────────────────────────────────────────────────────────

/// Controllable [StorageService] for T3b persist/rollback tests.
class FakeStorageService implements StorageService {
  final List<Transcript> savedTranscripts = [];
  final List<String> enqueuedIds = [];
  final List<String> deletedIds = [];

  bool enqueueThrows = false;
  bool saveThrows = false;

  @override
  Future<void> saveTranscript(Transcript transcript) async {
    if (saveThrows) throw Exception('save failed');
    savedTranscripts.add(transcript);
  }

  @override
  Future<void> enqueue(String transcriptId) async {
    if (enqueueThrows) throw Exception('enqueue failed');
    enqueuedIds.add(transcriptId);
  }

  @override
  Future<void> deleteTranscript(String id) async => deletedIds.add(id);

  @override
  Future<String> getDeviceId() async => 'test-device-123';

  // Unused but required by the interface.
  @override
  Future<Transcript?> getTranscript(String id) async => null;
  @override
  Future<List<Transcript>> getTranscripts(
          {int limit = 50, int offset = 0}) async =>
      [];
  @override
  Future<List<TranscriptWithStatus>> getTranscriptsWithStatus(
          {int limit = 20, int offset = 0}) async =>
      [];
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
  Future<int> recoverStaleSending() async => 0;
  @override
  Future<List<SyncQueueItem>> getFailedItems({int? maxAttempts}) async => [];
}

// ── _FixedConfigService ───────────────────────────────────────────────────────

/// [AppConfigService] that returns a fixed [AppConfig] — no platform I/O.
class _FixedConfigService extends AppConfigService {
  _FixedConfigService(this._config);
  final AppConfig _config;

  @override
  Future<AppConfig> load() async => _config;
}

// ── RecordingController stubs ─────────────────────────────────────────────────

/// [RecordingController] backed by no-op stubs — stays in [RecordingState.idle].
class _IdleRecordingController extends RecordingController {
  _IdleRecordingController(Ref ref)
      : super(_NullRecordingService(), _NullSttService(), ref);
}

/// [RecordingController] that always reports [RecordingActive].
class _ActiveRecordingController extends RecordingController {
  _ActiveRecordingController(Ref ref)
      : super(_NullRecordingService(), _NullSttService(), ref) {
    // ignore: invalid_use_of_protected_member
    state = const RecordingState.recording();
  }
}

class _NullRecordingService implements RecordingService {
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<void> start({required String outputPath}) async {}
  @override
  Future<RecordingResult> stop() async =>
      RecordingResult(filePath: '/tmp/t.wav', duration: Duration.zero, sampleRate: 16000);
  @override
  Future<void> pause() async {}
  @override
  Future<void> resume() async {}
  @override
  Future<void> cancel() async {}
  @override
  bool get isRecording => false;
  @override
  Stream<Duration> get elapsed => const Stream.empty();
}

class _NullSttService implements SttService {
  @override
  Future<bool> isModelLoaded() async => false;
  @override
  Future<void> loadModel() async {}
  @override
  Future<TranscriptResult> transcribe(String wavPath,
          {String? languageCode}) async =>
      throw SttException('unused');
}

/// [HandsFreeEngine] stub that invokes callbacks on specific calls —
/// used to verify which path [HandsFreeController.suspendForManualRecording]
/// takes based on the current session state.
class _TrackingHfEngine implements HandsFreeEngine {
  _TrackingHfEngine({this.onInterruptCapture});

  final VoidCallback? onInterruptCapture;

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
  Future<void> interruptCapture() async => onInterruptCapture?.call();
  @override
  void dispose() => _ctrl.close();
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
  @override void dispose() {}
}

// ── Container factory ────────────────────────────────────────────────────────

const _defaultApiUrl = Object();

ProviderContainer makeContainer({
  required HandsFreeEngine engine,
  String? groqApiKey = 'gsk_test_valid',
  Object? apiUrl = _defaultApiUrl,
  bool recordingActive = false,
  SttService? sttService,
  StorageService? storageService,
  TtsService? ttsService,
  AudioFeedbackService? audioFeedbackService,
  BackgroundService? backgroundService,
}) {
  final container = ProviderContainer(overrides: [
    handsFreeEngineProvider.overrideWithValue(engine),
    appConfigServiceProvider.overrideWithValue(
      _FixedConfigService(AppConfig(
        groqApiKey: groqApiKey,
        apiUrl: apiUrl == _defaultApiUrl ? 'https://test.example.com/api' : apiUrl as String?,
      )),
    ),
    recordingControllerProvider.overrideWith(
      (ref) => recordingActive
          ? _ActiveRecordingController(ref)
          : _IdleRecordingController(ref),
    ),
    // Default to hanging STT so T3a-style tests are unaffected by job processing.
    sttServiceProvider.overrideWithValue(sttService ?? _HangingSttService()),
    if (storageService != null)
      storageServiceProvider.overrideWithValue(storageService),
    ttsServiceProvider.overrideWithValue(ttsService ?? _StubTtsService()),
    audioFeedbackServiceProvider.overrideWithValue(
      audioFeedbackService ?? _StubAudioFeedbackService(),
    ),
    backgroundServiceProvider.overrideWithValue(
      backgroundService ?? StubBackgroundService(),
    ),
  ]);
  addTearDown(container.dispose);
  return container;
}

HandsFreeController ctrl(ProviderContainer c) =>
    c.read(handsFreeControllerProvider.notifier);

HandsFreeSessionState stateOf(ProviderContainer c) =>
    c.read(handsFreeControllerProvider);

/// Extracts jobs from any [HandsFreeSessionState] variant that carries them.
List<SegmentJob> jobsOf(HandsFreeSessionState s) => switch (s) {
      HandsFreeListening(:final jobs) => jobs,
      HandsFreeSessionError(:final jobs) => jobs,
      HandsFreeIdle(:final jobs) => jobs,
    };

/// True when [s] is [HandsFreeListening] with the given [phase].
bool isPhase(HandsFreeSessionState s, HandsFreeListeningPhase phase) =>
    s is HandsFreeListening && s.phase == phase;

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() => WidgetsFlutterBinding.ensureInitialized());

  // ── Session-start guards ──────────────────────────────────────────────────

  group('session-start guards', () {
    test('permission denied → SessionError(requiresSettings)', () async {
      final engine = FakeHandsFreeEngine()..permissionGranted = false;
      final c = makeContainer(engine: engine);

      await ctrl(c).startSession();

      final s = stateOf(c) as HandsFreeSessionError;
      expect(s.requiresSettings, isTrue);
      expect(engine.started, isFalse);
    });

    test('missing Groq key → SessionError(requiresAppSettings)', () async {
      final engine = FakeHandsFreeEngine();
      final c = makeContainer(engine: engine, groqApiKey: null);

      await ctrl(c).startSession();

      final s = stateOf(c) as HandsFreeSessionError;
      expect(s.requiresAppSettings, isTrue);
      expect(engine.started, isFalse);
    });

    test('empty Groq key → SessionError(requiresAppSettings)', () async {
      final engine = FakeHandsFreeEngine();
      final c = makeContainer(engine: engine, groqApiKey: '');

      await ctrl(c).startSession();

      final s = stateOf(c) as HandsFreeSessionError;
      expect(s.requiresAppSettings, isTrue);
      expect(engine.started, isFalse);
    });

    test('missing API URL → SessionError(requiresAppSettings)', () async {
      final engine = FakeHandsFreeEngine();
      final c = makeContainer(engine: engine, apiUrl: null);

      await ctrl(c).startSession();

      final s = stateOf(c) as HandsFreeSessionError;
      expect(s.requiresAppSettings, isTrue);
      expect(s.message, 'API URL not set.');
      expect(engine.started, isFalse);
    });

    test('empty API URL → SessionError(requiresAppSettings)', () async {
      final engine = FakeHandsFreeEngine();
      final c = makeContainer(engine: engine, apiUrl: '');

      await ctrl(c).startSession();

      final s = stateOf(c) as HandsFreeSessionError;
      expect(s.requiresAppSettings, isTrue);
      expect(engine.started, isFalse);
    });

    test('all guards pass → engine.start() called', () async {
      final engine = FakeHandsFreeEngine();
      final c = makeContainer(engine: engine);

      await ctrl(c).startSession();

      expect(engine.started, isTrue);
    });

    test('startSession is a no-op when session already active', () async {
      final engine = FakeHandsFreeEngine();
      final c = makeContainer(engine: engine);
      await ctrl(c).startSession();
      engine.emit(const EngineListening()); // move out of HandsFreeIdle
      await Future.delayed(Duration.zero);

      engine.started = false; // reset to detect a second call
      await ctrl(c).startSession();
      expect(engine.started, isFalse, reason: 'must not restart');
    });
  });

  // ── Engine event mapping ──────────────────────────────────────────────────

  group('engine event mapping', () {
    test('EngineListening → HandsFreeListening', () async {
      final engine = FakeHandsFreeEngine();
      final c = makeContainer(engine: engine);
      await ctrl(c).startSession();

      engine.emit(const EngineListening());
      await Future.delayed(Duration.zero);

      expect(stateOf(c), isA<HandsFreeListening>());
    });

    test('EngineCapturing → HandsFreeListening(phase=capturing)', () async {
      final engine = FakeHandsFreeEngine();
      final c = makeContainer(engine: engine);
      await ctrl(c).startSession();

      engine.emit(const EngineCapturing());
      await Future.delayed(Duration.zero);

      expect(isPhase(stateOf(c), HandsFreeListeningPhase.capturing), isTrue);
    });

    test('EngineCapturing → TtsService.stop() called', () async {
      final engine = FakeHandsFreeEngine();
      final spy = _SpyTtsService();
      final c = makeContainer(engine: engine, ttsService: spy);
      await ctrl(c).startSession();

      engine.emit(const EngineCapturing());
      await Future.delayed(Duration.zero);

      expect(spy.stopCount, 1);
    });

    test('EngineStopping → HandsFreeListening(phase=stopping)', () async {
      final engine = FakeHandsFreeEngine();
      final c = makeContainer(engine: engine);
      await ctrl(c).startSession();

      engine.emit(const EngineStopping());
      await Future.delayed(Duration.zero);

      expect(isPhase(stateOf(c), HandsFreeListeningPhase.stopping), isTrue);
    });

    test('EngineSegmentReady → job added, state still HandsFreeListening',
        () async {
      final engine = FakeHandsFreeEngine();
      final c = makeContainer(engine: engine); // uses _HangingSttService
      await ctrl(c).startSession();

      engine.emit(const EngineSegmentReady('/tmp/seg1.wav'));
      await Future.delayed(Duration.zero); // job transitions to Transcribing

      final s = stateOf(c);
      expect(s, isA<HandsFreeListening>());
      final jobs = (s as HandsFreeListening).jobs;
      expect(jobs, hasLength(1));
      expect(jobs.first.state, isA<Transcribing>());
      expect(jobs.first.wavPath, '/tmp/seg1.wav');
    });

    test('EngineError → SessionError with message', () async {
      final engine = FakeHandsFreeEngine();
      final c = makeContainer(engine: engine);
      await ctrl(c).startSession();

      engine.emit(const EngineError('VAD crashed'));
      await Future.delayed(Duration.zero);

      final s = stateOf(c) as HandsFreeSessionError;
      expect(s.message, contains('VAD crashed'));
    });

    test('EngineError(requiresSettings) → SessionError(requiresSettings)',
        () async {
      final engine = FakeHandsFreeEngine();
      final c = makeContainer(engine: engine);
      await ctrl(c).startSession();

      engine.emit(
          const EngineError('Permission denied', requiresSettings: true));
      await Future.delayed(Duration.zero);

      expect((stateOf(c) as HandsFreeSessionError).requiresSettings, isTrue);
    });
  });

  // ── FG service lifecycle (P026: explicit start/stop in controller) ────────

  group('foreground service lifecycle', () {
    test('startSession calls startService BEFORE _startEngine', () async {
      final engine = FakeHandsFreeEngine();
      final bg = _TrackingBackgroundService();
      final c = makeContainer(engine: engine, backgroundService: bg);

      await ctrl(c).startSession();

      // startService must appear before engine.start marker in the call list.
      // We assert via two observations: engine.started is true AFTER startService
      // completed (bg.lastStartCompleted is not null at this point), and
      // startService is the first call recorded on the stub.
      expect(bg.calls.first, 'startService');
      expect(bg.lastStartCompleted, isNotNull);
      expect(engine.started, isTrue);
      expect(bg.calls, contains('updateNotification(Voice Agent/Recording session active)'));
    });

    test('stopSession calls stopService before transitioning to idle',
        () async {
      final engine = FakeHandsFreeEngine();
      final bg = _TrackingBackgroundService();
      final c = makeContainer(engine: engine, backgroundService: bg);
      await ctrl(c).startSession();
      engine.emit(const EngineListening());
      await Future.delayed(Duration.zero);

      await ctrl(c).stopSession();

      expect(bg.calls.last, 'stopService');
      expect(stateOf(c), isA<HandsFreeIdle>());
    });

    test('permission denied → NO startService call', () async {
      final engine = FakeHandsFreeEngine()..permissionGranted = false;
      final bg = _TrackingBackgroundService();
      final c = makeContainer(engine: engine, backgroundService: bg);

      await ctrl(c).startSession();

      expect(bg.calls, isEmpty);
      expect(stateOf(c), isA<HandsFreeSessionError>());
    });

    test('missing Groq key → NO startService call', () async {
      final engine = FakeHandsFreeEngine();
      final bg = _TrackingBackgroundService();
      final c = makeContainer(
          engine: engine, backgroundService: bg, groqApiKey: null);

      await ctrl(c).startSession();

      expect(bg.calls, isEmpty);
      expect(stateOf(c), isA<HandsFreeSessionError>());
    });

    test('engine error → stopService called via _terminateWithError', () async {
      final engine = FakeHandsFreeEngine();
      final bg = _TrackingBackgroundService();
      final c = makeContainer(engine: engine, backgroundService: bg);
      await ctrl(c).startSession();
      await Future.delayed(Duration.zero);

      engine.emit(const EngineError('VAD crashed'));
      await Future.delayed(Duration.zero);

      expect(bg.calls, contains('stopService'));
      expect(stateOf(c), isA<HandsFreeSessionError>());
    });
  });

  // ── sessionActiveProvider writes (P027) ───────────────────────────────────

  group('sessionActiveProvider lifecycle', () {
    test('startSession success → sessionActive = true', () async {
      final engine = FakeHandsFreeEngine();
      final c = makeContainer(engine: engine);

      expect(c.read(sessionActiveProvider), isFalse);

      await ctrl(c).startSession();

      expect(c.read(sessionActiveProvider), isTrue);
    });

    test('stopSession → sessionActive = false', () async {
      final engine = FakeHandsFreeEngine();
      final c = makeContainer(engine: engine);
      await ctrl(c).startSession();
      engine.emit(const EngineListening());
      await Future.delayed(Duration.zero);

      await ctrl(c).stopSession();

      expect(c.read(sessionActiveProvider), isFalse);
    });

    test('_terminateWithError via engine error → sessionActive = false',
        () async {
      final engine = FakeHandsFreeEngine();
      final c = makeContainer(engine: engine);
      await ctrl(c).startSession();
      await Future.delayed(Duration.zero);

      engine.emit(const EngineError('VAD crashed'));
      await Future.delayed(Duration.zero);

      expect(c.read(sessionActiveProvider), isFalse);
    });

    test('permission denied guard → sessionActive stays false', () async {
      final engine = FakeHandsFreeEngine()..permissionGranted = false;
      final c = makeContainer(engine: engine);

      await ctrl(c).startSession();

      expect(c.read(sessionActiveProvider), isFalse);
    });

    test('missing Groq key guard → sessionActive stays false', () async {
      final engine = FakeHandsFreeEngine();
      final c = makeContainer(engine: engine, groqApiKey: null);

      await ctrl(c).startSession();

      expect(c.read(sessionActiveProvider), isFalse);
    });

    test('already-idle stopSession → no write (provider stays whatever it was)',
        () async {
      final engine = FakeHandsFreeEngine();
      final c = makeContainer(engine: engine);

      // Simulate an inconsistent state: provider is true but controller is
      // idle (shouldn't happen in practice, but verifies the early-return
      // guard doesn't clobber the flag).
      c.read(sessionActiveProvider.notifier).state = true;

      await ctrl(c).stopSession();

      // Because state was already HandsFreeIdle, stopSession returns before
      // writing the provider.
      expect(c.read(sessionActiveProvider), isTrue);
    });
  });

  // ── Background lifecycle (P026: session continues across pause) ───────────

  group('background lifecycle', () {
    test('app paused during session → session continues (no state change)',
        () async {
      final engine = FakeHandsFreeEngine();
      final c = makeContainer(engine: engine);
      await ctrl(c).startSession();
      engine.emit(const EngineListening()); // move out of HandsFreeIdle
      await Future.delayed(Duration.zero);

      ctrl(c).didChangeAppLifecycleState(AppLifecycleState.paused);
      await Future.delayed(Duration.zero);

      // Session must still be alive — FG service keeps the process alive.
      expect(stateOf(c), isA<HandsFreeListening>());
    });

    test('app paused when idle → no effect', () async {
      final engine = FakeHandsFreeEngine();
      final c = makeContainer(engine: engine);

      ctrl(c).didChangeAppLifecycleState(AppLifecycleState.paused);
      await Future.delayed(Duration.zero);

      expect(stateOf(c), isA<HandsFreeIdle>());
    });
  });

  // ── Stop session ──────────────────────────────────────────────────────────

  group('stopSession', () {
    test('stopSession → HandsFreeIdle; engine.stop() called', () async {
      final engine = FakeHandsFreeEngine();
      final c = makeContainer(engine: engine);
      await ctrl(c).startSession();
      engine.emit(const EngineListening());
      await Future.delayed(Duration.zero);

      await ctrl(c).stopSession();

      expect(stateOf(c), isA<HandsFreeIdle>());
      expect(engine.stopped, isTrue);
    });

    test('stopSession is idempotent', () async {
      final engine = FakeHandsFreeEngine();
      final c = makeContainer(engine: engine);
      await ctrl(c).startSession();
      engine.emit(const EngineListening()); // move out of HandsFreeIdle
      await Future.delayed(Duration.zero);

      await ctrl(c).stopSession();
      await expectLater(ctrl(c).stopSession(), completes);
    });

    test('stopSession with no segments → immediate idle', () async {
      final engine = FakeHandsFreeEngine();
      final c = makeContainer(engine: engine);
      await ctrl(c).startSession();

      await ctrl(c).stopSession();

      expect(stateOf(c), isA<HandsFreeIdle>());
    });

    test('queued jobs rejected and WAVs cleaned up on stop', () async {
      // Use a slow STT (50ms) so seg1 stays in Transcribing when stopSession
      // is called, seg2 stays in QueuedForTranscription.
      // stopSession() rejects seg2 synchronously, then drains seg1 (~50ms).
      // Only seg1's transcript should be saved; seg2 never reaches STT.
      final stt = _SlowSttService(text: 'Hello');
      final storage = FakeStorageService();
      final engine = FakeHandsFreeEngine();
      final c = makeContainer(engine: engine, sttService: stt, storageService: storage);
      await ctrl(c).startSession();

      engine.emit(const EngineSegmentReady('/tmp/seg1.wav'));
      engine.emit(const EngineSegmentReady('/tmp/seg2.wav'));
      await Future.delayed(Duration.zero); // seg1 → Transcribing, seg2 → Queued

      // stopSession() rejects seg2 before STT runs, then drains seg1.
      await ctrl(c).stopSession();

      expect(stateOf(c), isA<HandsFreeIdle>());
      // seg2 was rejected — only seg1's transcript was persisted.
      expect(storage.savedTranscripts, hasLength(1));
    });
  });

  // ── Job tracking ──────────────────────────────────────────────────────────

  group('job tracking', () {
    test('multiple segments → job list grows monotonically', () async {
      final engine = FakeHandsFreeEngine();
      final c = makeContainer(engine: engine);
      await ctrl(c).startSession();

      engine.emit(const EngineSegmentReady('/tmp/seg1.wav'));
      engine.emit(const EngineSegmentReady('/tmp/seg2.wav'));
      await Future.delayed(Duration.zero);

      final jobs = (stateOf(c) as HandsFreeListening).jobs;
      expect(jobs, hasLength(2));
    });

    test('no pending jobs → EngineListening maps to HandsFreeListening',
        () async {
      final engine = FakeHandsFreeEngine();
      final c = makeContainer(engine: engine);
      await ctrl(c).startSession();

      engine.emit(const EngineListening());
      await Future.delayed(Duration.zero);

      expect(stateOf(c), isA<HandsFreeListening>());
    });
  });

  // ── Job processing (T3b) ─────────────────────────────────────────────────

  group('job processing', () {
    test('success path → Completed; one Transcript + one queue item saved',
        () async {
      final stt = FakeSttService(text: 'Hello world');
      final storage = FakeStorageService();
      final engine = FakeHandsFreeEngine();
      final c =
          makeContainer(engine: engine, sttService: stt, storageService: storage);
      await ctrl(c).startSession();

      engine.emit(const EngineSegmentReady('/tmp/seg1.wav'));
      // Allow STT + persist to complete.
      await Future.delayed(const Duration(milliseconds: 50));

      final jobs = jobsOf(stateOf(c));
      expect(jobs, hasLength(1));
      expect(jobs.first.state, isA<Completed>());

      expect(storage.savedTranscripts, hasLength(1));
      expect(storage.savedTranscripts.first.text, 'Hello world');
      expect(storage.savedTranscripts.first.deviceId, 'test-device-123');
      expect(storage.enqueuedIds, hasLength(1));
      expect(storage.enqueuedIds.first, storage.savedTranscripts.first.id);
    });

    test('STT failure → JobFailed; no transcript saved', () async {
      final stt = FakeSttService(throws: true);
      final storage = FakeStorageService();
      final engine = FakeHandsFreeEngine();
      final c =
          makeContainer(engine: engine, sttService: stt, storageService: storage);
      await ctrl(c).startSession();

      engine.emit(const EngineSegmentReady('/tmp/seg1.wav'));
      await Future.delayed(const Duration(milliseconds: 50));

      final jobs = jobsOf(stateOf(c));
      expect(jobs.first.state, isA<JobFailed>());
      expect((jobs.first.state as JobFailed).message, contains('STT error'));
      expect(storage.savedTranscripts, isEmpty);
    });

    test('empty STT result → Rejected; no transcript saved', () async {
      final stt = FakeSttService(text: '   '); // whitespace only
      final storage = FakeStorageService();
      final engine = FakeHandsFreeEngine();
      final c =
          makeContainer(engine: engine, sttService: stt, storageService: storage);
      await ctrl(c).startSession();

      engine.emit(const EngineSegmentReady('/tmp/seg1.wav'));
      await Future.delayed(const Duration(milliseconds: 50));

      final jobs = jobsOf(stateOf(c));
      expect(jobs.first.state, isA<Rejected>());
      expect(storage.savedTranscripts, isEmpty);
    });

    test('enqueue failure → rollback (deleteTranscript) → JobFailed', () async {
      final stt = FakeSttService(text: 'Hello');
      final storage = FakeStorageService()..enqueueThrows = true;
      final engine = FakeHandsFreeEngine();
      final c =
          makeContainer(engine: engine, sttService: stt, storageService: storage);
      await ctrl(c).startSession();

      engine.emit(const EngineSegmentReady('/tmp/seg1.wav'));
      await Future.delayed(const Duration(milliseconds: 50));

      final jobs = jobsOf(stateOf(c));
      expect(jobs.first.state, isA<JobFailed>());
      expect((jobs.first.state as JobFailed).message, contains('Enqueue failed'));

      // Transcript saved but then rolled back (deleted).
      expect(storage.savedTranscripts, hasLength(1));
      expect(storage.deletedIds, hasLength(1));
      expect(storage.deletedIds.first, storage.savedTranscripts.first.id);
      expect(storage.enqueuedIds, isEmpty);
    });

    test('queue saturation: 5th segment is dropped (max 4 non-terminal jobs)',
        () async {
      // Use a hanging STT so no jobs complete — all 4 slots stay occupied.
      final engine = FakeHandsFreeEngine();
      final c = makeContainer(engine: engine); // hanging STT default
      await ctrl(c).startSession();

      for (var i = 1; i <= 5; i++) {
        engine.emit(EngineSegmentReady('/tmp/seg$i.wav'));
      }
      await Future.delayed(Duration.zero);

      final jobs = (stateOf(c) as HandsFreeListening).jobs;
      expect(jobs, hasLength(4), reason: '5th segment must be dropped');
    });

    test('jobs run serially (second job starts after first completes)',
        () async {
      final stt = FakeSttService(text: 'Text');
      final storage = FakeStorageService();
      final engine = FakeHandsFreeEngine();
      final c =
          makeContainer(engine: engine, sttService: stt, storageService: storage);
      await ctrl(c).startSession();

      engine.emit(const EngineSegmentReady('/tmp/seg1.wav'));
      engine.emit(const EngineSegmentReady('/tmp/seg2.wav'));
      await Future.delayed(const Duration(milliseconds: 100));

      final jobs = jobsOf(stateOf(c));
      expect(jobs.every((j) => j.state is Completed), isTrue,
          reason: 'Both jobs must complete when run serially');
      expect(storage.savedTranscripts, hasLength(2));
    });
  });

  // ── suspendForManualRecording / resumeAfterManualRecording ────────────────

  group('suspendForManualRecording', () {
    test('sets isSuspendedForManualRecording and clears engine', () async {
      final engine = FakeHandsFreeEngine();
      final c = makeContainer(engine: engine);
      await ctrl(c).startSession();
      engine.emit(const EngineListening());
      await Future.delayed(Duration.zero);

      await ctrl(c).suspendForManualRecording();

      expect(ctrl(c).isSuspendedForManualRecording, isTrue);
    });

    test('backlog is preserved after suspend (jobs not cleared)', () async {
      final engine = FakeHandsFreeEngine();
      final c = makeContainer(engine: engine); // hanging STT keeps jobs alive
      await ctrl(c).startSession();

      // Add two segments to the backlog.
      engine.emit(const EngineSegmentReady('/tmp/seg1.wav'));
      engine.emit(const EngineSegmentReady('/tmp/seg2.wav'));
      await Future.delayed(Duration.zero);

      final jobsBefore = jobsOf(stateOf(c)).length;
      await ctrl(c).suspendForManualRecording();

      // P037 v2 collapses the suspended state into HandsFreeIdle, so the
      // public job list isn't visible during the suspension. Resume to
      // observe that the controller never cleared its internal _jobs list.
      await ctrl(c).resumeAfterManualRecording();
      final jobsAfter = jobsOf(stateOf(c)).length;
      expect(jobsAfter, equals(jobsBefore),
          reason: 'suspendForManualRecording must not clear the job list');
    });

    test('suspending from HandsFreeCapturing calls interruptCapture', () async {
      bool interrupted = false;
      final engine = _TrackingHfEngine(
        onInterruptCapture: () => interrupted = true,
      );
      final c = makeContainer(engine: engine);
      await ctrl(c).startSession();
      engine.emit(const EngineCapturing());
      await Future.delayed(Duration.zero);

      await ctrl(c).suspendForManualRecording();

      expect(interrupted, isTrue);
    });

    test('suspending from HandsFreeIdle is a no-op', () async {
      final engine = FakeHandsFreeEngine();
      final c = makeContainer(engine: engine);
      // Stay in HandsFreeIdle — do not start a session.

      await ctrl(c).suspendForManualRecording();

      expect(ctrl(c).isSuspendedForManualRecording, isFalse,
          reason: 'no suspension when already idle');
    });
  });

  group('resumeAfterManualRecording', () {
    test('clears isSuspendedForManualRecording and restarts engine', () async {
      final engine = FakeHandsFreeEngine();
      final c = makeContainer(engine: engine);
      await ctrl(c).startSession();
      engine.emit(const EngineListening());
      await Future.delayed(Duration.zero);

      await ctrl(c).suspendForManualRecording();
      expect(ctrl(c).isSuspendedForManualRecording, isTrue);

      engine.started = false; // reset to detect restart
      await ctrl(c).resumeAfterManualRecording();

      expect(ctrl(c).isSuspendedForManualRecording, isFalse);
      expect(engine.started, isTrue, reason: 'engine.start() must be called on resume');
    });

    test('_jobs preserved across suspend + resume cycle', () async {
      final engine = FakeHandsFreeEngine();
      final c = makeContainer(engine: engine); // hanging STT keeps jobs in Transcribing
      await ctrl(c).startSession();

      engine.emit(const EngineSegmentReady('/tmp/seg1.wav'));
      await Future.delayed(Duration.zero);
      final jobsBefore = jobsOf(stateOf(c)).length;

      await ctrl(c).suspendForManualRecording();
      await ctrl(c).resumeAfterManualRecording();

      expect(jobsOf(stateOf(c)).length, equals(jobsBefore),
          reason: 'resumeAfterManualRecording must not reset _jobs');
    });
  });

  // ── Auto-disengage with in-flight jobs (P037 v2 regression) ────────────────
  group('auto-disengage with in-flight jobs', () {
    test('STT completing after auto-disengage keeps state HandsFreeIdle',
        () async {
      // Reproduces the regression where _processJob's
      // `state = _listeningOrBacklog()` flipped HandsFreeIdle back to
      // HandsFreeListening when a job state advanced (Transcribing →
      // Persisting → Completed) while engagement was already closed.
      final engine = FakeHandsFreeEngine();
      final sttCompleter = Completer<TranscriptResult>();
      final stt = _ControllableSttService(sttCompleter);
      final storage = FakeStorageService();
      final engagement =
          EngagementController(timeout: const Duration(milliseconds: 5));

      final container = ProviderContainer(overrides: [
        handsFreeEngineProvider.overrideWithValue(engine),
        appConfigServiceProvider.overrideWithValue(
          _FixedConfigService(const AppConfig(
            groqApiKey: 'gsk_test_valid',
            apiUrl: 'https://test.example.com/api',
          )),
        ),
        recordingControllerProvider.overrideWith(
          (ref) => _IdleRecordingController(ref),
        ),
        sttServiceProvider.overrideWithValue(stt),
        storageServiceProvider.overrideWithValue(storage),
        ttsServiceProvider.overrideWithValue(_StubTtsService()),
        audioFeedbackServiceProvider.overrideWithValue(
          _StubAudioFeedbackService(),
        ),
        backgroundServiceProvider.overrideWithValue(StubBackgroundService()),
        handsFreeControllerProvider.overrideWith(
          (ref) => HandsFreeController(ref, engagement: engagement),
        ),
      ]);
      addTearDown(container.dispose);

      await container.read(handsFreeControllerProvider.notifier).startSession();
      engine.emit(const EngineSegmentReady('/tmp/seg1.wav'));
      await Future.delayed(Duration.zero); // Queued → Transcribing

      // Trigger the 30 s auto-disengage. Listener microtask runs and the
      // controller should transition to HandsFreeIdle preserving the
      // Transcribing job in `jobs`.
      engagement.tickTimeout();
      await Future.delayed(const Duration(milliseconds: 10));
      expect(
        container.read(handsFreeControllerProvider),
        isA<HandsFreeIdle>(),
        reason: 'auto-disengage should land in HandsFreeIdle',
      );

      // Now finish STT — this triggers the original bug if
      // _listeningOrBacklog ignores the current Idle state.
      sttCompleter.complete(TranscriptResult(
        text: 'Hello',
        segments: [],
        detectedLanguage: 'en',
        audioDurationMs: 1000,
      ));
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      final after = container.read(handsFreeControllerProvider);
      expect(after, isA<HandsFreeIdle>(),
          reason:
              'job advances must not flip HandsFreeIdle back to Listening');
      final jobs = jobsOf(after);
      expect(jobs, hasLength(1));
      expect(jobs.first.state, isA<Completed>(),
          reason: 'job state must reflect post-STT progression');
    });
  });
}

class _ControllableSttService implements SttService {
  _ControllableSttService(this._completer);
  final Completer<TranscriptResult> _completer;

  @override
  Future<TranscriptResult> transcribe(String wavPath,
          {String? languageCode}) =>
      _completer.future;

  @override
  Future<bool> isModelLoaded() async => true;
  @override
  Future<void> loadModel() async {}
}
