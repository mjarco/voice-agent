import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/app/app.dart';
import 'package:voice_agent/core/config/app_config.dart';
import 'package:voice_agent/core/config/app_config_service.dart';
import 'package:voice_agent/core/config/app_config_provider.dart';
import 'package:voice_agent/core/models/sync_queue_item.dart';
import 'package:voice_agent/core/models/transcript.dart';
import 'package:voice_agent/core/models/transcript_with_status.dart';
import 'package:voice_agent/core/network/connectivity_service.dart';
import 'package:voice_agent/core/storage/storage_provider.dart';
import 'package:voice_agent/core/storage/storage_service.dart';
import 'package:voice_agent/core/audio/audio_feedback_provider.dart';
import 'package:voice_agent/core/audio/audio_feedback_service.dart';
import 'package:voice_agent/core/tts/tts_provider.dart';
import 'package:voice_agent/core/tts/tts_service.dart';
import 'package:voice_agent/features/api_sync/sync_provider.dart';
import 'package:voice_agent/features/activation/presentation/activation_provider.dart';
import 'package:voice_agent/core/background/background_service_provider.dart';

import '../../helpers/in_memory_bridge_store.dart';
import '../../helpers/stub_background_service.dart';

class _StubStorage implements StorageService {
  @override Future<String> getDeviceId() async => 'test';
  @override Future<List<TranscriptWithStatus>> getTranscriptsWithStatus({int limit = 20, int offset = 0}) async => [];
  @override Future<void> saveTranscript(Transcript t) async {}
  @override Future<Transcript?> getTranscript(String id) async => null;
  @override Future<List<Transcript>> getTranscripts({int limit = 50, int offset = 0}) async => [];
  @override Future<void> deleteTranscript(String id) async {}
  @override Future<void> enqueue(String transcriptId) async {}
  @override Future<List<SyncQueueItem>> getPendingItems() async => []
  ;
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

/// A fake AppConfigService that returns a pre-seeded config synchronously.
class _SeededConfigService extends AppConfigService {
  _SeededConfigService(this._config);

  final AppConfig _config;

  @override
  Future<AppConfig> load() async => _config;

  @override
  Future<void> saveGroqApiKey(String key) async {}

  @override
  Future<void> saveApiUrl(String url) async {}

  @override
  Future<void> saveApiToken(String token) async {}
}

class _StubTtsService implements TtsService {
  @override ValueListenable<bool> get isSpeaking => ValueNotifier(false);
  @override Future<void> speak(String text, {String? languageCode}) async {}
  @override Future<void> stop() async {}
  @override void dispose() {}
}

class _StubAudioFeedbackService implements AudioFeedbackService {
  @override Future<void> startProcessingFeedback() async {}
  @override Future<void> stopLoop() async {}
  @override Future<void> playSuccess() async {}
  @override Future<void> playError() async {}
  @override Future<void> playWakeWordAcknowledgment() async {}
  @override void dispose() {}
}

List<Override> _baseOverrides() => [
  storageServiceProvider.overrideWithValue(_StubStorage()),
  connectivityServiceProvider.overrideWith((_) => _NoOpConnectivity()),
  ttsServiceProvider.overrideWithValue(_StubTtsService()),
  audioFeedbackServiceProvider.overrideWithValue(_StubAudioFeedbackService()),
  bridgeStoreProvider.overrideWithValue(InMemoryBridgeStore()),
  backgroundServiceProvider.overrideWithValue(StubBackgroundService()),
];

Future<void> _navigateToSettings(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.settings));
  await tester.pumpAndSettle();
}

void main() {
  group('SettingsScreen', () {
    testWidgets('Groq API Key field appears in Transcription section',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: _baseOverrides(),
          child: const App(),
        ),
      );
      await tester.pumpAndSettle();
      await _navigateToSettings(tester);

      expect(find.widgetWithText(TextField, 'Groq API Key'), findsOneWidget);
    });

    testWidgets('Groq API Key field is populated after async config load',
        (tester) async {
      final seededService = _SeededConfigService(
        const AppConfig(groqApiKey: 'gsk_test_key'),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ..._baseOverrides(),
            appConfigServiceProvider.overrideWithValue(seededService),
          ],
          child: const App(),
        ),
      );
      await tester.pumpAndSettle();
      await _navigateToSettings(tester);

      final groqField = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Groq API Key'),
      );
      expect(groqField.controller?.text, 'gsk_test_key');
    });

    testWidgets('URL and token fields are populated after async config load',
        (tester) async {
      final seededService = _SeededConfigService(
        const AppConfig(
          apiUrl: 'https://example.com',
          apiToken: 'token_123',
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ..._baseOverrides(),
            appConfigServiceProvider.overrideWithValue(seededService),
          ],
          child: const App(),
        ),
      );
      await tester.pumpAndSettle();
      await _navigateToSettings(tester);

      final urlField = tester.widget<TextField>(
        find.widgetWithText(TextField, 'API URL'),
      );
      expect(urlField.controller?.text, 'https://example.com');

      final tokenField = tester.widget<TextField>(
        find.widgetWithText(TextField, 'API Token'),
      );
      expect(tokenField.controller?.text, 'token_123');
    });

    testWidgets('ttsEnabled toggle is visible and defaults to true', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: _baseOverrides(),
          child: const App(),
        ),
      );
      await tester.pumpAndSettle();
      await _navigateToSettings(tester);

      // Scroll down to reveal the General section toggle.
      await tester.drag(find.byType(ListView).first, const Offset(0, -400));
      await tester.pumpAndSettle();

      final tile = find.byKey(const Key('tts-enabled-tile'));
      expect(tile, findsOneWidget);
      final switchTile = tester.widget<SwitchListTile>(tile);
      expect(switchTile.value, isTrue);
    });

    testWidgets('ttsEnabled toggle saves false when toggled off', (tester) async {
      bool? savedValue;
      final trackingService = _TrackingTtsConfigService(
        onSaveTtsEnabled: (v) => savedValue = v,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ..._baseOverrides(),
            appConfigServiceProvider.overrideWithValue(trackingService),
          ],
          child: const App(),
        ),
      );
      await tester.pumpAndSettle();
      await _navigateToSettings(tester);

      await tester.drag(find.byType(ListView).first, const Offset(0, -400));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('tts-enabled-tile')));
      await tester.pumpAndSettle();

      expect(savedValue, isFalse);
    });

    testWidgets('audioFeedbackEnabled toggle is visible and defaults to true', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: _baseOverrides(),
          child: const App(),
        ),
      );
      await tester.pumpAndSettle();
      await _navigateToSettings(tester);

      await tester.drag(find.byType(ListView).first, const Offset(0, -500));
      await tester.pumpAndSettle();

      final tile = find.byKey(const Key('audio-feedback-tile'));
      expect(tile, findsOneWidget);
      final switchTile = tester.widget<SwitchListTile>(tile);
      expect(switchTile.value, isTrue);
    });

    testWidgets('audioFeedbackEnabled toggle saves false when toggled off', (tester) async {
      bool? savedValue;
      final trackingService = _TrackingAudioFeedbackConfigService(
        onSaveAudioFeedbackEnabled: (v) => savedValue = v,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ..._baseOverrides(),
            appConfigServiceProvider.overrideWithValue(trackingService),
          ],
          child: const App(),
        ),
      );
      await tester.pumpAndSettle();
      await _navigateToSettings(tester);

      await tester.drag(find.byType(ListView).first, const Offset(0, -500));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('audio-feedback-tile')));
      await tester.pumpAndSettle();

      expect(savedValue, isFalse);
    });

    testWidgets('Background Activation section is visible', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: _baseOverrides(),
          child: const App(),
        ),
      );
      await tester.pumpAndSettle();
      await _navigateToSettings(tester);

      await tester.drag(find.byType(ListView).first, const Offset(0, -600));
      await tester.pumpAndSettle();

      expect(find.text('Background Activation'), findsOneWidget);
      expect(find.byKey(const Key('background-listening-tile')), findsOneWidget);
    });

    testWidgets('Background listening defaults to off', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: _baseOverrides(),
          child: const App(),
        ),
      );
      await tester.pumpAndSettle();
      await _navigateToSettings(tester);

      await tester.drag(find.byType(ListView).first, const Offset(0, -600));
      await tester.pumpAndSettle();

      final tile = tester.widget<SwitchListTile>(
          find.byKey(const Key('background-listening-tile')));
      expect(tile.value, isFalse);
    });

    testWidgets('Wake word tile is disabled when background listening is off',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: _baseOverrides(),
          child: const App(),
        ),
      );
      await tester.pumpAndSettle();
      await _navigateToSettings(tester);

      await tester.drag(find.byType(ListView).first, const Offset(0, -600));
      await tester.pumpAndSettle();

      final tile = tester.widget<SwitchListTile>(
          find.byKey(const Key('wake-word-tile')));
      expect(tile.onChanged, isNull);
    });

    testWidgets('Wake word tile is enabled when background listening is on',
        (tester) async {
      final seededService = _SeededConfigService(
        const AppConfig(backgroundListeningEnabled: true),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ..._baseOverrides(),
            appConfigServiceProvider.overrideWithValue(seededService),
          ],
          child: const App(),
        ),
      );
      await tester.pumpAndSettle();
      await _navigateToSettings(tester);

      await tester.drag(find.byType(ListView).first, const Offset(0, -600));
      await tester.pumpAndSettle();

      final tile = tester.widget<SwitchListTile>(
          find.byKey(const Key('wake-word-tile')));
      expect(tile.onChanged, isNotNull);
    });

    testWidgets('Sensitivity slider is visible when wake word enabled',
        (tester) async {
      final seededService = _SeededConfigService(
        const AppConfig(
          backgroundListeningEnabled: true,
          wakeWordEnabled: true,
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ..._baseOverrides(),
            appConfigServiceProvider.overrideWithValue(seededService),
          ],
          child: const App(),
        ),
      );
      await tester.pumpAndSettle();
      await _navigateToSettings(tester);

      await tester.drag(find.byType(ListView).first, const Offset(0, -900));
      await tester.pumpAndSettle();

      final slider = find.byKey(const Key('wake-word-sensitivity-slider'));
      expect(slider, findsOneWidget);
      final sliderWidget = tester.widget<Slider>(slider);
      expect(sliderWidget.value, 0.5);
      expect(sliderWidget.onChanged, isNotNull);
    });

    testWidgets('Picovoice access key field is visible and persists on blur',
        (tester) async {
      String? savedKey;
      final trackingService = _TrackingWakeWordConfigService(
        onSavePicovoiceAccessKey: (k) => savedKey = k,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ..._baseOverrides(),
            appConfigServiceProvider.overrideWithValue(trackingService),
          ],
          child: const App(),
        ),
      );
      await tester.pumpAndSettle();
      await _navigateToSettings(tester);

      await tester.drag(find.byType(ListView).first, const Offset(0, -700));
      await tester.pumpAndSettle();

      final field = find.byKey(const Key('picovoice-key-field'));
      expect(field, findsOneWidget);

      await tester.tap(field);
      await tester.pump();
      await tester.enterText(field, 'test-access-key');

      // Programmatically unfocus to trigger the Focus.onFocusChange callback
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();

      expect(savedKey, 'test-access-key');
    });

    testWidgets('Groq API Key field saves on focus lost', (tester) async {
      String? savedKey;
      final trackingService = _TrackingConfigService(
        onSaveGroqApiKey: (k) => savedKey = k,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ..._baseOverrides(),
            appConfigServiceProvider.overrideWithValue(trackingService),
          ],
          child: const App(),
        ),
      );
      await tester.pumpAndSettle();
      await _navigateToSettings(tester);

      await tester.tap(find.widgetWithText(TextField, 'Groq API Key'));
      await tester.pump();
      await tester.enterText(
        find.widgetWithText(TextField, 'Groq API Key'),
        'gsk_new_key',
      );

      // Move focus away to trigger focus-lost save
      await tester.tap(find.widgetWithText(TextField, 'API Token'));
      await tester.pump();

      expect(savedKey, 'gsk_new_key');
    });
  });
}

class _TrackingConfigService extends AppConfigService {
  _TrackingConfigService({required this.onSaveGroqApiKey});

  final void Function(String) onSaveGroqApiKey;

  @override
  Future<AppConfig> load() async => const AppConfig();

  @override
  Future<void> saveGroqApiKey(String key) async => onSaveGroqApiKey(key);

  @override
  Future<void> saveApiUrl(String url) async {}

  @override
  Future<void> saveApiToken(String token) async {}
}

class _TrackingTtsConfigService extends AppConfigService {
  _TrackingTtsConfigService({required this.onSaveTtsEnabled});

  final void Function(bool) onSaveTtsEnabled;

  @override
  Future<AppConfig> load() async => const AppConfig();

  @override
  Future<void> saveTtsEnabled(bool value) async => onSaveTtsEnabled(value);
}

class _TrackingAudioFeedbackConfigService extends AppConfigService {
  _TrackingAudioFeedbackConfigService({required this.onSaveAudioFeedbackEnabled});

  final void Function(bool) onSaveAudioFeedbackEnabled;

  @override
  Future<AppConfig> load() async => const AppConfig();

  @override
  Future<void> saveAudioFeedbackEnabled(bool value) async =>
      onSaveAudioFeedbackEnabled(value);
}

class _TrackingWakeWordConfigService extends AppConfigService {
  _TrackingWakeWordConfigService({
    this.onSavePicovoiceAccessKey,
  });

  final void Function(String)? onSavePicovoiceAccessKey;

  @override
  Future<AppConfig> load() async => const AppConfig();

  @override
  Future<void> savePicovoiceAccessKey(String key) async =>
      onSavePicovoiceAccessKey?.call(key);
}
