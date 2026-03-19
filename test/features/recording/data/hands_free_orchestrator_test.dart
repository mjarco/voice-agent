import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';
import 'package:voice_agent/core/config/vad_config.dart';
import 'package:voice_agent/features/recording/data/hands_free_orchestrator.dart';
import 'package:voice_agent/features/recording/domain/hands_free_engine.dart';
import 'package:voice_agent/features/recording/domain/vad_service.dart';

import 'vad_service_stub.dart';

// ── FakeAudioRecorder ────────────────────────────────────────────────────────

/// Fake [AudioRecorder] that exposes a sink so tests can push PCM bytes.
class FakeAudioRecorder implements AudioRecorder {
  bool permissionGranted = true;
  bool started = false;
  StreamController<Uint8List>? _controller;

  void push(Uint8List bytes) => _controller?.add(bytes);

  @override
  Future<bool> hasPermission({bool request = true}) async => permissionGranted;

  @override
  Future<Stream<Uint8List>> startStream(RecordConfig config) async {
    started = true;
    _controller = StreamController<Uint8List>();
    return _controller!.stream;
  }

  @override
  Future<String?> stop() async {
    started = false;
    await _controller?.close();
    _controller = null;
    return null;
  }

  @override
  Future<void> start(RecordConfig config, {required String path}) async {}
  @override
  Future<bool> isRecording() async => started;
  @override
  Future<bool> isPaused() async => false;
  @override
  Future<void> pause() async {}
  @override
  Future<void> resume() async {}
  @override
  Future<void> cancel() async { started = false; }
  @override
  Future<Amplitude> getAmplitude() async => Amplitude(current: -30, max: -10);
  @override
  Future<bool> isEncoderSupported(AudioEncoder encoder) async => true;
  @override
  Future<List<InputDevice>> listInputDevices() async => [];
  @override
  Stream<RecordState> onStateChanged() => const Stream.empty();
  @override
  Future<void> dispose() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ── Constants (matching HandsFreeOrchestrator internals) ─────────────────────

const int _frameSize = 1024; // FakeVadService.frameSize
// msPerFrame = 1024 * 1000 ~/ (16000 * 2) = 32 ms
const int _hangoverFrameThreshold = 16; // ceil(500 / 32)
const int _minSpeechFrameThreshold = 13; // ceil(400 / 32)
const int _maxSpeechFrameThreshold = 938; // ceil(30000 / 32)

// ── Helpers ──────────────────────────────────────────────────────────────────

Uint8List pcm(int frames, {int value = 0}) {
  final buf = Uint8List(frames * _frameSize);
  if (value != 0) buf.fillRange(0, buf.length, value);
  return buf;
}

/// Busy-wait until [events] contains an instance of [T], or [timeout] elapses.
Future<void> waitFor<T extends HandsFreeEngineEvent>(
  List<HandsFreeEngineEvent> events, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!events.any((e) => e is T)) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Timed out waiting for $T');
    }
    await Future.delayed(const Duration(milliseconds: 5));
  }
}

// ── Tests ────────────────────────────────────────────────────────────────────

void main() {
  late FakeAudioRecorder recorder;
  late HandsFreeOrchestrator orch;

  tearDown(() => orch.dispose());

  HandsFreeOrchestrator make(List<VadLabel> labels) {
    recorder = FakeAudioRecorder();
    return HandsFreeOrchestrator(recorder, FakeVadService(labels));
  }

  // ── Lifecycle ────────────────────────────────────────────────────────────

  group('lifecycle', () {
    test('start() emits EngineListening', () async {
      orch = make([]);
      final events = <HandsFreeEngineEvent>[];
      final sub = orch.start(config: const VadConfig.defaults()).listen(events.add);

      await waitFor<EngineListening>(events);
      await orch.stop();
      await sub.cancel();

      expect(events.first, isA<EngineListening>());
    });

    test('stop() is idempotent', () async {
      orch = make([]);
      final events = <HandsFreeEngineEvent>[];
      final sub = orch.start(config: const VadConfig.defaults()).listen(events.add);
      // Wait for the engine to be fully started before stopping.
      await waitFor<EngineListening>(events);
      await orch.stop();
      await sub.cancel();
      // Second stop on an idle engine must complete immediately.
      await expectLater(orch.stop(), completes);
    });

    test('stream closes after stop()', () async {
      orch = make([]);
      bool done = false;
      final events = <HandsFreeEngineEvent>[];
      final sub =
          orch.start(config: const VadConfig.defaults()).listen(events.add, onDone: () => done = true);
      await waitFor<EngineListening>(events);
      await orch.stop();
      // Give the done callback time to fire.
      await Future.delayed(const Duration(milliseconds: 20));
      await sub.cancel();
      expect(done, isTrue);
    });
  });

  // ── hasPermission ─────────────────────────────────────────────────────────

  group('hasPermission', () {
    test('delegates to AudioRecorder', () async {
      orch = make([]);
      recorder.permissionGranted = true;
      expect(await orch.hasPermission(), isTrue);
      recorder.permissionGranted = false;
      expect(await orch.hasPermission(), isFalse);
    });
  });

  // ── Remainder buffer ──────────────────────────────────────────────────────

  group('remainder buffer', () {
    test('half-frame chunks accumulate into full frames', () async {
      // Push 3 speech frames as 6 half-frame chunks.
      // Engine should detect speech and emit EngineCapturing.
      const speechFrames = 3;
      orch = make(List.filled(speechFrames, VadLabel.speech));

      final events = <HandsFreeEngineEvent>[];
      final sub = orch.start(config: const VadConfig.defaults()).listen(events.add);
      await waitFor<EngineListening>(events);

      final half = Uint8List(_frameSize ~/ 2);
      for (var i = 0; i < speechFrames * 2; i++) {
        recorder.push(half);
        await Future.delayed(Duration.zero);
      }

      await Future.delayed(const Duration(milliseconds: 50));
      await orch.stop();
      await sub.cancel();

      expect(events, contains(isA<EngineCapturing>()));
    });

    test('multi-frame chunk is split into individual frames', () async {
      // Push 10 frames in one chunk; first frame is speech → EngineCapturing.
      const total = 10;
      final labels = [
        VadLabel.speech,
        ...List.filled(total - 1, VadLabel.nonSpeech),
      ];
      orch = make(labels);

      final events = <HandsFreeEngineEvent>[];
      final sub = orch.start(config: const VadConfig.defaults()).listen(events.add);
      await waitFor<EngineListening>(events);

      recorder.push(pcm(total));
      await Future.delayed(const Duration(milliseconds: 100));

      await orch.stop();
      await sub.cancel();

      expect(events, contains(isA<EngineCapturing>()));
    });

    test('sub-frame leftover does not crash', () async {
      // Push 1.5 frames — the 0.5 frame remainder stays in buffer.
      orch = make([VadLabel.nonSpeech]);
      final events = <HandsFreeEngineEvent>[];
      final sub = orch.start(config: const VadConfig.defaults()).listen(events.add);
      await waitFor<EngineListening>(events);

      recorder.push(Uint8List((_frameSize * 1.5).toInt()));
      await Future.delayed(const Duration(milliseconds: 50));

      await orch.stop();
      await sub.cancel();
      // No crash — test passes if we reach here.
    });
  });

  // ── minSpeechMs gate ──────────────────────────────────────────────────────

  group('minSpeechMs gate', () {
    test('segment < minSpeechMs is silently dropped — no EngineSegmentReady',
        () async {
      // 3 speech frames (96 ms) < minSpeechMs (400 ms → 13 frames).
      // After 16 hangover frames the segment ends with validSpeech = false.
      final labels = [
        ...List.filled(3, VadLabel.speech),
        ...List.filled(_hangoverFrameThreshold, VadLabel.nonSpeech),
      ];
      orch = make(labels);

      final events = <HandsFreeEngineEvent>[];
      final sub = orch.start(config: const VadConfig.defaults()).listen(events.add);
      await waitFor<EngineListening>(events);

      recorder.push(pcm(labels.length));
      await Future.delayed(const Duration(milliseconds: 200));

      await orch.stop();
      await sub.cancel();

      expect(events, isNot(contains(isA<EngineSegmentReady>())));
      // EngineStopping is emitted even for short segments.
      expect(events, contains(isA<EngineStopping>()));
    });

    test('segment >= minSpeechMs triggers EngineStopping', () async {
      // 13 speech frames + 16 hangover frames → segment is long enough.
      // WAV write may fail in test environment (no path_provider platform),
      // but EngineStopping must be emitted before the write.
      final labels = [
        ...List.filled(_minSpeechFrameThreshold, VadLabel.speech),
        ...List.filled(_hangoverFrameThreshold, VadLabel.nonSpeech),
      ];
      orch = make(labels);

      final events = <HandsFreeEngineEvent>[];
      final sub = orch.start(config: const VadConfig.defaults()).listen(events.add);
      await waitFor<EngineListening>(events);

      recorder.push(pcm(labels.length));
      await Future.delayed(const Duration(milliseconds: 200));

      await orch.stop();
      await sub.cancel();

      expect(events, contains(isA<EngineCapturing>()));
      expect(events, contains(isA<EngineStopping>()));
    });
  });

  // ── Deferred speech during stopping (maxSegment path, no cooldown) ────────

  group('deferred speech during stopping', () {
    test(
      'speech arriving during maxSegment stopping resumes capturing',
      () async {
        // Push _maxSpeechFrameThreshold (938) speech frames → force-close
        // (no cooldown). Then push 1 more speech frame that arrives during
        // _Phase.stopping → _pendingSpeechStarted = true → EngineCapturing
        // emitted after wav write (which will fail in test env but still
        // triggers _afterWavWrite).
        final labels = [
          ...List.filled(_maxSpeechFrameThreshold, VadLabel.speech),
          VadLabel.speech, // deferred — arrives during stopping
        ];
        orch = make(labels);

        final events = <HandsFreeEngineEvent>[];
        final sub = orch.start(config: const VadConfig.defaults()).listen(events.add);
        await waitFor<EngineListening>(events);

        // Push all frames in one chunk for speed.
        recorder.push(pcm(labels.length));

        // Wait for the pipeline to process (938 async VAD calls + wav write).
        await Future.delayed(const Duration(milliseconds: 1000));

        await orch.stop();
        await sub.cancel();

        final capturingCount = events.whereType<EngineCapturing>().length;
        expect(capturingCount, greaterThanOrEqualTo(2),
            reason:
                'Expected EngineCapturing from initial speech AND from deferred speech after maxSegment');
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );

    test(
      'cooldown suppresses pending speech after hangover-triggered stop',
      () async {
        // 13 speech + 16 hangover → validSpeech segment, cooldown starts.
        // Immediately 1 speech frame during stopping → suppressed by cooldown.
        // After wav write: returns to EngineListening, NOT EngineCapturing.
        final labels = [
          ...List.filled(_minSpeechFrameThreshold, VadLabel.speech),
          ...List.filled(_hangoverFrameThreshold, VadLabel.nonSpeech),
          VadLabel.speech, // arrives during stopping — should be suppressed
        ];
        orch = make(labels);

        final events = <HandsFreeEngineEvent>[];
        final sub = orch.start(config: const VadConfig.defaults()).listen(events.add);
        await waitFor<EngineListening>(events);

        recorder.push(pcm(labels.length));
        await Future.delayed(const Duration(milliseconds: 300));

        await orch.stop();
        await sub.cancel();

        // Only 1 EngineCapturing (from the initial speech).
        // The pending speech frame is cooldown-suppressed.
        final capturingCount = events.whereType<EngineCapturing>().length;
        expect(capturingCount, equals(1));
        // After the stop: EngineListening is re-emitted (back to listening phase).
        final listeningCount = events.whereType<EngineListening>().length;
        expect(listeningCount, greaterThanOrEqualTo(2));
      },
    );
  });

  // ── Event ordering ────────────────────────────────────────────────────────

  group('event ordering', () {
    test('no speech → only EngineListening emitted', () async {
      // Pure silence: no speech events, no capturing.
      orch = make(List.filled(5, VadLabel.nonSpeech));

      final events = <HandsFreeEngineEvent>[];
      final sub = orch.start(config: const VadConfig.defaults()).listen(events.add);
      await waitFor<EngineListening>(events);

      recorder.push(pcm(5));
      await Future.delayed(const Duration(milliseconds: 50));

      await orch.stop();
      await sub.cancel();

      expect(events.every((e) => e is EngineListening), isTrue);
    });

    test('speech → hangover → listening sequence is correct', () async {
      // 3 speech (below minSpeech) + hangover → back to listening.
      final labels = [
        ...List.filled(3, VadLabel.speech),
        ...List.filled(_hangoverFrameThreshold, VadLabel.nonSpeech),
      ];
      orch = make(labels);

      final events = <HandsFreeEngineEvent>[];
      final sub = orch.start(config: const VadConfig.defaults()).listen(events.add);
      await waitFor<EngineListening>(events);

      recorder.push(pcm(labels.length));
      await Future.delayed(const Duration(milliseconds: 200));

      await orch.stop();
      await sub.cancel();

      // Sequence: Listening → Capturing → Stopping → Listening
      final types = events.map((e) => e.runtimeType).toList();
      expect(types.indexOf(EngineListening), lessThan(types.indexOf(EngineCapturing)));
      expect(types.indexOf(EngineCapturing), lessThan(types.indexOf(EngineStopping)));
      // EngineListening appears at least twice (start + return from stopping).
      expect(events.whereType<EngineListening>().length, greaterThanOrEqualTo(2));
    });
  });

  // ── interruptCapture ─────────────────────────────────────────────────────

  group('interruptCapture', () {
    test('stream closes after interruptCapture()', () async {
      orch = make([]);
      bool done = false;
      final events = <HandsFreeEngineEvent>[];
      final sub = orch
          .start(config: const VadConfig.defaults())
          .listen(events.add, onDone: () => done = true);
      await waitFor<EngineListening>(events);

      await orch.interruptCapture();
      await Future.delayed(const Duration(milliseconds: 20));
      await sub.cancel();

      expect(done, isTrue, reason: 'stream must close after interruptCapture');
    });

    test('interruptCapture() is idempotent (already idle)', () async {
      orch = make([]);
      // Do not call start() — engine is idle.
      await expectLater(orch.interruptCapture(), completes);
    });

    test('no events emitted after interruptCapture() while capturing', () async {
      // Create labels: enough speech frames to start capturing, then nothing.
      final labels = [
        ...List.filled(1, VadLabel.speech), // triggers capturing
        ...List.filled(5, VadLabel.nonSpeech),
      ];
      orch = make(labels);
      final events = <HandsFreeEngineEvent>[];
      final sub = orch.start(config: const VadConfig.defaults()).listen(events.add);
      await waitFor<EngineListening>(events);

      // Push one speech frame to transition to Capturing, then interrupt.
      recorder.push(pcm(1, value: 1));
      await Future.delayed(const Duration(milliseconds: 20));

      final countBeforeInterrupt = events.length;
      await orch.interruptCapture();
      await Future.delayed(const Duration(milliseconds: 50));
      await sub.cancel();

      // No EngineSegmentReady should have been emitted after interrupt.
      expect(events.whereType<EngineSegmentReady>(), isEmpty,
          reason: 'partial segment must be discarded, not emitted');
      expect(events.length, equals(countBeforeInterrupt),
          reason: 'no new events after interruptCapture');
    });
  });
}
