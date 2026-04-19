import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/app/app.dart';
import 'package:voice_agent/core/models/sync_queue_item.dart';
import 'package:voice_agent/core/models/transcript.dart';
import 'package:voice_agent/core/network/connectivity_service.dart';
import 'package:voice_agent/features/api_sync/sync_provider.dart';
import 'package:voice_agent/core/storage/storage_provider.dart';
import 'package:voice_agent/core/models/transcript_with_status.dart';
import 'package:voice_agent/core/storage/storage_service.dart';
import 'package:voice_agent/features/activation/presentation/activation_provider.dart';
import 'package:voice_agent/core/background/background_service_provider.dart';

import '../helpers/in_memory_bridge_store.dart';
import '../helpers/stub_background_service.dart';

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
  Future<void> markFailed(String id, String error, {int? overrideAttempts}) async {}
  @override
  Future<void> markPendingForRetry(String id) async {}
  @override
  Future<void> reactivateForResend(String transcriptId) async {}
  @override
  Future<int> recoverStaleSending() async => 0;
  @override
  Future<List<SyncQueueItem>> getFailedItems({int? maxAttempts}) async => [];
}

class _NoOpConnectivity extends ConnectivityService {
  @override
  Stream<ConnectivityStatus> get statusStream => const Stream.empty();
}

List<Override> get _testOverrides => [
      storageServiceProvider.overrideWithValue(_StubStorageService()),
      connectivityServiceProvider.overrideWith((_) => _NoOpConnectivity()),
      bridgeStoreProvider.overrideWithValue(InMemoryBridgeStore()),
      backgroundServiceProvider.overrideWithValue(StubBackgroundService()),
    ];

void main() {
  testWidgets('App renders with shell and 5 tabs', (tester) async {
    await tester.pumpWidget(
      ProviderScope(overrides: _testOverrides, child: const App()),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Agenda'), findsWidgets);
    expect(find.text('Plan'), findsWidgets);
    expect(find.text('Record'), findsWidgets);
    expect(find.text('Routines'), findsWidgets);
    expect(find.text('Chat'), findsWidgets);
  });

  testWidgets('Default tab is Record (index 2)', (tester) async {
    await tester.pumpWidget(
      ProviderScope(overrides: _testOverrides, child: const App()),
    );
    await tester.pumpAndSettle();

    final navBar = tester.widget<NavigationBar>(
      find.byType(NavigationBar),
    );
    expect(navBar.selectedIndex, 2);
  });

  testWidgets('Tapping Agenda tab switches to index 0', (tester) async {
    await tester.pumpWidget(
      ProviderScope(overrides: _testOverrides, child: const App()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.calendar_today));
    await tester.pumpAndSettle();

    final navBar = tester.widget<NavigationBar>(
      find.byType(NavigationBar),
    );
    expect(navBar.selectedIndex, 0);
  });

  testWidgets('Tapping Chat tab switches to index 4', (tester) async {
    await tester.pumpWidget(
      ProviderScope(overrides: _testOverrides, child: const App()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.chat_bubble_outline));
    await tester.pumpAndSettle();

    final navBar = tester.widget<NavigationBar>(
      find.byType(NavigationBar),
    );
    expect(navBar.selectedIndex, 4);
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
