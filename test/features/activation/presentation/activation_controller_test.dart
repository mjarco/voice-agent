import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/audio/audio_feedback_provider.dart';
import 'package:voice_agent/core/audio/audio_feedback_service.dart';
import 'package:voice_agent/core/config/app_config.dart';
import 'package:voice_agent/core/config/app_config_provider.dart';
import 'package:voice_agent/core/config/app_config_service.dart';
import 'package:voice_agent/core/providers/activation_event.dart';
import 'package:voice_agent/core/providers/activation_providers.dart';
import 'package:voice_agent/core/providers/hands_free_session_status.dart';
import 'package:voice_agent/features/activation/domain/activation_state.dart';
import 'package:voice_agent/features/activation/domain/wake_word_service.dart';
import 'package:voice_agent/features/activation/presentation/activation_provider.dart';
import 'package:voice_agent/features/activation/presentation/wake_word_provider.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class FakeWakeWordService implements WakeWordService {
  bool _listening = false;
  final _detectionsController = StreamController<int>.broadcast();
  final _errorsController = StreamController<WakeWordError>.broadcast();

  String? lastAccessKey;
  List<BuiltInKeyword>? lastKeywords;
  List<double>? lastSensitivities;
  int startCallCount = 0;
  int stopCallCount = 0;

  @override
  Stream<int> get detections => _detectionsController.stream;

  @override
  Stream<WakeWordError> get errors => _errorsController.stream;

  @override
  bool get isListening => _listening;

  @override
  Future<void> startBuiltIn({
    required String accessKey,
    required List<BuiltInKeyword> keywords,
    required List<double> sensitivities,
  }) async {
    startCallCount++;
    lastAccessKey = accessKey;
    lastKeywords = keywords;
    lastSensitivities = sensitivities;
    _listening = true;
  }

  @override
  Future<void> startCustom({
    required String accessKey,
    required List<String> keywordPaths,
    required List<double> sensitivities,
  }) async {
    startCallCount++;
    _listening = true;
  }

  @override
  Future<void> stop() async {
    stopCallCount++;
    _listening = false;
  }

  @override
  void dispose() {
    _detectionsController.close();
    _errorsController.close();
  }

  void emitDetection(int index) => _detectionsController.add(index);
  void emitError(WakeWordError error) => _errorsController.add(error);
}

class FakeAudioFeedbackService implements AudioFeedbackService {
  int wakeWordAckCount = 0;

  @override
  Future<void> playWakeWordAcknowledgment() async => wakeWordAckCount++;
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

class FakeAppConfigService extends AppConfigService {
  FakeAppConfigService(this._config);
  final AppConfig _config;

  @override
  Future<AppConfig> load() async => _config;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

AppConfig _defaultConfig({
  bool backgroundListeningEnabled = true,
  bool wakeWordEnabled = true,
  String? picovoiceAccessKey = 'test-key',
  String wakeWordKeyword = 'jarvis',
  double wakeWordSensitivity = 0.5,
}) =>
    AppConfig(
      backgroundListeningEnabled: backgroundListeningEnabled,
      wakeWordEnabled: wakeWordEnabled,
      picovoiceAccessKey: picovoiceAccessKey,
      wakeWordKeyword: wakeWordKeyword,
      wakeWordSensitivity: wakeWordSensitivity,
    );

Future<({ProviderContainer container, FakeWakeWordService wakeWord, FakeAudioFeedbackService audio})>
    _setup({AppConfig? config}) async {
  final wakeWord = FakeWakeWordService();
  final audio = FakeAudioFeedbackService();
  final container = ProviderContainer(
    overrides: [
      appConfigServiceProvider.overrideWithValue(
        FakeAppConfigService(config ?? _defaultConfig()),
      ),
      wakeWordServiceProvider.overrideWithValue(wakeWord),
      audioFeedbackServiceProvider.overrideWithValue(audio),
    ],
  );
  // Wait for async config to load before creating the controller.
  await container.read(appConfigProvider.notifier).loadCompleted;
  // Force creation of the controller so stream subscriptions are active.
  container.read(activationControllerProvider);
  return (container: container, wakeWord: wakeWord, audio: audio);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('ActivationController', () {
    test('initial state is idle', () async {
      final s = await _setup();
      addTearDown(s.container.dispose);

      final state = s.container.read(activationControllerProvider);
      expect(state, isA<ActivationIdle>());
    });

    test('startListening transitions to Listening', () async {
      final s = await _setup();
      addTearDown(s.container.dispose);
      final notifier =
          s.container.read(activationControllerProvider.notifier);

      await notifier.startListening();

      expect(s.container.read(activationControllerProvider),
          isA<ActivationListening>());
      final listening = s.container.read(activationControllerProvider)
          as ActivationListening;
      expect(listening.keyword, 'jarvis');
      expect(s.wakeWord.lastAccessKey, 'test-key');
      expect(s.wakeWord.lastKeywords, [BuiltInKeyword.jarvis]);
      expect(s.wakeWord.lastSensitivities, [0.5]);
    });

    test('startListening with missing access key transitions to Error',
        () async {
      final s =
          await _setup(config: _defaultConfig(picovoiceAccessKey: null));
      addTearDown(s.container.dispose);
      final notifier =
          s.container.read(activationControllerProvider.notifier);

      await notifier.startListening();

      final state = s.container.read(activationControllerProvider);
      expect(state, isA<ActivationError>());
      expect((state as ActivationError).requiresSettings, isTrue);
    });

    test('startListening with empty access key transitions to Error',
        () async {
      final s = await _setup(config: _defaultConfig(picovoiceAccessKey: ''));
      addTearDown(s.container.dispose);
      final notifier =
          s.container.read(activationControllerProvider.notifier);

      await notifier.startListening();

      final state = s.container.read(activationControllerProvider);
      expect(state, isA<ActivationError>());
      expect((state as ActivationError).requiresSettings, isTrue);
    });

    test('startListening when background disabled stays idle', () async {
      final s = await _setup(
          config: _defaultConfig(backgroundListeningEnabled: false));
      addTearDown(s.container.dispose);
      final notifier =
          s.container.read(activationControllerProvider.notifier);

      await notifier.startListening();

      expect(s.container.read(activationControllerProvider),
          isA<ActivationIdle>());
      expect(s.wakeWord.startCallCount, 0);
    });

    test('startListening when wake word disabled stays idle', () async {
      final s =
          await _setup(config: _defaultConfig(wakeWordEnabled: false));
      addTearDown(s.container.dispose);
      final notifier =
          s.container.read(activationControllerProvider.notifier);

      await notifier.startListening();

      expect(s.container.read(activationControllerProvider),
          isA<ActivationIdle>());
    });

    test('stopListening transitions to Idle', () async {
      final s = await _setup();
      addTearDown(s.container.dispose);
      final notifier =
          s.container.read(activationControllerProvider.notifier);

      await notifier.startListening();
      expect(s.container.read(activationControllerProvider),
          isA<ActivationListening>());

      await notifier.stopListening();

      expect(s.container.read(activationControllerProvider),
          isA<ActivationIdle>());
      expect(s.wakeWord.stopCallCount, 1);
    });

    test('toggle starts when idle', () async {
      final s = await _setup();
      addTearDown(s.container.dispose);
      final notifier =
          s.container.read(activationControllerProvider.notifier);

      await notifier.toggle();

      expect(s.container.read(activationControllerProvider),
          isA<ActivationListening>());
    });

    test('toggle stops when listening', () async {
      final s = await _setup();
      addTearDown(s.container.dispose);
      final notifier =
          s.container.read(activationControllerProvider.notifier);

      await notifier.startListening();
      await notifier.toggle();

      expect(s.container.read(activationControllerProvider),
          isA<ActivationIdle>());
    });

    test('wake word detection transitions to HandsFreeActive', () async {
      final s = await _setup();
      addTearDown(s.container.dispose);
      final notifier =
          s.container.read(activationControllerProvider.notifier);

      await notifier.startListening();
      s.wakeWord.emitDetection(0);
      await Future.delayed(Duration.zero);

      final state = s.container.read(activationControllerProvider);
      expect(state, isA<ActivationHandsFreeActive>());
      expect(
        (state as ActivationHandsFreeActive).trigger,
        ActivationEvent.wakeWordDetected,
      );
      expect(s.wakeWord.stopCallCount, 1);
    });

    test('detection sets activationEventProvider', () async {
      final s = await _setup();
      addTearDown(s.container.dispose);
      final notifier =
          s.container.read(activationControllerProvider.notifier);

      await notifier.startListening();
      s.wakeWord.emitDetection(0);
      await Future.delayed(Duration.zero);

      expect(s.container.read(activationEventProvider),
          ActivationEvent.wakeWordDetected);
    });

    test('detection plays acknowledgment tone', () async {
      final s = await _setup();
      addTearDown(s.container.dispose);
      final notifier =
          s.container.read(activationControllerProvider.notifier);

      await notifier.startListening();
      s.wakeWord.emitDetection(0);
      await Future.delayed(Duration.zero);

      expect(s.audio.wakeWordAckCount, 1);
    });

    test('detection ignored when not listening', () async {
      final s = await _setup();
      addTearDown(s.container.dispose);

      s.wakeWord.emitDetection(0);
      await Future.delayed(Duration.zero);

      expect(s.container.read(activationControllerProvider),
          isA<ActivationIdle>());
      expect(s.audio.wakeWordAckCount, 0);
    });

    group('session status', () {
      test('CompletedOk restarts listening', () async {
        final s = await _setup();
        addTearDown(s.container.dispose);
        final notifier =
            s.container.read(activationControllerProvider.notifier);

        await notifier.startListening();
        s.wakeWord.emitDetection(0);
        await Future.delayed(Duration.zero);
        expect(s.container.read(activationControllerProvider),
            isA<ActivationHandsFreeActive>());

        notifier
            .onSessionStatusChanged(const HandsFreeSessionCompletedOk());
        await Future.delayed(Duration.zero);

        expect(s.container.read(activationControllerProvider),
            isA<ActivationListening>());
      });

      test('Failed transitions to error', () async {
        final s = await _setup();
        addTearDown(s.container.dispose);
        final notifier =
            s.container.read(activationControllerProvider.notifier);

        await notifier.startListening();
        s.wakeWord.emitDetection(0);
        await Future.delayed(Duration.zero);

        notifier.onSessionStatusChanged(
          const HandsFreeSessionFailed(message: 'transcription error'),
        );

        final state = s.container.read(activationControllerProvider);
        expect(state, isA<ActivationError>());
        expect((state as ActivationError).message, 'transcription error');
      });

      test('Running and Inactive are ignored', () async {
        final s = await _setup();
        addTearDown(s.container.dispose);
        final notifier =
            s.container.read(activationControllerProvider.notifier);

        await notifier.startListening();
        final beforeState =
            s.container.read(activationControllerProvider);

        notifier
            .onSessionStatusChanged(const HandsFreeSessionRunning());
        expect(s.container.read(activationControllerProvider),
            beforeState);

        notifier
            .onSessionStatusChanged(const HandsFreeSessionInactive());
        expect(s.container.read(activationControllerProvider),
            beforeState);
      });
    });

    group('pause request', () {
      test('non-null Completer stops wake word and completes', () async {
        final s = await _setup();
        addTearDown(s.container.dispose);
        final notifier =
            s.container.read(activationControllerProvider.notifier);

        await notifier.startListening();
        expect(s.container.read(activationControllerProvider),
            isA<ActivationListening>());

        final completer = Completer<void>();
        await notifier.onPauseRequest(completer);

        expect(s.container.read(activationControllerProvider),
            isA<ActivationIdle>());
        expect(completer.isCompleted, isTrue);
        expect(s.wakeWord.stopCallCount, 1);
      });

      test('null Completer restarts listening', () async {
        final s = await _setup();
        addTearDown(s.container.dispose);
        final notifier =
            s.container.read(activationControllerProvider.notifier);

        await notifier.startListening();
        final completer = Completer<void>();
        await notifier.onPauseRequest(completer);
        expect(s.container.read(activationControllerProvider),
            isA<ActivationIdle>());

        await notifier.onPauseRequest(null);

        expect(s.container.read(activationControllerProvider),
            isA<ActivationListening>());
      });

      test('completer completes immediately when idle', () async {
        final s = await _setup();
        addTearDown(s.container.dispose);
        final notifier =
            s.container.read(activationControllerProvider.notifier);

        final completer = Completer<void>();
        await notifier.onPauseRequest(completer);

        expect(completer.isCompleted, isTrue);
        expect(s.wakeWord.stopCallCount, 0);
      });
    });

    group('error handling', () {
      test('InvalidAccessKey transitions to Error with requiresSettings',
          () async {
        final s = await _setup();
        addTearDown(s.container.dispose);
        final notifier =
            s.container.read(activationControllerProvider.notifier);

        await notifier.startListening();
        s.wakeWord.emitError(const InvalidAccessKey());
        await Future.delayed(Duration.zero);

        final state = s.container.read(activationControllerProvider);
        expect(state, isA<ActivationError>());
        expect((state as ActivationError).requiresSettings, isTrue);
      });

      test('AudioCaptureFailed transitions to Error without requiresSettings',
          () async {
        final s = await _setup();
        addTearDown(s.container.dispose);
        final notifier =
            s.container.read(activationControllerProvider.notifier);

        await notifier.startListening();
        s.wakeWord
            .emitError(const AudioCaptureFailed(reason: 'mic unavailable'));
        await Future.delayed(Duration.zero);

        final state = s.container.read(activationControllerProvider);
        expect(state, isA<ActivationError>());
        expect((state as ActivationError).requiresSettings, isFalse);
      });

      test('unknown keyword transitions to Error with requiresSettings',
          () async {
        final s = await _setup(
            config: _defaultConfig(wakeWordKeyword: 'nonexistent'));
        addTearDown(s.container.dispose);
        final notifier =
            s.container.read(activationControllerProvider.notifier);

        await notifier.startListening();

        final state = s.container.read(activationControllerProvider);
        expect(state, isA<ActivationError>());
        expect((state as ActivationError).requiresSettings, isTrue);
      });
    });
  });
}
