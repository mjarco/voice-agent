import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';
import 'package:voice_agent/core/audio/audio_route_service.dart';
import 'package:voice_agent/core/config/vad_config.dart';
import 'package:voice_agent/features/recording/data/hands_free_orchestrator.dart';

import 'vad_service_stub.dart';

/// [AudioRouteService] whose change stream is driven by the test.
class _FakeRouteService implements AudioRouteService {
  final _controller = StreamController<AudioRouteChange>.broadcast();

  void emit(AudioRouteChangeReason reason) =>
      _controller.add(AudioRouteChange(reason));

  @override
  Stream<AudioRouteChange> get changes => _controller.stream;

  Future<void> dispose() => _controller.close();
}

/// [AudioRecorder] fake that counts `startStream` / `stop` calls so tests
/// can assert a capture restart happened.
class _CountingRecorder implements AudioRecorder {
  int startStreamCount = 0;
  int stopCount = 0;
  StreamController<Uint8List>? _controller;

  void push(Uint8List bytes) => _controller?.add(bytes);

  @override
  Future<bool> hasPermission({bool request = true}) async => true;

  @override
  Future<Stream<Uint8List>> startStream(RecordConfig config) async {
    startStreamCount++;
    await _controller?.close();
    _controller = StreamController<Uint8List>();
    return _controller!.stream;
  }

  @override
  Future<String?> stop() async {
    stopCount++;
    await _controller?.close();
    _controller = null;
    return null;
  }

  @override
  Future<void> start(RecordConfig config, {required String path}) async {}
  @override
  Future<bool> isRecording() async => _controller != null;
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
  group('P042 — route-change recovery', () {
    test('an input-affecting route change restarts capture', () async {
      final recorder = _CountingRecorder();
      final route = _FakeRouteService();
      final orch = HandsFreeOrchestrator(
        recorder,
        FakeVadService(const []),
        audioRouteService: route,
        watchdogInterval: const Duration(hours: 1),
        routeRestartDebounce: const Duration(milliseconds: 30),
      );
      orch.start(config: const VadConfig.defaults()).listen((_) {});
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(recorder.startStreamCount, 1);

      route.emit(AudioRouteChangeReason.oldDeviceUnavailable);
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(recorder.startStreamCount, 2,
          reason: 'capture re-acquired on the new route');
      await orch.stop();
      await route.dispose();
    });

    test('a non-input route change does not restart capture', () async {
      final recorder = _CountingRecorder();
      final route = _FakeRouteService();
      final orch = HandsFreeOrchestrator(
        recorder,
        FakeVadService(const []),
        audioRouteService: route,
        watchdogInterval: const Duration(hours: 1),
        routeRestartDebounce: const Duration(milliseconds: 30),
      );
      orch.start(config: const VadConfig.defaults()).listen((_) {});
      await Future<void>.delayed(const Duration(milliseconds: 60));

      // categoryChange is the app's own doing — must not trigger a restart.
      route.emit(AudioRouteChangeReason.categoryChange);
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(recorder.startStreamCount, 1);
      await orch.stop();
      await route.dispose();
    });

    test('a burst of route changes triggers a single restart', () async {
      final recorder = _CountingRecorder();
      final route = _FakeRouteService();
      final orch = HandsFreeOrchestrator(
        recorder,
        FakeVadService(const []),
        audioRouteService: route,
        watchdogInterval: const Duration(hours: 1),
        routeRestartDebounce: const Duration(milliseconds: 50),
      );
      orch.start(config: const VadConfig.defaults()).listen((_) {});
      await Future<void>.delayed(const Duration(milliseconds: 60));

      route.emit(AudioRouteChangeReason.oldDeviceUnavailable);
      route.emit(AudioRouteChangeReason.newDeviceAvailable);
      route.emit(AudioRouteChangeReason.routeConfigurationChange);
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(recorder.startStreamCount, 2,
          reason: 'debounce collapses the burst into one restart');
      await orch.stop();
      await route.dispose();
    });
  });

  group('P042 — silent-mic watchdog', () {
    test('restarts capture when no audio chunks arrive', () async {
      final recorder = _CountingRecorder();
      final orch = HandsFreeOrchestrator(
        recorder,
        FakeVadService(const []),
        watchdogInterval: const Duration(milliseconds: 50),
      );
      orch.start(config: const VadConfig.defaults()).listen((_) {});
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(recorder.startStreamCount, 1);

      // Push nothing — the mic is "dead". Watchdog needs one grace tick
      // then fires on the next.
      await Future<void>.delayed(const Duration(milliseconds: 250));

      expect(recorder.startStreamCount, greaterThanOrEqualTo(2),
          reason: 'watchdog re-acquired the dead mic');
      await orch.stop();
    });

    test('does not restart while audio chunks keep arriving', () async {
      final recorder = _CountingRecorder();
      final orch = HandsFreeOrchestrator(
        recorder,
        FakeVadService(const []),
        watchdogInterval: const Duration(milliseconds: 50),
      );
      orch.start(config: const VadConfig.defaults()).listen((_) {});
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // A chunk every 25 ms keeps the 50 ms watchdog satisfied.
      for (var i = 0; i < 12; i++) {
        recorder.push(Uint8List(64));
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }

      expect(recorder.startStreamCount, 1,
          reason: 'a live mic must not be restarted');
      await orch.stop();
    });
  });
}
