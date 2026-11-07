import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/audio/audio_feedback_provider.dart';
import 'package:voice_agent/core/audio/audio_feedback_service.dart';
import 'package:voice_agent/core/background/background_service.dart';
import 'package:voice_agent/core/background/background_service_provider.dart';
import 'package:voice_agent/core/config/app_config.dart';
import 'package:voice_agent/core/config/app_config_provider.dart';
import 'package:voice_agent/core/config/app_config_service.dart';
import 'package:voice_agent/core/config/vad_config.dart';
import 'package:voice_agent/core/models/transcript_result.dart';
import 'package:voice_agent/core/providers/app_foreground_provider.dart';
import 'package:voice_agent/core/providers/session_active_provider.dart';
import 'package:voice_agent/core/session_control/mic_mode.dart';
import 'package:voice_agent/core/tts/tts_provider.dart';
import 'package:voice_agent/core/tts/tts_service.dart';
import 'package:voice_agent/features/recording/domain/hands_free_engine.dart';
import 'package:voice_agent/features/recording/domain/hands_free_session_state.dart';
import 'package:voice_agent/features/recording/domain/recording_result.dart';
import 'package:voice_agent/features/recording/domain/recording_service.dart';
import 'package:voice_agent/features/recording/domain/segment_job.dart';
import 'package:voice_agent/features/recording/domain/stt_exception.dart';
import 'package:voice_agent/features/recording/domain/stt_service.dart';
import 'package:voice_agent/features/recording/presentation/hands_free_controller.dart';
import 'package:voice_agent/features/recording/presentation/recording_controller.dart';
import 'package:voice_agent/features/recording/presentation/recording_providers.dart';

// Android three-mode path of HandsFreeController (ADR-AUDIO-013). The
// iOS path keeps its own tests in hands_free_controller_test.dart.

// ── Fakes ────────────────────────────────────────────────────────────────────

/// Records every call; like the real orchestrator, keeps its gate across
/// a stop and a start.
class _Engine implements HandsFreeEngine {
  int starts = 0;
  int stops = 0;
  bool gateOpen = true;
  final List<bool> gateCalls = [];
  bool permission = true;
  StreamController<HandsFreeEngineEvent>? _ctrl;

  bool get running => _ctrl != null;

  void emit(HandsFreeEngineEvent e) => _ctrl?.add(e);
  void fail(Object e) => _ctrl?.addError(e);

  @override
  Future<bool> hasPermission() async => permission;

  @override
  Stream<HandsFreeEngineEvent> start({required VadConfig config}) {
    starts++;
    _ctrl = StreamController<HandsFreeEngineEvent>.broadcast();
    return _ctrl!.stream;
  }

  /// When set, a stop waits for it before releasing the recorder.
  Completer<void>? stopGate;

  @override
  Future<void> stop() async {
    stops++;
    if (stopGate != null) await stopGate!.future;
    final c = _ctrl;
    _ctrl = null;
    await c?.close();
  }

  @override
  Future<void> setCaptureGate({required bool open}) async {
    gateCalls.add(open);
    gateOpen = open;
  }

  @override
  Future<void> interruptCapture() => stop();

  @override
  void dispose() {}
}

class _Service implements BackgroundService {
  int starts = 0;
  int stops = 0;
  bool _running = false;

  @override
  bool get isRunning => _running;

  @override
  Future<void> startService() async {
    starts++;
    _running = true;
  }

  @override
  Future<void> stopService({
    AudioSessionTarget target = AudioSessionTarget.playback,
  }) async {
    stops++;
    _running = false;
  }

  @override
  Future<void> updateNotification({
    required String title,
    required String body,
  }) async {}
}

class _Tts implements TtsService {
  final ValueNotifier<bool> speaking = ValueNotifier(false);
  int stops = 0;

  @override
  ValueListenable<bool> get isSpeaking => speaking;
  @override
  Future<void> speak(String text, {String? languageCode}) async {}
  @override
  Future<void> stop() async => stops++;
  @override
  void dispose() {}
}

/// Holds every transcription until [release] completes.
class _GatedStt implements SttService {
  final Completer<TranscriptResult> release = Completer();
  int calls = 0;
  @override
  Future<TranscriptResult> transcribe(String wavPath,
      {String? languageCode}) {
    calls++;
    return release.future;
  }

  @override
  Future<bool> isModelLoaded() async => true;
  @override
  Future<void> loadModel() async {}
}

/// Never resolves: keeps a job in Transcribing.
class _HangingStt implements SttService {
  @override
  Future<TranscriptResult> transcribe(String wavPath,
          {String? languageCode}) =>
      Completer<TranscriptResult>().future;
  @override
  Future<bool> isModelLoaded() async => true;
  @override
  Future<void> loadModel() async {}
}

class _NoAudioFeedback implements AudioFeedbackService {
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

class _Config extends AppConfigService {
  _Config(this._config);
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

class _NullStt implements SttService {
  @override
  Future<bool> isModelLoaded() async => false;
  @override
  Future<void> loadModel() async {}
  @override
  Future<TranscriptResult> transcribe(String wavPath,
          {String? languageCode}) async =>
      throw SttException('unused');
}

// ── Harness ──────────────────────────────────────────────────────────────────

class _Harness {
  _Harness({String? groqApiKey = 'gsk_test', SttService? stt}) {
    container = ProviderContainer(overrides: [
      micModesEnabledProvider.overrideWithValue(true),
      handsFreeEngineProvider.overrideWithValue(engine),
      backgroundServiceProvider.overrideWithValue(service),
      ttsServiceProvider.overrideWithValue(tts),
      sttServiceProvider.overrideWithValue(stt ?? _HangingStt()),
      audioFeedbackServiceProvider.overrideWithValue(_NoAudioFeedback()),
      appConfigServiceProvider.overrideWithValue(_Config(AppConfig(
        groqApiKey: groqApiKey,
        apiUrl: 'https://test.example.com/api',
      ))),
      recordingControllerProvider.overrideWith(
        (ref) => RecordingController(_NullRecordingService(), _NullStt(), ref),
      ),
    ]);
    addTearDown(container.dispose);
  }

  final engine = _Engine();
  final service = _Service();
  final tts = _Tts();
  late final ProviderContainer container;

  HandsFreeController get ctrl =>
      container.read(handsFreeControllerProvider.notifier);
  HandsFreeSessionState get state => container.read(handsFreeControllerProvider);
  MicMode get mode => container.read(micModeProvider);
  bool get sessionActive => container.read(sessionActiveProvider);

  Future<void> listening() async {
    await ctrl.startSession();
    expect(mode, MicMode.listening);
  }

  Future<void> standby() async {
    await listening();
    await ctrl.pauseSession();
    expect(mode, MicMode.standby);
  }
}

List<SegmentJob> _jobs(HandsFreeSessionState s) => switch (s) {
      HandsFreeListening(:final jobs) => jobs,
      HandsFreeSessionError(:final jobs) => jobs,
      HandsFreeIdle(:final jobs) => jobs,
    };

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  setUpAll(() => WidgetsFlutterBinding.ensureInitialized());

  group('Off → Listening (start)', () {
    test('starts the service, then the recorder, with the gate open',
        () async {
      final h = _Harness();
      await h.ctrl.startSession();

      expect(h.mode, MicMode.listening);
      expect(h.state, isA<HandsFreeListening>());
      expect(h.service.starts, 1);
      expect(h.engine.starts, 1);
      expect(h.engine.gateOpen, isTrue);
      expect(h.sessionActive, isTrue);
    });

    test('a failed guard keeps Off and shows the error', () async {
      final h = _Harness(groqApiKey: null);
      await h.ctrl.startSession();

      expect(h.mode, MicMode.off);
      expect(h.state, isA<HandsFreeSessionError>());
      expect(h.engine.starts, 0);
      expect(h.service.starts, 0);
    });

    test('a start in Standby is ignored', () async {
      final h = _Harness();
      await h.standby();
      await h.ctrl.startSession();

      expect(h.mode, MicMode.standby);
      expect(h.engine.starts, 1);
      expect(h.service.starts, 1);
    });
  });

  group('Listening → Standby (pause)', () {
    test('stops the recorder, keeps the service, the session and the queue',
        () async {
      final h = _Harness();
      await h.listening();
      h.engine.emit(const EngineSegmentReady('/tmp/does-not-exist.wav'));
      await _settle();
      expect(_jobs(h.state), hasLength(1));

      await h.ctrl.pauseSession();

      expect(h.mode, MicMode.standby);
      expect(h.state, isA<HandsFreeIdle>());
      expect(_jobs(h.state), hasLength(1), reason: 'the queue is kept');
      expect(h.engine.stops, 1);
      expect(h.engine.running, isFalse, reason: 'the mic is released');
      expect(h.service.stops, 0);
      expect(h.sessionActive, isTrue, reason: 'the queue keeps draining');
    });

    test('stops a reply being spoken: Pause means quiet', () async {
      final h = _Harness();
      await h.listening();
      await h.ctrl.pauseSession();
      expect(h.tts.stops, greaterThanOrEqualTo(1));
    });

    test('a pause in Standby or Off is ignored', () async {
      final h = _Harness();
      await h.ctrl.pauseSession();
      expect(h.mode, MicMode.off);

      await h.standby();
      await h.ctrl.pauseSession();
      expect(h.mode, MicMode.standby);
      expect(h.engine.stops, 1);
    });
  });

  group('Standby → Listening (resume)', () {
    test('starts the recorder cold and opens the gate', () async {
      final h = _Harness();
      await h.standby();
      await h.ctrl.resumeSession();

      expect(h.mode, MicMode.listening);
      expect(h.state, isA<HandsFreeListening>());
      expect(h.engine.starts, 2);
      expect(h.engine.running, isTrue);
      expect(h.engine.gateOpen, isTrue);
      expect(h.service.starts, 1, reason: 'the service never stopped');
    });

    test('a quick resume waits for the recorder to stop first', () async {
      final h = _Harness();
      await h.listening();
      h.engine.stopGate = Completer<void>();

      final pause = h.ctrl.pauseSession();
      final resume = h.ctrl.resumeSession();
      await _settle();
      expect(h.engine.starts, 1, reason: 'no start before the stop ends');

      h.engine.stopGate!.complete();
      await pause;
      await resume;

      expect(h.mode, MicMode.listening);
      expect(h.engine.starts, 2);
      expect(h.engine.running, isTrue,
          reason: 'the old stop did not close the new stream');
    });

    test('a pause again while stopping leaves the recorder off', () async {
      final h = _Harness();
      await h.listening();
      h.engine.stopGate = Completer<void>();

      final pause = h.ctrl.pauseSession();
      final resume = h.ctrl.resumeSession();
      await _settle();
      final pauseAgain = h.ctrl.pauseSession();
      h.engine.stopGate!.complete();
      await Future.wait([pause, resume, pauseAgain]);

      expect(h.mode, MicMode.standby);
      expect(h.engine.starts, 1);
      expect(h.engine.running, isFalse);
    });

    test('pause, resume, pause, resume within one stop starts the recorder '
        'once', () async {
      final h = _Harness();
      await h.listening();
      h.engine.stopGate = Completer<void>();

      final calls = [
        h.ctrl.pauseSession(),
        h.ctrl.resumeSession(),
        h.ctrl.pauseSession(),
        h.ctrl.resumeSession(),
      ];
      await _settle();
      expect(h.engine.starts, 1, reason: 'nothing starts before the stop');

      h.engine.stopGate!.complete();
      await Future.wait(calls);
      await _settle();

      expect(h.mode, MicMode.listening);
      expect(h.engine.starts, 2, reason: 'only the latest resume starts');
      expect(h.engine.running, isTrue);
    });

    test('a resume in Off is ignored', () async {
      final h = _Harness();
      await h.ctrl.resumeSession();
      expect(h.mode, MicMode.off);
      expect(h.engine.starts, 0);
    });

    test('a pause during a reply, then a resume, opens the gate again',
        () async {
      final h = _Harness();
      await h.listening();
      h.tts.speaking.value = true;
      await _settle();
      expect(h.engine.gateOpen, isFalse);

      await h.ctrl.pauseSession();
      h.tts.speaking.value = false;
      await _settle();
      await h.ctrl.resumeSession();

      expect(h.engine.gateOpen, isTrue);
    });

    test('a resume while a reply is spoken keeps the gate closed', () async {
      final h = _Harness();
      await h.standby();
      h.tts.speaking.value = true;
      await _settle();
      await h.ctrl.resumeSession();
      await _settle();

      expect(h.engine.gateOpen, isFalse);
      h.tts.speaking.value = false;
      await _settle();
      expect(h.engine.gateOpen, isTrue);
    });
  });

  group('→ Off (stop)', () {
    test('from Listening: stops the recorder and the service', () async {
      final h = _Harness();
      await h.listening();
      await h.ctrl.stopSession();

      expect(h.mode, MicMode.off);
      expect(h.state, isA<HandsFreeIdle>());
      expect(h.engine.running, isFalse);
      expect(h.service.stops, 1);
      expect(h.sessionActive, isFalse);
    });

    test('from Standby with an empty queue still stops the service (#380)',
        () async {
      final h = _Harness();
      await h.standby();
      expect(_jobs(h.state), isEmpty);
      await h.ctrl.stopSession();

      expect(h.mode, MicMode.off);
      expect(h.service.stops, 1);
      expect(h.sessionActive, isFalse);
    });

    test('rejects queued jobs, drains the one in flight, empties the queue',
        () async {
      final stt = _GatedStt();
      final h = _Harness(stt: stt);
      await h.listening();
      h.engine.emit(const EngineSegmentReady('/tmp/a.wav'));
      h.engine.emit(const EngineSegmentReady('/tmp/b.wav'));
      await _settle();
      final jobs = _jobs(h.state);
      expect(jobs[0].state, isA<Transcribing>());
      expect(jobs[1].state, isA<QueuedForTranscription>());

      final stop = h.ctrl.stopSession();
      await _settle();
      // The queued job is rejected at once; the stop waits for the one in
      // flight.
      stt.release.completeError(SttException('network'));
      await stop;

      expect(h.mode, MicMode.off);
      expect(_jobs(h.state), isEmpty);
      expect(stt.calls, 1, reason: 'the queued job never reached STT');
    });

    test('during the drain the mode and the state already say Off',
        () async {
      final stt = _GatedStt();
      final h = _Harness(stt: stt);
      await h.listening();
      h.engine.emit(const EngineSegmentReady('/tmp/a.wav'));
      await _settle();

      final stop = h.ctrl.stopSession();
      await _settle();
      expect(h.mode, MicMode.off);
      expect(h.state, isA<HandsFreeIdle>());
      expect(_jobs(h.state), hasLength(1), reason: 'the job still drains');

      stt.release.completeError(SttException('network'));
      await stop;
    });

    test('a start during the drain waits for it, then starts clean',
        () async {
      final stt = _GatedStt();
      final h = _Harness(stt: stt);
      await h.listening();
      h.engine.emit(const EngineSegmentReady('/tmp/a.wav'));
      await _settle();

      final stop = h.ctrl.stopSession();
      await _settle();
      final start = h.ctrl.startSession();
      await _settle();
      expect(h.mode, MicMode.off, reason: 'the start waits for the drain');

      stt.release.completeError(SttException('network'));
      await stop;
      await start;

      expect(h.mode, MicMode.listening);
      expect(h.state, isA<HandsFreeListening>());
      expect(_jobs(h.state), isEmpty, reason: 'the old queue is gone');
      expect(h.engine.running, isTrue);
      expect(h.service.starts, 2);
    });

    test('a stop in Off with nothing queued does nothing', () async {
      final h = _Harness();
      await h.ctrl.stopSession();
      expect(h.service.stops, 0);
    });
  });

  group('the turn inside Listening', () {
    test('an utterance does not close the gate or leave Listening', () async {
      final h = _Harness();
      await h.listening();
      h.engine.gateCalls.clear();

      h.engine.emit(const EngineCapturing());
      await _settle();
      h.engine.emit(const EngineSegmentReady('/tmp/x.wav'));
      h.engine.emit(const EngineListening());
      await _settle();

      expect(h.mode, MicMode.listening);
      expect(h.state, isA<HandsFreeListening>());
      expect(h.engine.gateCalls, isEmpty);
      expect(h.engine.stops, 0);
    });

    test('a reply closes the gate while spoken, then opens it', () async {
      final h = _Harness();
      await h.listening();

      h.tts.speaking.value = true;
      await _settle();
      expect(h.engine.gateOpen, isFalse);
      expect(h.state, isA<HandsFreeListening>(),
          reason: 'the mode the user sees does not change');

      h.tts.speaking.value = false;
      await _settle();
      expect(h.engine.gateOpen, isTrue);
      expect(h.engine.starts, 1, reason: 'no recorder restart for a reply');
    });

    test('a reply that starts mid-utterance leaves the capturing phase',
        () async {
      final h = _Harness();
      await h.listening();
      h.engine.emit(const EngineCapturing());
      await _settle();
      expect((h.state as HandsFreeListening).phase,
          HandsFreeListeningPhase.capturing);

      h.tts.speaking.value = true;
      await _settle();

      expect((h.state as HandsFreeListening).phase,
          HandsFreeListeningPhase.listening,
          reason: 'the gate dropped the segment; the mic is not red');
    });

    test('TTS in Standby touches no gate', () async {
      final h = _Harness();
      await h.standby();
      h.engine.gateCalls.clear();

      h.tts.speaking.value = true;
      await _settle();
      h.tts.speaking.value = false;
      await _settle();

      expect(h.engine.gateCalls, isEmpty);
      expect(h.mode, MicMode.standby);
    });
  });

  group('Listening → Standby (error)', () {
    test('keeps the service and shows the message', () async {
      final h = _Harness();
      await h.listening();

      h.engine.emit(const EngineError('Mic lost'));
      await _settle();

      expect(h.mode, MicMode.standby);
      final s = h.state;
      expect(s, isA<HandsFreeSessionError>());
      expect((s as HandsFreeSessionError).message, 'Mic lost');
      expect(h.service.stops, 0);
      expect(h.sessionActive, isTrue);
      expect(h.engine.running, isFalse);
    });

    test('a stream error is an error too', () async {
      final h = _Harness();
      await h.listening();
      h.engine.fail(Exception('boom'));
      await _settle();
      expect(h.mode, MicMode.standby);
      expect(h.state, isA<HandsFreeSessionError>());
    });

    test('a resume clears the error', () async {
      final h = _Harness();
      await h.listening();
      h.engine.emit(const EngineError('Mic lost'));
      await _settle();

      await h.ctrl.resumeSession();

      expect(h.mode, MicMode.listening);
      expect(h.state, isA<HandsFreeListening>());
    });
  });

  group('push-to-talk', () {
    test('from Listening: Standby for the recording, back in the foreground',
        () async {
      final h = _Harness();
      await h.listening();

      await h.ctrl.suspendForManualRecording();
      expect(h.mode, MicMode.standby);
      expect(h.ctrl.isSuspendedForManualRecording, isTrue);
      expect(h.engine.running, isFalse, reason: 'one recorder at a time');

      await h.ctrl.resumeAfterManualRecording();
      expect(h.mode, MicMode.listening);
      expect(h.ctrl.isSuspendedForManualRecording, isFalse);
    });

    test('ending in the background stays in Standby', () async {
      final h = _Harness();
      await h.listening();
      await h.ctrl.suspendForManualRecording();
      h.container.read(appForegroundedProvider.notifier).state = false;

      await h.ctrl.resumeAfterManualRecording();

      expect(h.mode, MicMode.standby);
      expect(h.ctrl.isSuspendedForManualRecording, isFalse);
    });

    test('from Standby or Off changes nothing', () async {
      final h = _Harness();
      await h.ctrl.suspendForManualRecording();
      expect(h.ctrl.isSuspendedForManualRecording, isFalse);
      expect(h.mode, MicMode.off);

      await h.standby();
      await h.ctrl.suspendForManualRecording();
      await h.ctrl.resumeAfterManualRecording();
      expect(h.mode, MicMode.standby);
    });

    test('a Stop during the recording wins over the return', () async {
      final h = _Harness();
      await h.listening();
      await h.ctrl.suspendForManualRecording();
      await h.ctrl.stopSession();
      await h.ctrl.resumeAfterManualRecording();
      expect(h.mode, MicMode.off);
    });
  });

  group('the legacy entry points map to the modes', () {
    test('suspendByUser pauses and resumeByUser resumes', () async {
      final h = _Harness();
      await h.listening();
      await h.ctrl.suspendByUser();
      expect(h.mode, MicMode.standby);
      await h.ctrl.resumeByUser();
      expect(h.mode, MicMode.listening);
    });

    test('toggleUserSuspend toggles', () async {
      final h = _Harness();
      await h.listening();
      expect(await h.ctrl.toggleUserSuspend(), isTrue);
      expect(h.mode, MicMode.standby);
      expect(await h.ctrl.toggleUserSuspend(), isFalse);
      expect(h.mode, MicMode.listening);
    });

    test('a pause during a VAD reload leaves the recorder off', () async {
      final h = _Harness();
      await h.listening();
      h.engine.stopGate = Completer<void>();

      final reload = h.ctrl.reloadVadConfig();
      final pause = h.ctrl.pauseSession();
      h.engine.stopGate!.complete();
      await Future.wait([reload, pause]);

      expect(h.mode, MicMode.standby);
      expect(h.engine.starts, 1);
      expect(h.engine.running, isFalse);
    });

    test('a VAD reload in Standby does not start the recorder', () async {
      final h = _Harness();
      await h.standby();
      await h.ctrl.reloadVadConfig();
      expect(h.engine.running, isFalse);
      expect(h.mode, MicMode.standby);
    });
  });
}
