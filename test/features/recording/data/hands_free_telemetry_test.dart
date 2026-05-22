// P039 T5b — proves that the orchestrator emits the diagnosis-critical
// telemetry events when the audio stream fails or completes.
//
// The proposal's §Mic-silent diagnosis chain says: hard error path leaves
// (a) `hf.stream_error` event with the error message attribute, and
// (b) the long-lived `hf.attach_stream` span is marked error and ended.
// Soft starvation is detected by `hf.chunk_received` flatlining without
// any `hf.stream_error`. Both are tested here.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';
import 'package:voice_agent/core/config/vad_config.dart';
import 'package:voice_agent/core/observability/telemetry.dart';
import 'package:voice_agent/features/recording/data/hands_free_orchestrator.dart';
import 'package:voice_agent/features/recording/domain/hands_free_engine.dart';

import 'vad_service_stub.dart';

class _ExposedFakeRecorder implements AudioRecorder {
  StreamController<Uint8List>? controller;

  @override
  Future<bool> hasPermission({bool request = true}) async => true;

  @override
  Future<Stream<Uint8List>> startStream(RecordConfig config) async {
    controller = StreamController<Uint8List>();
    return controller!.stream;
  }

  @override
  Future<String?> stop() async {
    await controller?.close();
    controller = null;
    return null;
  }

  @override
  Future<void> start(RecordConfig config, {required String path}) async {}
  @override
  Future<bool> isRecording() async => controller != null;
  @override
  Future<bool> isPaused() async => false;
  @override
  Future<void> pause() async {}
  @override
  Future<void> resume() async {}
  @override
  Future<void> cancel() async {}
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

void main() {
  late _RecordingTelemetry recording;

  setUp(() {
    recording = _RecordingTelemetry();
    Telemetry.instance = recording;
  });

  tearDown(() {
    Telemetry.instance = const NoopTelemetry();
  });

  test('a stream error emits hf.stream_error with the message attribute',
      (() async {
    final recorder = _ExposedFakeRecorder();
    final orch = HandsFreeOrchestrator(recorder, FakeVadService(const []),
        watchdogInterval: const Duration(hours: 1));
    final events = <HandsFreeEngineEvent>[];

    final stream = orch.start(config: const VadConfig.defaults());
    stream.listen(events.add);

    // Let _doStart wire the listen() call.
    await Future<void>.delayed(const Duration(milliseconds: 50));

    // Sanity: attach_stream span should have started.
    expect(recording.spans.where((s) => s.name == 'hf.attach_stream'),
        hasLength(1));
    expect(recording.spans.single.endedStatus, isNull);

    // Trigger an error on the underlying audio stream.
    recorder.controller?.addError(const _FakeNativeError('avfaudio 2003329396'));

    // Wait for the error to propagate to the orchestrator.
    await Future<void>.delayed(const Duration(milliseconds: 50));

    // Assert: hf.stream_error event was emitted with the error message.
    final streamErr = recording.events.where((e) => e.name == 'hf.stream_error');
    expect(streamErr, hasLength(1), reason: 'expected exactly one hf.stream_error');
    expect(streamErr.single.attrs['message'], contains('avfaudio 2003329396'));

    // The long-lived span is annotated with the error event and ended.
    final attach = recording.spans.single;
    expect(attach.events.any((e) => e.name == 'hf.stream_error'), isTrue);
    expect(attach.endedStatus, SpanStatus.error);

    orch.dispose();
  }));

  test('each captured audio chunk emits a hf.chunk_received counter',
      (() async {
    final recorder = _ExposedFakeRecorder();
    final orch = HandsFreeOrchestrator(recorder, FakeVadService(const []),
        watchdogInterval: const Duration(hours: 1));
    orch.start(config: const VadConfig.defaults()).listen((_) {});

    await Future<void>.delayed(const Duration(milliseconds: 50));

    // Push three frames (size doesn't matter for the counter; what matters
    // is that _enqueueChunk fires).
    recorder.controller?.add(Uint8List(64));
    recorder.controller?.add(Uint8List(64));
    recorder.controller?.add(Uint8List(64));

    await Future<void>.delayed(const Duration(milliseconds: 50));

    final chunkCounters =
        recording.counters.where((c) => c.name == 'hf.chunk_received');
    expect(chunkCounters, hasLength(3),
        reason: 'one counter per delivered chunk');
    // All emitted while gate was open.
    expect(chunkCounters.every((c) => c.attrs['gate_open'] == true), isTrue);

    orch.dispose();
  }));

  test('chunks delivered with the gate closed still bump the counter',
      (() async {
    // Distinguishes "closed-gate listening" from "dead mic" — closed-gate
    // chunks still arrive, so the counter keeps ticking. A flatlined
    // counter while gate is open is the signature of a dead mic.
    final recorder = _ExposedFakeRecorder();
    final orch = HandsFreeOrchestrator(recorder, FakeVadService(const []),
        watchdogInterval: const Duration(hours: 1));
    orch.start(config: const VadConfig.defaults()).listen((_) {});
    await Future<void>.delayed(const Duration(milliseconds: 50));

    await orch.setCaptureGate(open: false);
    recorder.controller?.add(Uint8List(64));
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final chunks = recording.counters
        .where((c) => c.name == 'hf.chunk_received')
        .toList();
    expect(chunks.last.attrs['gate_open'], isFalse);

    orch.dispose();
  }));
}

class _FakeNativeError implements Exception {
  const _FakeNativeError(this.message);
  final String message;
  @override
  String toString() => message;
}

// ── Test-only Recording Telemetry ────────────────────────────────────────────

class _RecordingTelemetry implements Telemetry {
  final List<_RecEvent> events = [];
  final List<_RecCounter> counters = [];
  final List<_RecSpan> spans = [];

  @override
  void event(String name, {Map<String, Object?> attrs = const {}}) {
    events.add(_RecEvent(name, Map.unmodifiable(attrs)));
  }

  @override
  TelemetrySpan span(String name,
      {SpanKind kind = SpanKind.internal,
      Map<String, Object?> attrs = const {}}) {
    final s = _RecSpan(name, Map.unmodifiable(attrs));
    spans.add(s);
    return s;
  }

  @override
  void counter(String name,
      {int delta = 1, Map<String, Object?> attrs = const {}}) {
    counters.add(_RecCounter(name, delta, Map.unmodifiable(attrs)));
  }

  @override
  void histogram(String name, num value,
      {Map<String, Object?> attrs = const {}}) {}

  @override
  Future<void> flush() async {}
}

class _RecEvent {
  _RecEvent(this.name, this.attrs);
  final String name;
  final Map<String, Object?> attrs;
}

class _RecCounter {
  _RecCounter(this.name, this.delta, this.attrs);
  final String name;
  final int delta;
  final Map<String, Object?> attrs;
}

class _RecSpan implements TelemetrySpan {
  _RecSpan(this.name, this.attrs);
  final String name;
  final Map<String, Object?> attrs;
  final List<_RecEvent> events = [];
  SpanStatus? endedStatus;
  String? endedMessage;

  @override
  void setAttr(String key, Object? value) {}

  @override
  void addEvent(String name, {Map<String, Object?> attrs = const {}}) {
    events.add(_RecEvent(name, Map.unmodifiable(attrs)));
  }

  @override
  void end({SpanStatus status = SpanStatus.unset, String? message}) {
    if (endedStatus != null) return;
    endedStatus = status;
    endedMessage = message;
  }
}
