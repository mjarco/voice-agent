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
import 'package:voice_agent/core/storage/storage_provider.dart';
import 'package:voice_agent/core/storage/storage_service.dart';
import 'package:voice_agent/core/config/vad_config.dart';
import 'package:voice_agent/features/recording/domain/hands_free_engine.dart';
import 'package:voice_agent/features/recording/domain/hands_free_session_state.dart';
import 'package:voice_agent/features/recording/domain/recording_result.dart';
import 'package:voice_agent/features/recording/domain/recording_service.dart';
import 'package:voice_agent/features/recording/domain/recording_state.dart';
import 'package:voice_agent/features/recording/domain/stt_service.dart';
import 'package:voice_agent/core/tts/tts_provider.dart';
import 'package:voice_agent/core/tts/tts_service.dart';
import 'package:voice_agent/features/recording/presentation/hands_free_controller.dart';
import 'package:voice_agent/features/recording/presentation/recording_controller.dart';
import 'package:voice_agent/core/audio/audio_feedback_provider.dart';
import 'package:voice_agent/core/audio/audio_feedback_service.dart';
import 'package:voice_agent/features/recording/presentation/recording_providers.dart';

import '../../../helpers/stub_background_service.dart';

// ── FakeHandsFreeEngine ──────────────────────────────────────────────────────

class _FakeHandsFreeEngine implements HandsFreeEngine {
  bool permissionGranted = true;
  bool started = false;
  bool stopped = false;
  int startCount = 0;

  final _controller = StreamController<HandsFreeEngineEvent>.broadcast();

  void emit(HandsFreeEngineEvent event) => _controller.add(event);

  @override
  Future<bool> hasPermission() async => permissionGranted;

  @override
  Stream<HandsFreeEngineEvent> start({required VadConfig config}) {
    started = true;
    startCount++;
    return _controller.stream;
  }

  @override
  Future<void> stop() async => stopped = true;

  @override
  Future<void> interruptCapture() async {}

  @override
  void dispose() {
    _controller.close();
  }
}

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

class _FixedConfigService extends AppConfigService {
  _FixedConfigService(this._config);
  final AppConfig _config;

  @override
  Future<AppConfig> load() async => _config;
}

class _NullRecordingService implements RecordingService {
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<void> start({required String outputPath}) async {}
  @override
  Future<RecordingResult> stop() async => RecordingResult(
      filePath: '/tmp/t.wav', duration: Duration.zero, sampleRate: 16000);
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
      Completer<TranscriptResult>().future; // never completes
}

class _FakeStorageService implements StorageService {
  @override
  Future<String> getDeviceId() async => 'test-device';
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
  Future<List<TranscriptWithStatus>> getTranscriptsWithStatus(
          {int limit = 20, int offset = 0}) async =>
      [];
  @override
  Future<int> recoverStaleSending() async => 0;
  @override
  Future<List<SyncQueueItem>> getFailedItems({int? maxAttempts}) async => [];
}

// ── Container factory ────────────────────────────────────────────────────────

ProviderContainer _makeContainer({
  required _FakeHandsFreeEngine engine,
  String? groqApiKey = 'gsk_test_valid',
  BackgroundService? backgroundService,
}) {
  final container = ProviderContainer(overrides: [
    handsFreeEngineProvider.overrideWithValue(engine),
    appConfigServiceProvider.overrideWithValue(
      _FixedConfigService(AppConfig(groqApiKey: groqApiKey, apiUrl: 'https://test.example.com/api')),
    ),
    recordingControllerProvider.overrideWith(
      (ref) => _IdleRecordingController(ref),
    ),
    sttServiceProvider.overrideWithValue(_NullSttService()),
    storageServiceProvider.overrideWithValue(_FakeStorageService()),
    ttsServiceProvider.overrideWithValue(_StubTtsService()),
    audioFeedbackServiceProvider
        .overrideWithValue(_StubAudioFeedbackService()),
    backgroundServiceProvider
        .overrideWithValue(backgroundService ?? StubBackgroundService()),
  ]);
  addTearDown(container.dispose);
  return container;
}

/// [RecordingController] backed by no-op stubs -- stays in [RecordingState.idle].
class _IdleRecordingController extends RecordingController {
  _IdleRecordingController(Ref ref)
      : super(_NullRecordingService(), _NullSttService(), ref);
}

HandsFreeController _ctrl(ProviderContainer c) =>
    c.read(handsFreeControllerProvider.notifier);

HandsFreeSessionState _stateOf(ProviderContainer c) =>
    c.read(handsFreeControllerProvider);

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() => WidgetsFlutterBinding.ensureInitialized());

  group('suspendByUser', () {
    test('from listening transitions to HandsFreeIdle (P037 v2)', () async {
      final engine = _FakeHandsFreeEngine();
      final c = _makeContainer(engine: engine);
      await _ctrl(c).startSession();
      engine.emit(const EngineListening());
      await Future.delayed(Duration.zero);
      expect(_stateOf(c), isA<HandsFreeListening>());

      await _ctrl(c).suspendByUser();

      expect(_stateOf(c), isA<HandsFreeIdle>());
    });

    test('is no-op when already suspended by user', () async {
      final engine = _FakeHandsFreeEngine();
      final c = _makeContainer(engine: engine);
      await _ctrl(c).startSession();
      engine.emit(const EngineListening());
      await Future.delayed(Duration.zero);

      await _ctrl(c).suspendByUser();
      expect(_stateOf(c), isA<HandsFreeIdle>());

      // Second call should be no-op
      await _ctrl(c).suspendByUser();
      expect(_stateOf(c), isA<HandsFreeIdle>());
    });

    test('is no-op from HandsFreeIdle', () async {
      final engine = _FakeHandsFreeEngine();
      final c = _makeContainer(engine: engine);
      // Don't start session — stay idle

      await _ctrl(c).suspendByUser();

      expect(_stateOf(c), isA<HandsFreeIdle>());
    });

    test('is no-op from HandsFreeSessionError', () async {
      final engine = _FakeHandsFreeEngine()..permissionGranted = false;
      final c = _makeContainer(engine: engine);
      await _ctrl(c).startSession();

      await _ctrl(c).suspendByUser();

      expect(_stateOf(c), isA<HandsFreeSessionError>());
    });

    test('fast path when already suspended for TTS', () async {
      final engine = _FakeHandsFreeEngine();
      final c = _makeContainer(engine: engine);
      await _ctrl(c).startSession();
      engine.emit(const EngineListening());
      await Future.delayed(Duration.zero);

      // Suspend for TTS first
      await _ctrl(c).suspendForTts();
      // Now suspend by user — should take the fast path
      await _ctrl(c).suspendByUser();

      expect(_stateOf(c), isA<HandsFreeIdle>());
    });
  });

  group('resumeByUser', () {
    test('from suspended transitions to HandsFreeListening', () async {
      final engine = _FakeHandsFreeEngine();
      final c = _makeContainer(engine: engine);
      await _ctrl(c).startSession();
      engine.emit(const EngineListening());
      await Future.delayed(Duration.zero);

      await _ctrl(c).suspendByUser();
      expect(_stateOf(c), isA<HandsFreeIdle>());

      engine.started = false;
      await _ctrl(c).resumeByUser();

      expect(_stateOf(c), isA<HandsFreeListening>());
      expect(engine.started, isTrue, reason: 'engine must restart on resume');
    });

    test('is no-op when not suspended by user', () async {
      final engine = _FakeHandsFreeEngine();
      final c = _makeContainer(engine: engine);
      await _ctrl(c).startSession();
      engine.emit(const EngineListening());
      await Future.delayed(Duration.zero);

      await _ctrl(c).resumeByUser();

      expect(_stateOf(c), isA<HandsFreeListening>());
    });

    test('does not restart engine if still suspended for TTS', () async {
      final engine = _FakeHandsFreeEngine();
      final c = _makeContainer(engine: engine);
      await _ctrl(c).startSession();
      engine.emit(const EngineListening());
      await Future.delayed(Duration.zero);

      await _ctrl(c).suspendForTts();
      await _ctrl(c).suspendByUser();
      expect(_stateOf(c), isA<HandsFreeIdle>());

      engine.started = false;
      engine.startCount = 0;
      await _ctrl(c).resumeByUser();

      // Engine should NOT start because TTS suspension is still active
      expect(engine.startCount, 0);
    });

    test(
        'does not restart engine if still suspended for manual recording',
        () async {
      final engine = _FakeHandsFreeEngine();
      final c = _makeContainer(engine: engine);
      await _ctrl(c).startSession();
      engine.emit(const EngineListening());
      await Future.delayed(Duration.zero);

      await _ctrl(c).suspendForManualRecording();
      await _ctrl(c).suspendByUser();
      expect(_stateOf(c), isA<HandsFreeIdle>());

      engine.started = false;
      engine.startCount = 0;
      await _ctrl(c).resumeByUser();

      // Engine should NOT start because manual recording suspension is still active
      expect(engine.startCount, 0);
    });
  });

  group('toggleUserSuspend', () {
    test('suspends when not suspended', () async {
      final engine = _FakeHandsFreeEngine();
      final c = _makeContainer(engine: engine);
      await _ctrl(c).startSession();
      engine.emit(const EngineListening());
      await Future.delayed(Duration.zero);

      final result = await _ctrl(c).toggleUserSuspend();

      expect(result, isTrue);
      expect(_stateOf(c), isA<HandsFreeIdle>());
    });

    test('resumes when already suspended', () async {
      final engine = _FakeHandsFreeEngine();
      final c = _makeContainer(engine: engine);
      await _ctrl(c).startSession();
      engine.emit(const EngineListening());
      await Future.delayed(Duration.zero);

      await _ctrl(c).suspendByUser();
      expect(_stateOf(c), isA<HandsFreeIdle>());

      final result = await _ctrl(c).toggleUserSuspend();

      expect(result, isFalse);
      expect(_stateOf(c), isA<HandsFreeListening>());
    });
  });

  group('suspension priority — resumeAfterTts', () {
    test('does not restart when _suspendedByUser is true', () async {
      final engine = _FakeHandsFreeEngine();
      final c = _makeContainer(engine: engine);
      await _ctrl(c).startSession();
      engine.emit(const EngineListening());
      await Future.delayed(Duration.zero);

      // TTS + user suspend
      await _ctrl(c).suspendForTts();
      await _ctrl(c).suspendByUser();
      expect(_stateOf(c), isA<HandsFreeIdle>());

      engine.started = false;
      engine.startCount = 0;

      // TTS finishes — but user pause should keep VAD stopped
      await _ctrl(c).resumeAfterTts();

      expect(engine.startCount, 0,
          reason: 'user pause takes precedence over TTS resume');
    });
  });

  group('conversation-turn auto-resume after TTS (P037 v2)', () {
    test('TTS-end after per-segment one-shot re-engages a fresh '
        'listening window', () async {
      // Reproduces the user-reported gap: per-segment one-shot closes
      // the engagement immediately, so by the time TTS plays the
      // controller is already HandsFreeIdle and the legacy
      // `_suspendedForTts` flag is never set. The conversational
      // signal `_pendingConversationResume` (set by _disengageOneShot)
      // must drive the resume instead.
      final engine = _FakeHandsFreeEngine();
      final c = _makeContainer(engine: engine);

      await _ctrl(c).startSession();
      engine.emit(const EngineSegmentReady('/tmp/seg1.wav'));
      // Two microtask ticks: one for job → Transcribing, one for
      // _disengageOneShot to land HandsFreeIdle with the flag set.
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);
      expect(_stateOf(c), isA<HandsFreeIdle>(),
          reason: 'per-segment one-shot must close engagement');

      engine.startCount = 0;

      // No suspendForTts in v2 — the recording_screen still calls it
      // when ttsPlayingProvider flips to true, but it short-circuits
      // because state is already Idle. So we only need to fire the
      // resume callback to model "TTS just ended."
      await _ctrl(c).resumeAfterTts();

      expect(engine.startCount, 1,
          reason: 'TTS-end after captured utterance must re-engage');
    });

    test('does NOT auto-resume when no segment was captured (cold TTS)',
        () async {
      // If TTS plays without a preceding captured segment (e.g. an
      // unrelated background announcement), we must not silently open
      // a listening window — that would steal the mic with no user
      // intent.
      final engine = _FakeHandsFreeEngine();
      final c = _makeContainer(engine: engine);

      // Controller starts in HandsFreeIdle, never engaged → no flag.
      engine.startCount = 0;
      await _ctrl(c).resumeAfterTts();

      expect(engine.startCount, 0,
          reason: 'cold TTS-end (no captured segment) must NOT engage');
    });

    test('user re-engaging before TTS-end clears the conversation flag',
        () async {
      // User clicks AirPods between disengage and TTS-end. They've
      // taken control. The deferred TTS-end must NOT trigger a second
      // engage on top of the user's manual one.
      final engine = _FakeHandsFreeEngine();
      final c = _makeContainer(engine: engine);

      await _ctrl(c).startSession();
      engine.emit(const EngineSegmentReady('/tmp/seg1.wav'));
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);
      expect(_stateOf(c), isA<HandsFreeIdle>());

      // User clicks again before TTS plays.
      await _ctrl(c).startSession();
      engine.emit(const EngineListening());
      await Future.delayed(Duration.zero);
      expect(_stateOf(c), isA<HandsFreeListening>());
      engine.startCount = 0;

      // Now (delayed) TTS-end fires. Should be a no-op — we're
      // already engaged via the user's manual click.
      await _ctrl(c).resumeAfterTts();

      expect(engine.startCount, 0,
          reason: 'manual re-engage must clear pending conversation flag');
    });
  });

  group('suspension priority — resumeAfterManualRecording', () {
    test('does not restart when _suspendedByUser is true', () async {
      final engine = _FakeHandsFreeEngine();
      final c = _makeContainer(engine: engine);
      await _ctrl(c).startSession();
      engine.emit(const EngineListening());
      await Future.delayed(Duration.zero);

      await _ctrl(c).suspendForManualRecording();
      await _ctrl(c).suspendByUser();
      expect(_stateOf(c), isA<HandsFreeIdle>());

      engine.started = false;
      engine.startCount = 0;

      // Manual recording finishes — but user pause should keep VAD stopped
      await _ctrl(c).resumeAfterManualRecording();

      expect(engine.startCount, 0,
          reason: 'user pause takes precedence over manual recording resume');
    });
  });

  group('reloadVadConfig guard', () {
    test('is no-op when _suspendedByUser', () async {
      final engine = _FakeHandsFreeEngine();
      final c = _makeContainer(engine: engine);
      await _ctrl(c).startSession();
      engine.emit(const EngineListening());
      await Future.delayed(Duration.zero);

      await _ctrl(c).suspendByUser();
      expect(_stateOf(c), isA<HandsFreeIdle>());

      engine.started = false;
      engine.startCount = 0;

      await _ctrl(c).reloadVadConfig();

      expect(engine.startCount, 0,
          reason: 'reloadVadConfig should not restart engine when user paused');
    });
  });

  group('stopSession', () {
    test('clears _suspendedByUser', () async {
      final engine = _FakeHandsFreeEngine();
      final c = _makeContainer(engine: engine);
      await _ctrl(c).startSession();
      engine.emit(const EngineListening());
      await Future.delayed(Duration.zero);

      await _ctrl(c).suspendByUser();
      expect(_stateOf(c), isA<HandsFreeIdle>());

      await _ctrl(c).stopSession();

      expect(_stateOf(c), isA<HandsFreeIdle>());

      // Start again — should work normally (no lingering user pause)
      await _ctrl(c).startSession();
      engine.emit(const EngineListening());
      await Future.delayed(Duration.zero);

      expect(_stateOf(c), isA<HandsFreeListening>());
    });
  });
}
