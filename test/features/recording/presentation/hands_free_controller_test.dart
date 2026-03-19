import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/config/app_config.dart';
import 'package:voice_agent/core/config/app_config_provider.dart';
import 'package:voice_agent/core/config/app_config_service.dart';
import 'package:voice_agent/core/models/transcript_result.dart';
import 'package:voice_agent/features/recording/domain/hands_free_engine.dart';
import 'package:voice_agent/features/recording/domain/hands_free_session_state.dart';
import 'package:voice_agent/features/recording/domain/recording_result.dart';
import 'package:voice_agent/features/recording/domain/recording_service.dart';
import 'package:voice_agent/features/recording/domain/recording_state.dart';
import 'package:voice_agent/features/recording/domain/segment_job.dart';
import 'package:voice_agent/features/recording/domain/stt_exception.dart';
import 'package:voice_agent/features/recording/domain/stt_service.dart';
import 'package:voice_agent/features/recording/presentation/hands_free_controller.dart';
import 'package:voice_agent/features/recording/presentation/recording_controller.dart';
import 'package:voice_agent/features/recording/presentation/recording_providers.dart';

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
  Stream<HandsFreeEngineEvent> start() {
    started = true;
    return _controller.stream;
  }

  @override
  Future<void> stop() async => stopped = true;

  @override
  void dispose() {
    disposed = true;
    _controller.close();
  }
}

// ── _FixedConfigService ───────────────────────────────────────────────────────

/// [AppConfigService] that returns a fixed [AppConfig] — no platform I/O.
class _FixedConfigService extends AppConfigService {
  _FixedConfigService(this._config);
  final AppConfig _config;

  @override
  Future<AppConfig> load() async => _config;
}

// ── _ActiveRecordingController ────────────────────────────────────────────────

/// [RecordingController] backed by no-op stubs — stays in [RecordingState.idle].
class _IdleRecordingController extends RecordingController {
  _IdleRecordingController(Ref ref) : super(
    _NullRecordingService(),
    _NullSttService(),
    ref,
  );
}

/// [RecordingController] that always reports [RecordingActive].
class _ActiveRecordingController extends RecordingController {
  _ActiveRecordingController(Ref ref) : super(
    _NullRecordingService(),
    _NullSttService(),
    ref,
  ) {
    // Force-set the state to recording via the protected setter.
    // ignore: invalid_use_of_protected_member
    state = const RecordingState.recording();
  }
}

// ── Minimal no-op stubs for _ActiveRecordingController ───────────────────────

class _NullRecordingService implements RecordingService {
  @override Future<bool> requestPermission() async => true;
  @override Future<void> start({required String outputPath}) async {}
  @override Future<RecordingResult> stop() async =>
      RecordingResult(filePath: '/tmp/t.wav', duration: Duration.zero, sampleRate: 16000);
  @override Future<void> cancel() async {}
  @override bool get isRecording => false;
  @override Stream<Duration> get elapsed => const Stream.empty();
}

class _NullSttService implements SttService {
  @override Future<bool> isModelLoaded() async => false;
  @override Future<void> loadModel() async {}
  @override Future<TranscriptResult> transcribe(String wavPath, {String? languageCode}) async =>
      throw SttException('unused');
}

// ── Container factory ────────────────────────────────────────────────────────

ProviderContainer makeContainer({
  required FakeHandsFreeEngine engine,
  String? groqApiKey = 'gsk_test_valid',
  bool recordingActive = false,
}) {
  final container = ProviderContainer(overrides: [
    handsFreeEngineProvider.overrideWithValue(engine),
    appConfigServiceProvider.overrideWithValue(
      _FixedConfigService(AppConfig(groqApiKey: groqApiKey)),
    ),
    recordingControllerProvider.overrideWith(
      (ref) => recordingActive
          ? _ActiveRecordingController(ref)
          : _IdleRecordingController(ref),
    ),
  ]);
  addTearDown(container.dispose);
  return container;
}

HandsFreeController ctrl(ProviderContainer c) =>
    c.read(handsFreeControllerProvider.notifier);

HandsFreeSessionState stateOf(ProviderContainer c) =>
    c.read(handsFreeControllerProvider);

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

  // ── Active-recording guard ────────────────────────────────────────────────

  group('active-recording guard', () {
    test('manual recording active → SessionError (no OS/app-settings flags)',
        () async {
      final engine = FakeHandsFreeEngine();
      final c = makeContainer(engine: engine, recordingActive: true);

      await ctrl(c).startSession();

      final s = stateOf(c) as HandsFreeSessionError;
      expect(s.requiresSettings, isFalse);
      expect(s.requiresAppSettings, isFalse);
      expect(engine.started, isFalse);
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

    test('EngineCapturing → HandsFreeCapturing', () async {
      final engine = FakeHandsFreeEngine();
      final c = makeContainer(engine: engine);
      await ctrl(c).startSession();

      engine.emit(const EngineCapturing());
      await Future.delayed(Duration.zero);

      expect(stateOf(c), isA<HandsFreeCapturing>());
    });

    test('EngineStopping → HandsFreeStopping', () async {
      final engine = FakeHandsFreeEngine();
      final c = makeContainer(engine: engine);
      await ctrl(c).startSession();

      engine.emit(const EngineStopping());
      await Future.delayed(Duration.zero);

      expect(stateOf(c), isA<HandsFreeStopping>());
    });

    test('EngineSegmentReady → job added, state becomes WithBacklog', () async {
      final engine = FakeHandsFreeEngine();
      final c = makeContainer(engine: engine);
      await ctrl(c).startSession();

      engine.emit(const EngineSegmentReady('/tmp/seg1.wav'));
      await Future.delayed(Duration.zero);

      final s = stateOf(c);
      expect(s, isA<HandsFreeWithBacklog>());
      final jobs = (s as HandsFreeWithBacklog).jobs;
      expect(jobs, hasLength(1));
      expect(jobs.first.state, isA<QueuedForTranscription>());
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

  // ── Background interruption ───────────────────────────────────────────────

  group('background interruption', () {
    test('app paused during session → SessionError containing "backgrounded"',
        () async {
      final engine = FakeHandsFreeEngine();
      final c = makeContainer(engine: engine);
      await ctrl(c).startSession();
      engine.emit(const EngineListening()); // move out of HandsFreeIdle
      await Future.delayed(Duration.zero);

      ctrl(c).didChangeAppLifecycleState(AppLifecycleState.paused);
      await Future.delayed(Duration.zero);

      final s = stateOf(c) as HandsFreeSessionError;
      expect(s.message, contains('backgrounded'));
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

      await ctrl(c).stopSession();
      await expectLater(ctrl(c).stopSession(), completes);
    });

    test('drain-then-idle: only queued jobs (no in-flight) → stops immediately',
        () async {
      final engine = FakeHandsFreeEngine();
      final c = makeContainer(engine: engine);
      await ctrl(c).startSession();

      engine.emit(const EngineSegmentReady('/tmp/seg1.wav'));
      await Future.delayed(Duration.zero);

      await ctrl(c).stopSession();

      expect(stateOf(c), isA<HandsFreeIdle>());
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

      final jobs = (stateOf(c) as HandsFreeWithBacklog).jobs;
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
}
