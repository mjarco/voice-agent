import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:voice_agent/app/app.dart';
import 'package:voice_agent/core/config/app_config.dart';
import 'package:voice_agent/core/config/app_config_provider.dart';
import 'package:voice_agent/core/config/app_config_service.dart';
import 'package:voice_agent/core/config/vad_config.dart';
import 'package:voice_agent/core/models/sync_queue_item.dart';
import 'package:voice_agent/core/models/transcript.dart';
import 'package:voice_agent/core/models/transcript_with_status.dart';
import 'package:voice_agent/core/network/connectivity_service.dart';
import 'package:voice_agent/core/providers/api_url_provider.dart';
import 'package:voice_agent/core/storage/storage_provider.dart';
import 'package:voice_agent/core/storage/storage_service.dart';
import 'package:voice_agent/features/api_sync/sync_provider.dart';
import 'package:voice_agent/features/recording/domain/hands_free_engine.dart';
import 'package:voice_agent/core/models/transcript_result.dart';
import 'package:voice_agent/features/recording/domain/recording_result.dart';
import 'package:voice_agent/features/recording/domain/recording_service.dart';
import 'package:voice_agent/features/recording/domain/stt_service.dart';
import 'package:voice_agent/features/recording/domain/vad_service.dart';
import 'package:voice_agent/features/recording/presentation/recording_providers.dart';
import 'package:voice_agent/app/router.dart';
import 'package:voice_agent/features/settings/advanced_settings_screen.dart';

// ── Stubs ─────────────────────────────────────────────────────────────────────

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
  @override Future<void> markFailed(String id, String error) async {}
  @override Future<void> markPendingForRetry(String id) async {}
  @override Future<void> reactivateForResend(String transcriptId) async {}
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
  @override void dispose() => _ctrl.close();
}

class _NoOpRecordingService implements RecordingService {
  @override Future<bool> requestPermission() async => true;
  @override Future<void> start({required String outputPath}) async {}
  @override Future<RecordingResult> stop() async =>
      RecordingResult(filePath: '/tmp/x.wav', duration: Duration.zero, sampleRate: 16000);
  @override Future<void> cancel() async {}
  @override Stream<Duration> get elapsed => const Stream.empty();
  @override bool get isRecording => false;
}

class _NoOpSttService implements SttService {
  @override Future<bool> isModelLoaded() async => true;
  @override Future<void> loadModel() async {}
  @override Future<TranscriptResult> transcribe(String path, {String? languageCode}) =>
      Completer<TranscriptResult>().future;
}

class _SeededConfigService extends AppConfigService {
  _SeededConfigService(this._config);
  final AppConfig _config;
  VadConfig? savedVadConfig;

  @override Future<AppConfig> load() async => _config;
  @override Future<void> saveApiUrl(String url) async {}
  @override Future<void> saveApiToken(String token) async {}
  @override Future<void> saveGroqApiKey(String key) async {}
  @override Future<void> saveAutoSend(bool value) async {}
  @override Future<void> saveLanguage(String language) async {}
  @override Future<void> saveKeepHistory(bool value) async {}
  @override Future<void> saveVadConfig(VadConfig config) async {
    savedVadConfig = config;
  }
}

List<Override> _baseOverrides({AppConfigService? configService}) => [
  storageServiceProvider.overrideWithValue(_StubStorage()),
  connectivityServiceProvider.overrideWith((_) => _NoOpConnectivity()),
  apiUrlConfiguredProvider.overrideWithValue(true),
  handsFreeEngineProvider.overrideWithValue(_IdleHfEngine()),
  recordingServiceProvider.overrideWithValue(_NoOpRecordingService()),
  sttServiceProvider.overrideWithValue(_NoOpSttService()),
  if (configService != null)
    appConfigServiceProvider.overrideWithValue(configService),
];

/// Pumps [AdvancedSettingsScreen] directly inside a minimal scaffold+router
/// so tests don't need to navigate through the full SettingsScreen.
Future<void> _pumpAdvanced(
  WidgetTester tester, {
  AppConfigService? configService,
}) async {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => const AdvancedSettingsScreen(),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: _baseOverrides(configService: configService),
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('SettingsScreen — Advanced VAD navigation', () {
    testWidgets(
        'tapping Advanced (VAD) tile in settings navigates to AdvancedSettingsScreen',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: _baseOverrides(),
          child: const App(),
        ),
      );
      await tester.pumpAndSettle();

      // Navigate to settings tab
      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();

      // Scroll until the tile is visible in the settings ListView
      await tester.drag(
        find.byType(ListView).last,
        const Offset(0, -400),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('advanced-vad-tile')));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('Advanced (VAD)'),
        ),
        findsOneWidget,
      );
    });
  });

  group('AdvancedSettingsScreen', () {
    testWidgets('renders default VadConfig values in sliders', (tester) async {
      await _pumpAdvanced(tester);

      expect(find.text('0.40'), findsOneWidget);
      expect(find.text('0.35'), findsOneWidget);
      expect(find.text('500ms'), findsOneWidget);
      expect(find.text('400ms'), findsOneWidget);
      expect(find.text('300ms'), findsOneWidget);
    });

    testWidgets('renders seeded VadConfig values in sliders', (tester) async {
      const seededVad = VadConfig(
        positiveSpeechThreshold: 0.6,
        negativeSpeechThreshold: 0.5,
        hangoverMs: 800,
        minSpeechMs: 600,
        preRollMs: 400,
      );
      await _pumpAdvanced(
        tester,
        configService:
            _SeededConfigService(const AppConfig(vadConfig: seededVad)),
      );

      expect(find.text('0.60'), findsOneWidget);
      expect(find.text('0.50'), findsOneWidget);
      expect(find.text('800ms'), findsOneWidget);
      expect(find.text('600ms'), findsOneWidget);
      expect(find.text('400ms'), findsOneWidget);
    });

    testWidgets('Reset to defaults button is present', (tester) async {
      await _pumpAdvanced(tester);

      expect(find.byKey(const Key('reset-defaults')), findsOneWidget);
    });

    testWidgets('Reset to defaults button calls updateVadConfig with defaults',
        (tester) async {
      const seededVad = VadConfig(
        positiveSpeechThreshold: 0.7,
        negativeSpeechThreshold: 0.6,
        hangoverMs: 1000,
        minSpeechMs: 700,
        preRollMs: 500,
      );
      final service =
          _SeededConfigService(const AppConfig(vadConfig: seededVad));
      await _pumpAdvanced(tester, configService: service);

      await tester.tap(find.byKey(const Key('reset-defaults')));
      await tester.pumpAndSettle();

      expect(service.savedVadConfig, const VadConfig.defaults());
      // UI reflects defaults immediately
      expect(find.text('0.40'), findsOneWidget);
      expect(find.text('500ms'), findsOneWidget);
    });

    testWidgets('async config load updates sliders before user edits',
        (tester) async {
      // Simulate async load: configService returns non-default values
      const seededVad = VadConfig(
        positiveSpeechThreshold: 0.65,
        negativeSpeechThreshold: 0.55,
        hangoverMs: 900,
        minSpeechMs: 650,
        preRollMs: 350,
      );
      final service =
          _SeededConfigService(const AppConfig(vadConfig: seededVad));
      await _pumpAdvanced(tester, configService: service);

      // Values from seeded config should appear (loaded async)
      expect(find.text('0.65'), findsOneWidget);
      expect(find.text('900ms'), findsOneWidget);
    });
  });

  group('_VadParamsStrip on RecordingScreen', () {
    testWidgets('VAD strip shows current VadConfig values', (tester) async {
      const seededVad = VadConfig(
        positiveSpeechThreshold: 0.55,
        negativeSpeechThreshold: 0.45,
        hangoverMs: 600,
        minSpeechMs: 500,
        preRollMs: 200,
      );
      final service =
          _SeededConfigService(const AppConfig(vadConfig: seededVad));

      await tester.pumpWidget(
        ProviderScope(
          overrides: _baseOverrides(configService: service),
          child: const App(),
        ),
      );
      // Ensure we're on the record screen regardless of prior router state.
      router.go('/record');
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('vad-params-strip')), findsOneWidget);

      final text = tester.widget<Text>(
        find.byKey(const Key('vad-params-text')),
      );
      expect(text.data, contains('0.55'));
      expect(text.data, contains('600ms'));
      expect(text.data, contains('500ms'));
      expect(text.data, contains('200ms'));
    });

    testWidgets('tapping VAD strip navigates to AdvancedSettingsScreen',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: _baseOverrides(),
          child: const App(),
        ),
      );
      router.go('/record');
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('vad-params-strip')));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('Advanced (VAD)'),
        ),
        findsOneWidget,
      );
    });
  });
}
