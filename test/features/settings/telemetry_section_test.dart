// P039 T5c — widget tests for the Telemetry section in
// Settings → Advanced. Overrides isDevFlavorProvider so the section
// renders regardless of which flavor `flutter test` was invoked
// with.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voice_agent/core/config/app_config.dart';
import 'package:voice_agent/core/config/app_config_provider.dart';
import 'package:voice_agent/core/config/app_config_service.dart';
import 'package:voice_agent/core/providers/flavor_provider.dart';
import 'package:voice_agent/core/storage/storage_provider.dart';
import 'package:voice_agent/core/storage/storage_service.dart';
import 'package:voice_agent/features/settings/advanced_settings_screen.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  Future<void> pump(
    WidgetTester tester, {
    bool isDev = true,
    AppConfig? initial,
    _RecordingStorage? storage,
  }) async {
    final configService = _SeededConfigService(initial ?? const AppConfig());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isDevFlavorProvider.overrideWithValue(isDev),
          appConfigServiceProvider.overrideWithValue(configService),
          storageServiceProvider.overrideWithValue(
            storage ?? _RecordingStorage(),
          ),
        ],
        child: const MaterialApp(home: AdvancedSettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('section is hidden when isDevFlavorProvider returns false',
      (tester) async {
    await pump(tester, isDev: false);
    expect(find.byKey(const Key('telemetry-enabled-toggle')), findsNothing);
    expect(find.byKey(const Key('telemetry-collector-url')), findsNothing);
  });

  testWidgets('section renders the toggle, URL field, and clear button',
      (tester) async {
    await pump(tester);
    expect(find.byKey(const Key('telemetry-enabled-toggle')), findsOneWidget);
    expect(find.byKey(const Key('telemetry-collector-url')), findsOneWidget);
    expect(find.byKey(const Key('telemetry-clear-buffer')), findsOneWidget);
    expect(find.byKey(const Key('telemetry-restart-banner')), findsNothing);
  });

  testWidgets('toggling the switch persists and shows the restart banner',
      (tester) async {
    await pump(tester);
    final toggle = find.byKey(const Key('telemetry-enabled-toggle'));
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('telemetry-restart-banner')), findsNothing);

    await tester.tap(toggle);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('telemetry-restart-banner')), findsOneWidget);
  });

  testWidgets('submitting an invalid URL shows an inline error',
      (tester) async {
    await pump(tester);
    final field = find.byKey(const Key('telemetry-collector-url'));
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();

    await tester.enterText(field, 'not a url');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.text('Invalid URL — must be absolute (http:// or https://).'),
        findsOneWidget);
    expect(find.byKey(const Key('telemetry-restart-banner')), findsNothing,
        reason: 'invalid URLs do not flip the restart flag');
  });

  testWidgets('submitting a valid URL persists and flips the restart flag',
      (tester) async {
    await pump(tester);
    final field = find.byKey(const Key('telemetry-collector-url'));
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();

    await tester.enterText(field, 'http://localhost:4318');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.text('Invalid URL — must be absolute (http:// or https://).'),
        findsNothing);
    expect(find.byKey(const Key('telemetry-restart-banner')), findsOneWidget);
  });

  testWidgets('Clear telemetry buffer button calls storage.clearTelemetryOutbox',
      (tester) async {
    final storage = _RecordingStorage();
    await pump(tester, storage: storage);
    final button = find.byKey(const Key('telemetry-clear-buffer'));
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();

    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(storage.clearCalls, 1);
    expect(find.textContaining('Cleared'), findsOneWidget);
  });
}

class _SeededConfigService extends AppConfigService {
  _SeededConfigService(this._initial);
  AppConfig _initial;

  @override
  Future<AppConfig> load() async => _initial;

  @override
  Future<void> saveDevTelemetryEnabled(bool value) async {
    _initial = _initial.copyWith(devTelemetryEnabled: value);
  }

  @override
  Future<void> saveOtelCollectorUrl(String value) async {
    _initial = _initial.copyWith(otelCollectorUrl: value);
  }
}

class _RecordingStorage
    with TelemetryStorageNoop
    implements StorageService {
  int clearCalls = 0;

  @override
  Future<int> clearTelemetryOutbox() async {
    clearCalls += 1;
    return 0;
  }

  @override
  Future<String> getDeviceId() async => 'test';
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
