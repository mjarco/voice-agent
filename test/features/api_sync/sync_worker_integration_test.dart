import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/session_control/hands_free_control_port.dart';
import 'package:voice_agent/core/session_control/haptic_service.dart';
import 'package:voice_agent/core/session_control/session_control_dispatcher.dart';
import 'package:voice_agent/core/session_control/session_control_signal.dart';
import 'package:voice_agent/core/session_control/session_id_coordinator.dart';
import 'package:voice_agent/core/session_control/toaster.dart';
import 'package:voice_agent/core/tts/tts_service.dart';

// -- Test doubles --------------------------------------------------------

class _FakeTtsService implements TtsService {
  @override
  ValueListenable<bool> get isSpeaking => ValueNotifier(false);

  @override
  Future<void> speak(String text, {String? languageCode}) async {}

  @override
  Future<void> stop() async {}

  @override
  void dispose() {}
}

class _FakeHandsFreeControlPort implements HandsFreeControlPort {
  int stopSessionCalls = 0;

  @override
  bool isSuspendedForManualRecording = false;

  @override
  Future<void> stopSession() async {
    stopSessionCalls++;
  }
}

class _FakeToaster extends Toaster {
  _FakeToaster() : super(GlobalKey<ScaffoldMessengerState>());
  final List<String> messages = [];

  @override
  void show(String message, {Duration duration = const Duration(seconds: 2)}) {
    messages.add(message);
  }
}

class _FakeHapticService extends HapticService {
  int calls = 0;

  @override
  Future<void> lightImpact() async {
    calls++;
  }
}

// -- Tests ---------------------------------------------------------------

void main() {
  late _FakeTtsService ttsService;
  late _FakeHandsFreeControlPort controlPort;
  late SessionIdCoordinator coordinator;
  late _FakeToaster toaster;
  late _FakeHapticService haptic;
  late SessionControlDispatcher dispatcher;

  setUp(() {
    ttsService = _FakeTtsService();
    controlPort = _FakeHandsFreeControlPort();
    coordinator = SessionIdCoordinator();
    toaster = _FakeToaster();
    haptic = _FakeHapticService();
    dispatcher = SessionControlDispatcher(
      ttsService: ttsService,
      handsFreeControlPort: controlPort,
      sessionIdCoordinator: coordinator,
      toaster: toaster,
      hapticService: haptic,
      ttsTimeout: Duration.zero,
    );
  });

  group('full integration: signal parsing + dispatch', () {
    test('stop_recording=true dispatches and calls stopSession', () async {
      final body = {
        'message': 'Goodbye',
        'session_control': {'stop_recording': true},
      };
      final signal = SessionControlSignal.fromBody(body);
      expect(signal, isNotNull);

      await dispatcher.dispatch(signal!);

      expect(controlPort.stopSessionCalls, 1);
      expect(toaster.messages, ['Session ended']);
      expect(haptic.calls, 1);
      expect(coordinator.currentConversationId, isNull);
    });

    test('reset_session=true dispatches and clears coordinator', () async {
      coordinator.adoptConversationId('old-conv-id');
      expect(coordinator.currentConversationId, 'old-conv-id');

      final body = {
        'message': 'New session',
        'session_control': {'reset_session': true},
      };
      final signal = SessionControlSignal.fromBody(body);
      expect(signal, isNotNull);

      await dispatcher.dispatch(signal!);

      expect(coordinator.currentConversationId, isNull);
      expect(controlPort.stopSessionCalls, 0);
      expect(toaster.messages, ['New conversation']);
      expect(haptic.calls, 1);
    });

    test('both signals: reset applied first, then stop', () async {
      coordinator.adoptConversationId('old-id');
      final callOrder = <String>[];

      // Use a custom control port that records call order
      final orderPort = _OrderedControlPort(callOrder);
      final orderCoordinator = _OrderedSessionIdCoordinator(callOrder);
      orderCoordinator.adoptConversationId('old-id');

      final orderDispatcher = SessionControlDispatcher(
        ttsService: ttsService,
        handsFreeControlPort: orderPort,
        sessionIdCoordinator: orderCoordinator,
        toaster: toaster,
        hapticService: haptic,
        ttsTimeout: Duration.zero,
      );

      final body = {
        'message': 'Goodbye',
        'session_control': {'reset_session': true, 'stop_recording': true},
      };
      final signal = SessionControlSignal.fromBody(body);
      expect(signal, isNotNull);

      await orderDispatcher.dispatch(signal!);

      expect(callOrder, ['resetSession', 'stopSession']);
      expect(toaster.messages, ['New conversation', 'Session ended']);
      expect(haptic.calls, 2);
    });

    test('both false (noop envelope) dispatches but does not call actions',
        () async {
      final body = {
        'message': 'Hello',
        'session_control': {'reset_session': false, 'stop_recording': false},
      };
      final signal = SessionControlSignal.fromBody(body);
      expect(signal, isNotNull);
      expect(signal!.isNoop, isTrue);

      await dispatcher.dispatch(signal);

      expect(controlPort.stopSessionCalls, 0);
      expect(toaster.messages, isEmpty);
      expect(haptic.calls, 0);
    });

    test('absent session_control key produces null signal', () {
      final body = {'message': 'Hello'};
      final signal = SessionControlSignal.fromBody(body);
      expect(signal, isNull);
    });
  });
}

// -- Ordered test doubles for verifying call order -----------------------

class _OrderedControlPort implements HandsFreeControlPort {
  _OrderedControlPort(this._log);
  final List<String> _log;

  @override
  bool isSuspendedForManualRecording = false;

  @override
  Future<void> stopSession() async {
    _log.add('stopSession');
  }
}

class _OrderedSessionIdCoordinator extends SessionIdCoordinator {
  _OrderedSessionIdCoordinator(this._log);
  final List<String> _log;

  @override
  Future<void> resetSession() async {
    _log.add('resetSession');
    await super.resetSession();
  }
}
