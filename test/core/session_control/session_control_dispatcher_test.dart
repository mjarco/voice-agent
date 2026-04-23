import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/session_control/hands_free_control_port.dart';
import 'package:voice_agent/core/session_control/haptic_service.dart';
import 'package:voice_agent/core/session_control/session_control_dispatcher.dart';
import 'package:voice_agent/core/session_control/session_control_signal.dart';
import 'package:voice_agent/core/session_control/session_id_coordinator.dart';
import 'package:voice_agent/core/session_control/toaster.dart';
import 'package:voice_agent/core/tts/tts_service.dart';

// -- Fakes ----------------------------------------------------------------

class _FakeTtsService implements TtsService {
  final ValueNotifier<bool> _speaking = ValueNotifier(false);

  @override
  ValueListenable<bool> get isSpeaking => _speaking;

  void setSpeaking(bool value) => _speaking.value = value;

  @override
  Future<void> speak(String text, {String? languageCode}) async {}

  @override
  Future<void> stop() async {
    _speaking.value = false;
  }

  @override
  void dispose() {
    _speaking.dispose();
  }
}

class _FakeHandsFreeControlPort implements HandsFreeControlPort {
  final List<String> calls = [];
  bool _suspended = false;

  set suspended(bool value) => _suspended = value;

  @override
  bool get isSuspendedForManualRecording => _suspended;

  @override
  Future<void> stopSession() async {
    calls.add('stopSession');
  }
}

class _FakeToaster implements Toaster {
  final List<String> messages = [];

  @override
  void show(String message, {Duration duration = const Duration(seconds: 2)}) {
    messages.add(message);
  }
}

class _FakeHapticService implements HapticService {
  int callCount = 0;

  @override
  Future<void> lightImpact() async {
    callCount++;
  }
}

/// Tracks all side-effect calls in invocation order for ordering assertions.
class _CallLog {
  final List<String> entries = [];
}

// -- Tests ----------------------------------------------------------------

void main() {
  late _FakeTtsService tts;
  late _FakeHandsFreeControlPort handsFree;
  late SessionIdCoordinator coordinator;
  late _FakeToaster toaster;
  late _FakeHapticService haptic;
  late _CallLog callLog;
  late SessionControlDispatcher dispatcher;

  setUp(() {
    tts = _FakeTtsService();
    handsFree = _FakeHandsFreeControlPort();
    coordinator = SessionIdCoordinator();
    toaster = _FakeToaster();
    haptic = _FakeHapticService();
    callLog = _CallLog();

    // Wrap coordinator and handsFree to record call ordering.
    final loggingCoordinator = _LoggingSessionIdCoordinator(
      coordinator,
      callLog,
    );
    final loggingHandsFree = _LoggingHandsFreeControlPort(
      handsFree,
      callLog,
    );

    dispatcher = SessionControlDispatcher(
      ttsService: tts,
      handsFreeControlPort: loggingHandsFree,
      sessionIdCoordinator: loggingCoordinator,
      toaster: toaster,
      hapticService: haptic,
      ttsTimeout: const Duration(milliseconds: 200),
    );
  });

  group('SessionControlDispatcher', () {
    test('reset=true, stop=false: resetSession called, stopSession not, '
        'toast "New conversation", haptic fires', () async {
      const signal = SessionControlSignal(
        resetSession: true,
        stopRecording: false,
      );

      await dispatcher.dispatch(signal);

      expect(callLog.entries, ['resetSession']);
      expect(handsFree.calls, isEmpty);
      expect(toaster.messages, ['New conversation']);
      expect(haptic.callCount, 1);
    });

    test('reset=false, stop=true: stopSession called, resetSession not, '
        'toast "Session ended", haptic fires', () async {
      const signal = SessionControlSignal(
        resetSession: false,
        stopRecording: true,
      );

      await dispatcher.dispatch(signal);

      expect(callLog.entries, ['stopSession']);
      expect(toaster.messages, ['Session ended']);
      expect(haptic.callCount, 1);
    });

    test('both true: both called, resetSession before stopSession', () async {
      const signal = SessionControlSignal(
        resetSession: true,
        stopRecording: true,
      );

      await dispatcher.dispatch(signal);

      expect(callLog.entries, ['resetSession', 'stopSession']);
      expect(toaster.messages, ['New conversation', 'Session ended']);
      expect(haptic.callCount, 2);
    });

    test('noop: no calls, no toast, no haptic, no TTS wait', () async {
      // Set TTS speaking to verify it is NOT observed for noop.
      tts.setSpeaking(true);

      const signal = SessionControlSignal(
        resetSession: false,
        stopRecording: false,
      );

      await dispatcher.dispatch(signal);

      expect(callLog.entries, isEmpty);
      expect(toaster.messages, isEmpty);
      expect(haptic.callCount, 0);

      // TTS is still speaking -- dispatcher did not wait.
      expect(tts.isSpeaking.value, isTrue);
    });

    test('TTS not speaking: signal applies immediately', () async {
      // isSpeaking starts false by default.
      const signal = SessionControlSignal(
        resetSession: true,
        stopRecording: false,
      );

      final stopwatch = Stopwatch()..start();
      await dispatcher.dispatch(signal);
      stopwatch.stop();

      expect(callLog.entries, ['resetSession']);
      // Should complete well before the 200ms timeout.
      expect(stopwatch.elapsedMilliseconds, lessThan(100));
    });

    test('TTS stuck (isSpeaking stays true > timeout): '
        'signal applies after timeout', () async {
      tts.setSpeaking(true);

      const signal = SessionControlSignal(
        resetSession: true,
        stopRecording: false,
      );

      final stopwatch = Stopwatch()..start();
      await dispatcher.dispatch(signal);
      stopwatch.stop();

      expect(callLog.entries, ['resetSession']);
      // Should have waited at least the timeout duration.
      expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(180));
    });

    test('TTS finishes before timeout: signal applies when TTS stops',
        () async {
      tts.setSpeaking(true);

      const signal = SessionControlSignal(
        resetSession: true,
        stopRecording: false,
      );

      // Stop TTS after a short delay.
      Timer(const Duration(milliseconds: 50), () {
        tts.setSpeaking(false);
      });

      final stopwatch = Stopwatch()..start();
      await dispatcher.dispatch(signal);
      stopwatch.stop();

      expect(callLog.entries, ['resetSession']);
      // Should complete well before the 200ms timeout.
      expect(stopwatch.elapsedMilliseconds, lessThan(150));
    });

    test('isSuspendedForManualRecording == true: '
        'stopSession skipped, toast/haptic suppressed', () async {
      handsFree.suspended = true;

      const signal = SessionControlSignal(
        resetSession: false,
        stopRecording: true,
      );

      await dispatcher.dispatch(signal);

      expect(callLog.entries, isEmpty);
      expect(toaster.messages, isEmpty);
      expect(haptic.callCount, 0);
    });

    test('isSuspendedForManualRecording == true with both signals: '
        'resetSession applies, stopSession skipped', () async {
      handsFree.suspended = true;

      const signal = SessionControlSignal(
        resetSession: true,
        stopRecording: true,
      );

      await dispatcher.dispatch(signal);

      // resetSession should still apply.
      expect(callLog.entries, ['resetSession']);
      expect(toaster.messages, ['New conversation']);
      expect(haptic.callCount, 1);
    });

    test('concurrent dispatch calls are serialized', () async {
      tts.setSpeaking(true);

      const signal1 = SessionControlSignal(
        resetSession: true,
        stopRecording: false,
      );
      const signal2 = SessionControlSignal(
        resetSession: false,
        stopRecording: true,
      );

      // Dispatch two signals concurrently.
      final future1 = dispatcher.dispatch(signal1);
      final future2 = dispatcher.dispatch(signal2);

      // TTS finishes after a short delay -- only the first dispatch
      // should see isSpeaking=true.
      Timer(const Duration(milliseconds: 50), () {
        tts.setSpeaking(false);
      });

      await Future.wait([future1, future2]);

      // Both signals applied, in order: first reset, then stop.
      expect(callLog.entries, ['resetSession', 'stopSession']);
      expect(
        toaster.messages,
        ['New conversation', 'Session ended'],
      );
      expect(haptic.callCount, 2);
    });

    test('concurrent dispatch: second waits for first to complete',
        () async {
      tts.setSpeaking(true);

      final timestamps = <String>[];

      const signal1 = SessionControlSignal(
        resetSession: true,
        stopRecording: false,
      );
      const signal2 = SessionControlSignal(
        resetSession: false,
        stopRecording: true,
      );

      final future1 = dispatcher.dispatch(signal1).then((_) {
        timestamps.add('first-done');
      });
      final future2 = dispatcher.dispatch(signal2).then((_) {
        timestamps.add('second-done');
      });

      // Let TTS timeout fire for first dispatch.
      await Future.wait([future1, future2]);

      // First must complete before second.
      expect(timestamps, ['first-done', 'second-done']);
    });

    test('dispatch error does not break the chain', () async {
      // Create a dispatcher with a handler that throws on first call.
      var throwOnce = true;
      final throwingCoordinator = _ThrowingSessionIdCoordinator(
        coordinator,
        () {
          if (throwOnce) {
            throwOnce = false;
            throw Exception('test error');
          }
        },
      );

      final errorDispatcher = SessionControlDispatcher(
        ttsService: tts,
        handsFreeControlPort: handsFree,
        sessionIdCoordinator: throwingCoordinator,
        toaster: toaster,
        hapticService: haptic,
        ttsTimeout: const Duration(milliseconds: 200),
      );

      const signal = SessionControlSignal(
        resetSession: true,
        stopRecording: false,
      );

      // First dispatch -- the error is caught internally.
      await errorDispatcher.dispatch(signal);

      // Second dispatch should still work.
      await errorDispatcher.dispatch(signal);

      // The second call succeeded (no throw), so toast should appear.
      expect(toaster.messages, ['New conversation']);
    });
  });
}

// -- Logging wrappers for ordering assertions --------------------------------

class _LoggingSessionIdCoordinator extends SessionIdCoordinator {
  _LoggingSessionIdCoordinator(this._delegate, this._log);

  final SessionIdCoordinator _delegate;
  final _CallLog _log;

  @override
  String? get currentConversationId => _delegate.currentConversationId;

  @override
  Future<void> resetSession() async {
    _log.entries.add('resetSession');
    await _delegate.resetSession();
  }

  @override
  void adoptConversationId(String id) => _delegate.adoptConversationId(id);
}

class _LoggingHandsFreeControlPort implements HandsFreeControlPort {
  _LoggingHandsFreeControlPort(this._delegate, this._log);

  final _FakeHandsFreeControlPort _delegate;
  final _CallLog _log;

  @override
  bool get isSuspendedForManualRecording =>
      _delegate.isSuspendedForManualRecording;

  @override
  Future<void> stopSession() async {
    _log.entries.add('stopSession');
    await _delegate.stopSession();
  }
}

class _ThrowingSessionIdCoordinator extends SessionIdCoordinator {
  _ThrowingSessionIdCoordinator(this._delegate, this._onReset);

  final SessionIdCoordinator _delegate;
  final void Function() _onReset;

  @override
  String? get currentConversationId => _delegate.currentConversationId;

  @override
  Future<void> resetSession() async {
    _onReset();
    await _delegate.resetSession();
  }

  @override
  void adoptConversationId(String id) => _delegate.adoptConversationId(id);
}
