import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:voice_agent/core/session_control/hands_free_control_port.dart';
import 'package:voice_agent/core/session_control/haptic_service.dart';
import 'package:voice_agent/core/session_control/session_control_signal.dart';
import 'package:voice_agent/core/session_control/session_id_coordinator.dart';
import 'package:voice_agent/core/session_control/toaster.dart';
import 'package:voice_agent/core/tts/tts_service.dart';

/// Dispatches [SessionControlSignal]s after TTS finishes, applying
/// `resetSession` then `stopRecording` in canonical order (P049 section 5).
///
/// Concurrent [dispatch] calls are serialized via an internal Future
/// chain so a second call waits for the first to settle.
class SessionControlDispatcher {
  SessionControlDispatcher({
    required TtsService ttsService,
    required HandsFreeControlPort handsFreeControlPort,
    required SessionIdCoordinator sessionIdCoordinator,
    required Toaster toaster,
    required HapticService hapticService,
    Duration ttsTimeout = const Duration(seconds: 3),
  })  : _ttsService = ttsService,
        _handsFreeControlPort = handsFreeControlPort,
        _sessionIdCoordinator = sessionIdCoordinator,
        _toaster = toaster,
        _hapticService = hapticService,
        _ttsTimeout = ttsTimeout;

  final TtsService _ttsService;
  final HandsFreeControlPort _handsFreeControlPort;
  final SessionIdCoordinator _sessionIdCoordinator;
  final Toaster _toaster;
  final HapticService _hapticService;
  final Duration _ttsTimeout;

  /// Internal Future chain for serializing concurrent dispatch calls.
  Future<void> _chain = Future.value();

  /// Single entry point. When [signal.isNoop], returns early without
  /// waiting for TTS and without firing toast/haptic.
  Future<void> dispatch(SessionControlSignal signal) {
    if (signal.isNoop) {
      debugPrint(
        '[SessionControlDispatcher] noop signal received, skipping',
      );
      return Future.value();
    }
    _chain = _chain.then((_) => _dispatchImpl(signal));
    return _chain;
  }

  Future<void> _dispatchImpl(SessionControlSignal signal) async {
    try {
      await _waitForTtsToFinish();

      // Canonical order (P049 section 5): reset first, then stop.
      if (signal.resetSession) {
        await _sessionIdCoordinator.resetSession();
        _toaster.show('New conversation');
        await _hapticService.lightImpact();
      }

      if (signal.stopRecording) {
        if (_handsFreeControlPort.isSuspendedForManualRecording) {
          debugPrint(
            '[SessionControlDispatcher] stopRecording skipped: '
            'user is in manual recording mode',
          );
        } else {
          await _handsFreeControlPort.stopSession();
          _toaster.show('Session ended');
          await _hapticService.lightImpact();
        }
      }
    } catch (e) {
      debugPrint('[SessionControlDispatcher] dispatch error: $e');
    }
  }

  /// Waits for [TtsService.isSpeaking] to flip to false, or for
  /// [_ttsTimeout] -- whichever comes first.
  Future<void> _waitForTtsToFinish() async {
    if (!_ttsService.isSpeaking.value) return;

    final completer = Completer<void>();

    void listener() {
      if (!_ttsService.isSpeaking.value && !completer.isCompleted) {
        completer.complete();
      }
    }

    _ttsService.isSpeaking.addListener(listener);

    try {
      await completer.future.timeout(_ttsTimeout, onTimeout: () {
        debugPrint(
          '[SessionControlDispatcher] TTS timeout after $_ttsTimeout',
        );
      });
    } finally {
      _ttsService.isSpeaking.removeListener(listener);
    }
  }
}
