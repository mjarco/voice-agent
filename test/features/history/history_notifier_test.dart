import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/models/sync_queue_item.dart';
import 'package:voice_agent/core/models/sync_status.dart';
import 'package:voice_agent/core/models/transcript.dart';
import 'package:voice_agent/core/models/transcript_with_status.dart';
import 'package:voice_agent/core/storage/storage_service.dart';
import 'package:voice_agent/features/history/history_notifier.dart';

class FakeStorageService implements StorageService {
  List<TranscriptWithStatus> fakeItems = [];
  final List<String> deletedIds = [];
  final List<String> reactivatedIds = [];

  @override
  Future<List<TranscriptWithStatus>> getTranscriptsWithStatus({
    int limit = 20,
    int offset = 0,
  }) async {
    final end = (offset + limit).clamp(0, fakeItems.length);
    if (offset >= fakeItems.length) return [];
    return fakeItems.sublist(offset, end);
  }

  @override
  Future<void> deleteTranscript(String id) async {
    deletedIds.add(id);
    fakeItems.removeWhere((i) => i.id == id);
  }

  @override
  Future<void> reactivateForResend(String transcriptId) async {
    reactivatedIds.add(transcriptId);
  }

  // Unused methods — stub implementations
  @override
  Future<void> saveTranscript(Transcript t) async {}
  @override
  Future<Transcript?> getTranscript(String id) async => null;
  @override
  Future<List<Transcript>> getTranscripts({int limit = 50, int offset = 0}) async => [];
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
  @override
  Future<String> getDeviceId() async => 'test-device';
  @override
  Future<int> recoverStaleSending() async => 0;
}

void main() {
  late FakeStorageService storage;
  late HistoryNotifier notifier;

  setUp(() {
    storage = FakeStorageService();
    storage.fakeItems = List.generate(
      25,
      (i) => TranscriptWithStatus(
        id: 'tx-$i',
        text: 'Transcript $i',
        createdAt: DateTime.fromMillisecondsSinceEpoch(i * 1000),
        status: DisplaySyncStatus.sent,
      ),
    );
    notifier = HistoryNotifier(storage);
  });

  test('loadNextPage loads first page on construction', () async {
    // HistoryNotifier calls loadNextPage in constructor
    await Future.delayed(const Duration(milliseconds: 50));

    expect(notifier.state.items.length, 20);
    expect(notifier.state.hasMore, isTrue);
    expect(notifier.state.isLoading, isFalse);
  });

  test('loadNextPage loads second page', () async {
    await Future.delayed(const Duration(milliseconds: 50));

    await notifier.loadNextPage();

    expect(notifier.state.items.length, 25);
    expect(notifier.state.hasMore, isFalse); // only 5 items in second page
  });

  test('loadNextPage is no-op when no more items', () async {
    await Future.delayed(const Duration(milliseconds: 50));
    await notifier.loadNextPage(); // loads remaining 5
    await notifier.loadNextPage(); // should be no-op

    expect(notifier.state.items.length, 25);
    expect(notifier.state.hasMore, isFalse);
  });

  test('refresh reloads from scratch', () async {
    await Future.delayed(const Duration(milliseconds: 50));
    expect(notifier.state.items.length, 20);

    await notifier.refresh();

    expect(notifier.state.items.length, 20); // first page again
    expect(notifier.state.hasMore, isTrue);
  });

  test('deleteItem removes from list and calls storage', () async {
    await Future.delayed(const Duration(milliseconds: 50));
    final initialCount = notifier.state.items.length;

    await notifier.deleteItem('tx-0');

    expect(notifier.state.items.length, initialCount - 1);
    expect(
      notifier.state.items.any((i) => i.id == 'tx-0'),
      isFalse,
    );
    expect(storage.deletedIds, contains('tx-0'));
  });

  test('resendItem calls reactivateForResend and updates status', () async {
    storage.fakeItems[0] = TranscriptWithStatus(
      id: 'tx-0',
      text: 'Failed transcript',
      createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      status: DisplaySyncStatus.failed,
    );
    notifier = HistoryNotifier(storage);
    await Future.delayed(const Duration(milliseconds: 50));

    await notifier.resendItem('tx-0');

    expect(storage.reactivatedIds, contains('tx-0'));
    final item = notifier.state.items.firstWhere((i) => i.id == 'tx-0');
    expect(item.status, DisplaySyncStatus.pending);
  });
}
