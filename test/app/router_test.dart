import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/app/app.dart';
import 'package:voice_agent/core/models/sync_queue_item.dart';
import 'package:voice_agent/core/models/transcript.dart';
import 'package:voice_agent/core/models/transcript_with_status.dart';
import 'package:voice_agent/core/storage/storage_provider.dart';
import 'package:voice_agent/core/storage/storage_service.dart';
import 'package:voice_agent/core/background/background_service_provider.dart';
import 'package:voice_agent/core/models/agenda.dart';
import 'package:voice_agent/core/models/routine.dart';
import 'package:voice_agent/features/agenda/domain/agenda_repository.dart';
import 'package:voice_agent/features/agenda/presentation/agenda_providers.dart';

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

class _StubAgendaRepository implements AgendaRepository {
  @override
  Future<AgendaResponse> fetchAgenda(String date) async => AgendaResponse(
        date: date,
        granularity: 'day',
        from: date,
        to: date,
        items: [],
        routineItems: [],
      );
  @override
  Future<CachedAgenda?> getCachedAgenda(String date) async => null;
  @override
  Future<void> cacheAgenda(String date, AgendaResponse response) async {}
  @override
  Future<void> markActionItemDone(String recordId) async {}
  @override
  Future<void> updateOccurrenceStatus(
    String routineId,
    String occurrenceId,
    OccurrenceStatus status,
  ) async {}
}

void main() {
  final overrides = [
    storageServiceProvider.overrideWithValue(_StubStorageService()),
    backgroundServiceProvider.overrideWithValue(StubBackgroundService()),
    agendaRepositoryProvider.overrideWithValue(_StubAgendaRepository()),
  ];

  group('5-tab navigation', () {
    testWidgets('initial location is /record (center tab)', (tester) async {
      await tester.pumpWidget(
        ProviderScope(overrides: overrides, child: const App()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Record'), findsWidgets);

      final navBar = tester.widget<NavigationBar>(
        find.byType(NavigationBar),
      );
      expect(navBar.selectedIndex, 2);
    });

    testWidgets('all 5 tab destinations render', (tester) async {
      await tester.pumpWidget(
        ProviderScope(overrides: overrides, child: const App()),
      );
      await tester.pumpAndSettle();

      final navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(navBar.destinations.length, 5);
    });

    testWidgets('switching tabs preserves state (indexedStack)', (tester) async {
      await tester.pumpWidget(
        ProviderScope(overrides: overrides, child: const App()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Record'), findsWidgets);

      await tester.tap(find.byIcon(Icons.calendar_today));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.mic));
      await tester.pumpAndSettle();

      final navBar = tester.widget<NavigationBar>(
        find.byType(NavigationBar),
      );
      expect(navBar.selectedIndex, 2);
    });
  });
}
