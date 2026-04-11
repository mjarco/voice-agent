import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/app/app.dart';
import 'package:voice_agent/core/config/app_config.dart';
import 'package:voice_agent/core/config/app_config_provider.dart';
import 'package:voice_agent/core/config/app_config_service.dart';
import 'package:voice_agent/core/models/sync_queue_item.dart';
import 'package:voice_agent/core/models/transcript.dart';
import 'package:voice_agent/core/models/transcript_with_status.dart';
import 'package:voice_agent/core/network/connectivity_service.dart';
import 'package:voice_agent/core/providers/agent_reply_provider.dart';
import 'package:voice_agent/core/providers/api_url_provider.dart';
import 'package:voice_agent/core/storage/storage_provider.dart';
import 'package:voice_agent/core/storage/storage_service.dart';
import 'package:voice_agent/features/api_sync/sync_provider.dart';
import 'package:voice_agent/core/config/vad_config.dart';
import 'package:voice_agent/core/models/transcript_result.dart';
import 'package:voice_agent/features/recording/domain/hands_free_engine.dart';
import 'package:voice_agent/features/recording/domain/recording_result.dart';
import 'package:voice_agent/features/recording/domain/recording_service.dart';
import 'package:voice_agent/features/recording/domain/recording_state.dart';
import 'package:voice_agent/features/recording/domain/stt_service.dart';
import 'package:voice_agent/core/audio/audio_feedback_provider.dart';
import 'package:voice_agent/core/audio/audio_feedback_service.dart';
import 'package:voice_agent/core/tts/tts_provider.dart';
import 'package:voice_agent/core/tts/tts_service.dart';
import 'package:voice_agent/features/recording/presentation/recording_controller.dart';
import 'package:voice_agent/features/recording/presentation/recording_providers.dart';

class _StubStorage implements StorageService {
  @override Future<String> getDeviceId() async => 'test';
  @override Future<List<TranscriptWithStatus>> getTranscriptsWithStatus({int limit = 20, int offset = 0}) async => [];
  @override Future<void> saveTranscript(Transcript t) async {}
  @override Future<Transcript?> getTranscript(String id) async => null;
  @override Future<List<Transcript>> getTranscripts({int limit = 50, int offset = 0}) async => [];
  @override Future<void> deleteTranscript(String id) async {}
  @override Future<void> enqueue(String transcriptId) async {}
  @override Future<List<SyncQueueItem>> getPendingItems() async => [];
  @override Future<void> markSending(String id) async {}
  @override Future<void> markSent(String id) async {}
  @override Future<void> markFailed(String id, String error, {int? overrideAttempts}) async {}
  @override Future<void> markPendingForRetry(String id) async {}
  @override Future<void> reactivateForResend(String transcriptId) async {}
  @override Future<int> recoverStaleSending() async => 0;
  @override Future<List<SyncQueueItem>> getFailedItems({int? maxAttempts}) async => [];
}

class _NoOpConnectivity extends ConnectivityService {
  @override
  Stream<ConnectivityStatus> get statusStream => const Stream.empty();
}

class _IdleHfEngine implements HandsFreeEngine {
  final _ctrl = StreamController<HandsFreeEngineEvent>.broadcast();
  @override Future<bool> hasPermission() async => true;
  @override Stream<HandsFreeEngineEvent> start({required VadConfig config}) => _ctrl.stream;
  @override Future<void> stop() async {}
  @override Future<void> interruptCapture() async {}
  @override void dispose() => _ctrl.close();
}

class _FixedConfigService extends AppConfigService {
  _FixedConfigService(this._config);
  final AppConfig _config;
  @override
  Future<AppConfig> load() async => _config;
}

class _StubTtsService implements TtsService {
  @override Future<void> speak(String text, {String? languageCode}) async {}
  @override Future<void> stop() async {}
  @override void dispose() {}
}

class _StubAudioFeedbackService implements AudioFeedbackService {
  @override Future<void> startProcessingFeedback() async {}
  @override Future<void> stopLoop() async {}
  @override Future<void> playSuccess() async {}
  @override Future<void> playError() async {}
  @override void dispose() {}
}

List<Override> get _baseOverrides => [
  storageServiceProvider.overrideWithValue(_StubStorage()),
  connectivityServiceProvider.overrideWith((_) => _NoOpConnectivity()),
  handsFreeEngineProvider.overrideWithValue(_IdleHfEngine()),
  appConfigServiceProvider.overrideWithValue(
    _FixedConfigService(const AppConfig(groqApiKey: 'test-key')),
  ),
  ttsServiceProvider.overrideWithValue(_StubTtsService()),
  audioFeedbackServiceProvider.overrideWithValue(_StubAudioFeedbackService()),
];

void main() {
  testWidgets('Record screen shows mic button in idle state', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._baseOverrides,
          apiUrlConfiguredProvider.overrideWithValue(true),
        ],
        child: const App(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.mic), findsWidgets);
    expect(find.text('Tap to record'), findsOneWidget);
  });

  testWidgets('Record screen shows banner when API not configured',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(overrides: _baseOverrides, child: const App()),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Set up your API endpoint in Settings to sync your transcripts.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('Record screen hides banner when API configured',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._baseOverrides,
          apiUrlConfiguredProvider.overrideWithValue(true),
        ],
        child: const App(),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Set up your API endpoint in Settings to sync your transcripts.',
      ),
      findsNothing,
    );
  });

  testWidgets(
    'RecordingError(requiresAppSettings) shows "Go to Settings", hides "Open Settings"',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ..._baseOverrides,
            apiUrlConfiguredProvider.overrideWithValue(true),
            recordingControllerProvider.overrideWith(
              (ref) => _ErrorController(
                ref,
                const RecordingError('key not set', requiresAppSettings: true),
              ),
            ),
          ],
          child: const App(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Go to Settings'), findsOneWidget);
      expect(find.text('Open Settings'), findsNothing);
      expect(find.text('Try Again'), findsNothing);
    },
  );

  testWidgets(
    'RecordingError(requiresSettings) shows "Open Settings", hides "Go to Settings"',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ..._baseOverrides,
            apiUrlConfiguredProvider.overrideWithValue(true),
            recordingControllerProvider.overrideWith(
              (ref) => _ErrorController(
                ref,
                const RecordingError(
                  'permission denied',
                  requiresSettings: true,
                ),
              ),
            ),
          ],
          child: const App(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Open Settings'), findsOneWidget);
      expect(find.text('Go to Settings'), findsNothing);
      expect(find.text('Try Again'), findsNothing);
    },
  );

  testWidgets(
    'RecordingError(no flags) shows "Try Again", hides both Settings buttons',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ..._baseOverrides,
            apiUrlConfiguredProvider.overrideWithValue(true),
            recordingControllerProvider.overrideWith(
              (ref) => _ErrorController(
                ref,
                const RecordingError('something went wrong'),
              ),
            ),
          ],
          child: const App(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Try Again'), findsOneWidget);
      expect(find.text('Go to Settings'), findsNothing);
      expect(find.text('Open Settings'), findsNothing);
    },
  );

  group('Agent reply card', () {
    testWidgets('shows card when latestAgentReplyProvider is non-null',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ..._baseOverrides,
            apiUrlConfiguredProvider.overrideWithValue(true),
            latestAgentReplyProvider.overrideWith((_) => 'Agent reply text'),
          ],
          child: const App(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('agent-reply-card')), findsOneWidget);
      expect(find.text('Agent reply text'), findsOneWidget);
    });

    testWidgets('hides card when latestAgentReplyProvider is null',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ..._baseOverrides,
            apiUrlConfiguredProvider.overrideWithValue(true),
          ],
          child: const App(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('agent-reply-card')), findsNothing);
    });

    testWidgets('dismiss button clears the reply card', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ..._baseOverrides,
            apiUrlConfiguredProvider.overrideWithValue(true),
            latestAgentReplyProvider.overrideWith((_) => 'Dismiss me'),
          ],
          child: const App(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('agent-reply-card')), findsOneWidget);

      await tester.tap(find.byKey(const Key('agent-reply-dismiss')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('agent-reply-card')), findsNothing);
    });
  });
}

// ---------------------------------------------------------------------------
// Stubs needed for _ErrorController
// ---------------------------------------------------------------------------

class _NoOpRecordingService implements RecordingService {
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<void> start({required String outputPath}) async {}
  @override
  Future<RecordingResult> stop() async => RecordingResult(
        filePath: '/tmp/x.wav',
        duration: Duration.zero,
        sampleRate: 16000,
      );
  @override
  Future<void> cancel() async {}
  @override
  Stream<Duration> get elapsed => const Stream.empty();
  @override
  bool get isRecording => false;
}

class _NoOpSttService implements SttService {
  @override
  Future<bool> isModelLoaded() async => true;
  @override
  Future<void> loadModel() async {}
  @override
  Future<TranscriptResult> transcribe(String path, {String? languageCode}) =>
      Future.value(
        const TranscriptResult(
          text: '',
          segments: [],
          detectedLanguage: 'en',
          audioDurationMs: 0,
        ),
      );
}

/// Controller that starts in a fixed [RecordingError] state.
class _ErrorController extends RecordingController {
  _ErrorController(Ref ref, RecordingError error)
      : super(_NoOpRecordingService(), _NoOpSttService(), ref) {
    state = error;
  }
}
