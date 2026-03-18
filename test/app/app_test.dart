import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/app/app.dart';
import 'package:voice_agent/core/models/sync_queue_item.dart';
import 'package:voice_agent/core/models/transcript.dart';
import 'package:voice_agent/core/storage/storage_provider.dart';
import 'package:voice_agent/core/models/transcript_with_status.dart';
import 'package:voice_agent/core/storage/storage_service.dart';

class _StubStorageService implements StorageService {
  @override
  Future<String> getDeviceId() async => 'test-device';
  @override
  Future<List<TranscriptWithStatus>> getTranscriptsWithStatus({
    int limit = 20,
    int offset = 0,
  }) async => [];
  @override
  Future<void> saveTranscript(Transcript t) async {}
  @override
  Future<Transcript?> getTranscript(String id) async => null;
  @override
  Future<List<Transcript>> getTranscripts({int limit = 50, int offset = 0}) async => [];
  @override
  Future<void> deleteTranscript(String id) async {}
  @override
  Future<void> enqueue(String transcriptId) async {}
  @override
  Future<List<SyncQueueItem>> getPendingItems() async => [];
  @override
  Future<void> markSending(String id) async {}
  @override
  Future<void> markSent(String id) async {}
  @override
  Future<void> markFailed(String id, String error) async {}
  @override
  Future<void> markPendingForRetry(String id) async {}
}

List<Override> get _testOverrides => [
      storageServiceProvider.overrideWithValue(_StubStorageService()),
    ];

void main() {
  testWidgets('App renders with shell and 3 tabs', (tester) async {
    await tester.pumpWidget(
      ProviderScope(overrides: _testOverrides, child: const App()),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('History'), findsWidgets);
    expect(find.text('Record'), findsWidgets);
    expect(find.text('Settings'), findsWidgets);
  });

  testWidgets('Default tab is Record', (tester) async {
    await tester.pumpWidget(
      ProviderScope(overrides: _testOverrides, child: const App()),
    );
    await tester.pumpAndSettle();

    final navBar = tester.widget<NavigationBar>(
      find.byType(NavigationBar),
    );
    expect(navBar.selectedIndex, 1);
  });

  testWidgets('Tapping History tab shows History screen', (tester) async {
    await tester.pumpWidget(
      ProviderScope(overrides: _testOverrides, child: const App()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.history));
    await tester.pumpAndSettle();

    final navBar = tester.widget<NavigationBar>(
      find.byType(NavigationBar),
    );
    expect(navBar.selectedIndex, 0);
  });

  testWidgets('Tapping Settings tab shows Settings screen', (tester) async {
    await tester.pumpWidget(
      ProviderScope(overrides: _testOverrides, child: const App()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();

    final navBar = tester.widget<NavigationBar>(
      find.byType(NavigationBar),
    );
    expect(navBar.selectedIndex, 2);
  });

  testWidgets('App uses Material 3', (tester) async {
    await tester.pumpWidget(
      ProviderScope(overrides: _testOverrides, child: const App()),
    );

    final materialApp = tester.widget<MaterialApp>(
      find.byType(MaterialApp),
    );
    expect(materialApp.theme?.useMaterial3, isTrue);
  });
}
