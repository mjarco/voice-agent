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
import 'package:voice_agent/features/api_sync/sync_provider.dart';

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
  @override Future<void> markFailed(String id, String error) async {}
  @override Future<void> markPendingForRetry(String id) async {}
  @override Future<void> reactivateForResend(String transcriptId) async {}
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

List<Override> _baseOverrides() => [
  storageServiceProvider.overrideWithValue(_StubStorage()),
  connectivityServiceProvider.overrideWith((_) => _NoOpConnectivity()),
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
