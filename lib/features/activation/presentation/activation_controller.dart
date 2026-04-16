import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/core/audio/audio_feedback_service.dart';
import 'package:voice_agent/core/config/app_config_provider.dart';
import 'package:voice_agent/core/providers/activation_event.dart';
import 'package:voice_agent/core/providers/activation_providers.dart';
import 'package:voice_agent/core/providers/hands_free_session_status.dart';
import 'package:voice_agent/features/activation/domain/activation_state.dart';
import 'package:voice_agent/features/activation/domain/wake_word_service.dart';

class ActivationController extends StateNotifier<ActivationState> {
  ActivationController({
    required this.wakeWordService,
    required this.audioFeedback,
    required Ref ref,
  })  : _ref = ref,
        super(const ActivationIdle()) {
    _detectionSub = wakeWordService.detections.listen(_onDetection);
    _errorSub = wakeWordService.errors.listen(_onWakeWordError);
  }

  final WakeWordService wakeWordService;
  final AudioFeedbackService audioFeedback;
  final Ref _ref;

  StreamSubscription<int>? _detectionSub;
  StreamSubscription<WakeWordError>? _errorSub;
  Timer? _retryTimer;

  /// Start or restart wake word listening based on current config.
  Future<void> startListening() async {
    final config = _ref.read(appConfigProvider);
    if (!config.backgroundListeningEnabled) return;

    final accessKey = config.picovoiceAccessKey;
    if (accessKey == null || accessKey.isEmpty) {
      state = const ActivationError(
        message: 'Picovoice access key not configured',
        requiresSettings: true,
      );
      return;
    }

    if (!config.wakeWordEnabled) {
      // Background listening without wake word: just stay idle
      // (foreground service may still be running for other purposes)
      state = const ActivationIdle();
      return;
    }

    final keyword = config.wakeWordKeyword;
    final builtIn = BuiltInKeyword.values.where((k) => k.name == keyword);
    if (builtIn.isEmpty) {
      state = ActivationError(
        message: 'Unknown keyword: $keyword',
        requiresSettings: true,
      );
      return;
    }

    await wakeWordService.startBuiltIn(
      accessKey: accessKey,
      keywords: [builtIn.first],
      sensitivities: [config.wakeWordSensitivity],
    );

    if (wakeWordService.isListening) {
      state = ActivationListening(keyword: keyword);
    }
    // If not listening, an error was emitted via the errors stream
    // and _onWakeWordError will handle the state transition.
  }

  /// Stop wake word listening and return to idle.
  Future<void> stopListening() async {
    _retryTimer?.cancel();
    _retryTimer = null;
    await wakeWordService.stop();
    state = const ActivationIdle();
  }

  /// Toggle background activation on/off.
  Future<void> toggle() async {
    if (state is ActivationIdle || state is ActivationError) {
      await startListening();
    } else {
      await stopListening();
    }
  }

  /// Called when the hands-free session status changes.
  void onSessionStatusChanged(HandsFreeSessionStatus status) {
    switch (status) {
      case HandsFreeSessionCompletedOk():
        // Session completed — restart wake word detection.
        _ref.read(handsFreeSessionStatusProvider.notifier).state =
            const HandsFreeSessionInactive();
        startListening();
      case HandsFreeSessionFailed(message: final msg):
        _ref.read(handsFreeSessionStatusProvider.notifier).state =
            const HandsFreeSessionInactive();
        state = ActivationError(message: msg);
        _scheduleRetry();
      case HandsFreeSessionRunning():
      case HandsFreeSessionInactive():
        break;
    }
  }

  /// Called when a wake word pause is requested (manual recording).
  Future<void> onPauseRequest(Completer<void>? completer) async {
    if (completer == null) {
      // Pause cleared — resume listening if we were active.
      if (state is ActivationIdle) {
        await startListening();
      }
      return;
    }

    // Pause requested — stop Porcupine and complete the completer.
    if (state is ActivationListening) {
      await wakeWordService.stop();
      state = const ActivationIdle();
    }
    if (!completer.isCompleted) {
      completer.complete();
    }
  }

  void _onDetection(int keywordIndex) {
    if (state is! ActivationListening) return;

    // Stop Porcupine before handing off to hands-free recording.
    wakeWordService.stop();

    final keyword = (state as ActivationListening).keyword;
    state = const ActivationHandsFreeActive(
      trigger: ActivationEvent.wakeWordDetected,
    );

    // Signal to HandsFreeController via the activation event provider.
    _ref.read(activationEventProvider.notifier).state =
        ActivationEvent.wakeWordDetected;

    audioFeedback.playWakeWordAcknowledgment();

    // Log the detected keyword for debugging.
    assert(() {
      // ignore: avoid_print
      print('Wake word detected: $keyword (index: $keywordIndex)');
      return true;
    }());
  }

  void _onWakeWordError(WakeWordError error) {
    final (message, requiresSettings) = switch (error) {
      InvalidAccessKey() => ('Invalid Picovoice access key', true),
      CorruptModel(path: final p) => ('Corrupt keyword model: $p', true),
      AudioCaptureFailed(reason: final r) => ('Audio capture failed: $r', false),
      UnknownWakeWordError(message: final m) => ('Wake word error: $m', false),
    };

    state = ActivationError(
      message: message,
      requiresSettings: requiresSettings,
    );

    if (!requiresSettings) {
      _scheduleRetry();
    }
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    _retryTimer = Timer(const Duration(seconds: 5), () {
      if (state is ActivationError &&
          !(state as ActivationError).requiresSettings) {
        startListening();
      }
    });
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _detectionSub?.cancel();
    _errorSub?.cancel();
    super.dispose();
  }
}
