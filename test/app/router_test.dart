import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/app/app.dart';
import 'package:voice_agent/core/models/sync_queue_item.dart';
import 'package:voice_agent/core/models/transcript.dart';
import 'package:voice_agent/core/models/transcript_with_status.dart';
import 'package:voice_agent/core/storage/storage_provider.dart';
import 'package:voice_agent/core/storage/storage_service.dart';
import 'package:voice_agent/features/activation/presentation/activation_provider.dart';
import 'package:voice_agent/core/background/background_service_provider.dart';

import '../helpers/in_memory_bridge_store.dart';
import '../helpers/stub_background_service.dart';

class _StubStorageService implements StorageService {
  @override
  Future<String> getDeviceId() async => 'test-device';
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
  Future<List<TranscriptWithStatus>> getTranscriptsWithStatus({
    int limit = 20,
    int offset = 0,
  }) async => [];
  @override
  Future<int> recoverStaleSending() async => 0;
  @override
  Future<List<SyncQueueItem>> getFailedItems({int? maxAttempts}) async => [];
}

void main() {
  final overrides = [
    storageServiceProvider.overrideWithValue(_StubStorageService()),
    bridgeStoreProvider.overrideWithValue(InMemoryBridgeStore()),
    backgroundServiceProvider.overrideWithValue(StubBackgroundService()),
  ];

  group('Tab state preservation', () {
    testWidgets('Switching tabs preserves state (indexedStack)', (tester) async {
      await tester.pumpWidget(
        ProviderScope(overrides: overrides, child: const App()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Record'), findsWidgets);

      await tester.tap(find.byIcon(Icons.history));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.mic));
      await tester.pumpAndSettle();

      final navBar = tester.widget<NavigationBar>(
        find.byType(NavigationBar),
      );
      expect(navBar.selectedIndex, 1);
    });
  });

}
