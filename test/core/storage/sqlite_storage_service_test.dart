import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:voice_agent/core/models/sync_status.dart';
import 'package:voice_agent/core/models/transcript.dart';
import 'package:voice_agent/core/storage/sqlite_storage_service.dart';

void main() {
  late SqliteStorageService storage;
  late String dbPath;

  setUpAll(() {
    sqfliteFfiInit();
  });

  setUp(() async {
    final tempDir = Directory.systemTemp.createTempSync('voice_agent_test_');
    dbPath = '${tempDir.path}/test.db';
    storage = await SqliteStorageService.initialize(
      databaseFactory: databaseFactoryFfi,
      path: dbPath,
    );
  });

  group('Transcript CRUD', () {
    final transcript = Transcript(
      id: 'test-id-1',
      text: 'Hello world',
      language: 'en',
      audioDurationMs: 5000,
      deviceId: 'dev-1',
      createdAt: 1710000000000,
    );

    test('saveTranscript then getTranscript returns it', () async {
      await storage.saveTranscript(transcript);
      final result = await storage.getTranscript('test-id-1');

      expect(result, isNotNull);
      expect(result, equals(transcript));
    });

    test('getTranscript returns null for non-existent id', () async {
      final result = await storage.getTranscript('non-existent');
      expect(result, isNull);
    });

    test('getTranscripts returns in descending created_at order', () async {
      final t1 = Transcript(
        id: 'id-1',
        text: 'first',
        deviceId: 'dev',
        createdAt: 100,
      );
      final t2 = Transcript(
        id: 'id-2',
        text: 'second',
        deviceId: 'dev',
        createdAt: 200,
      );
      final t3 = Transcript(
        id: 'id-3',
        text: 'third',
        deviceId: 'dev',
        createdAt: 300,
      );

      await storage.saveTranscript(t1);
      await storage.saveTranscript(t2);
      await storage.saveTranscript(t3);

      final results = await storage.getTranscripts();
      expect(results.length, 3);
      expect(results[0].id, 'id-3'); // newest first
      expect(results[1].id, 'id-2');
      expect(results[2].id, 'id-1');
    });

    test('getTranscripts respects limit and offset', () async {
      for (var i = 0; i < 5; i++) {
        await storage.saveTranscript(Transcript(
          id: 'id-$i',
          text: 'text $i',
          deviceId: 'dev',
          createdAt: i * 1000,
        ));
      }

      final page1 = await storage.getTranscripts(limit: 2, offset: 0);
      expect(page1.length, 2);

      final page2 = await storage.getTranscripts(limit: 2, offset: 2);
      expect(page2.length, 2);

      final page3 = await storage.getTranscripts(limit: 2, offset: 4);
      expect(page3.length, 1);
    });

    test('deleteTranscript removes the transcript', () async {
      await storage.saveTranscript(transcript);
      await storage.deleteTranscript('test-id-1');

      final result = await storage.getTranscript('test-id-1');
      expect(result, isNull);
    });

    test('deleteTranscript cascades to sync_queue', () async {
      await storage.saveTranscript(transcript);
      await storage.enqueue('test-id-1');

      final before = await storage.getPendingItems();
      expect(before.length, 1);

      await storage.deleteTranscript('test-id-1');

      final after = await storage.getPendingItems();
      expect(after.length, 0);
    });

    test('saveTranscript with nullable fields null', () async {
      final t = Transcript(
        id: 'null-fields',
        text: 'test',
        language: null,
        audioDurationMs: null,
        deviceId: 'dev',
        createdAt: 100,
      );

      await storage.saveTranscript(t);
      final result = await storage.getTranscript('null-fields');

      expect(result, isNotNull);
      expect(result!.language, isNull);
      expect(result.audioDurationMs, isNull);
    });
  });

  group('Sync Queue State Machine', () {
    final transcript = Transcript(
      id: 'tx-1',
      text: 'test transcript',
      deviceId: 'dev',
      createdAt: 1000,
    );

    test('enqueue creates pending item with attempts 0', () async {
      await storage.saveTranscript(transcript);
      await storage.enqueue('tx-1');

      final items = await storage.getPendingItems();
      expect(items.length, 1);
      expect(items[0].transcriptId, 'tx-1');
      expect(items[0].status, SyncStatus.pending);
      expect(items[0].attempts, 0);
      expect(items[0].lastAttemptAt, isNull);
      expect(items[0].errorMessage, isNull);
    });

    test('getPendingItems returns only pending, FIFO order', () async {
      await storage.saveTranscript(transcript);
      final t2 = Transcript(
        id: 'tx-2',
        text: 'second',
        deviceId: 'dev',
        createdAt: 2000,
      );
      await storage.saveTranscript(t2);

      await storage.enqueue('tx-1');
      // Small delay to ensure different created_at
      await Future.delayed(const Duration(milliseconds: 10));
      await storage.enqueue('tx-2');

      final items = await storage.getPendingItems();
      expect(items.length, 2);
      expect(items[0].transcriptId, 'tx-1'); // first in, first out
      expect(items[1].transcriptId, 'tx-2');
    });

    test('full happy path: pending -> sending -> deleted (markSent)',
        () async {
      await storage.saveTranscript(transcript);
      await storage.enqueue('tx-1');

      var items = await storage.getPendingItems();
      final queueId = items[0].id;

      // Mark sending
      await storage.markSending(queueId);
      items = await storage.getPendingItems();
      expect(items, isEmpty); // no longer pending

      // Mark sent (deletes the row)
      await storage.markSent(queueId);
      items = await storage.getPendingItems();
      expect(items, isEmpty);

      // Transcript still exists
      final tx = await storage.getTranscript('tx-1');
      expect(tx, isNotNull);
    });

    test('failure path: pending -> sending -> failed', () async {
      await storage.saveTranscript(transcript);
      await storage.enqueue('tx-1');

      var items = await storage.getPendingItems();
      final queueId = items[0].id;

      await storage.markSending(queueId);
      await storage.markFailed(queueId, 'server timeout');

      // Not in pending anymore (status is failed)
      items = await storage.getPendingItems();
      expect(items, isEmpty);
    });

    test('retry path: failed -> pending via markPendingForRetry', () async {
      await storage.saveTranscript(transcript);
      await storage.enqueue('tx-1');

      var items = await storage.getPendingItems();
      final queueId = items[0].id;

      await storage.markSending(queueId);
      await storage.markFailed(queueId, 'error');
      await storage.markPendingForRetry(queueId);

      items = await storage.getPendingItems();
      expect(items.length, 1);
      expect(items[0].status, SyncStatus.pending);
    });

    test('markSending increments attempts counter', () async {
      await storage.saveTranscript(transcript);
      await storage.enqueue('tx-1');

      var items = await storage.getPendingItems();
      final queueId = items[0].id;
      expect(items[0].attempts, 0);

      await storage.markSending(queueId);
      await storage.markFailed(queueId, 'err');
      await storage.markPendingForRetry(queueId);

      items = await storage.getPendingItems();
      expect(items[0].attempts, 1);

      await storage.markSending(queueId);
      await storage.markFailed(queueId, 'err');
      await storage.markPendingForRetry(queueId);

      items = await storage.getPendingItems();
      expect(items[0].attempts, 2);
    });

    test('markSending sets lastAttemptAt and clears errorMessage', () async {
      await storage.saveTranscript(transcript);
      await storage.enqueue('tx-1');

      var items = await storage.getPendingItems();
      final queueId = items[0].id;

      // First: fail with error
      await storage.markSending(queueId);
      await storage.markFailed(queueId, 'some error');
      await storage.markPendingForRetry(queueId);

      // Second sending: should clear error
      await storage.markSending(queueId);
      await storage.markFailed(queueId, 'check fields');
      await storage.markPendingForRetry(queueId);

      items = await storage.getPendingItems();
      expect(items[0].lastAttemptAt, isNotNull);
    });

    test('markPendingForRetry only works on failed items', () async {
      await storage.saveTranscript(transcript);
      await storage.enqueue('tx-1');

      var items = await storage.getPendingItems();
      final queueId = items[0].id;

      // Try to retry a pending item (not failed) — should be no-op
      await storage.markPendingForRetry(queueId);

      items = await storage.getPendingItems();
      expect(items.length, 1);
      expect(items[0].status, SyncStatus.pending);
    });
  });

  group('reactivateForResend', () {
    final transcript = Transcript(
      id: 'tx-resend',
      text: 'resend test',
      deviceId: 'dev',
      createdAt: 5000,
    );

    test('reactivates failed row: resets status, attempts, error', () async {
      await storage.saveTranscript(transcript);
      await storage.enqueue('tx-resend');

      var items = await storage.getPendingItems();
      final queueId = items.first.id;

      // Simulate failure
      await storage.markSending(queueId);
      await storage.markFailed(queueId, 'server error');

      // Reactivate
      await storage.reactivateForResend('tx-resend');

      items = await storage.getPendingItems();
      expect(items.length, 1);
      expect(items.first.status, SyncStatus.pending);
      expect(items.first.attempts, 0);
      expect(items.first.errorMessage, isNull);
      expect(items.first.lastAttemptAt, isNull);
    });

    test('is no-op when transcript has pending queue item', () async {
      await storage.saveTranscript(transcript);
      await storage.enqueue('tx-resend');

      // Already pending — reactivate should be no-op
      await storage.reactivateForResend('tx-resend');

      final items = await storage.getPendingItems();
      expect(items.length, 1); // still just one
    });

    test('no duplicate rows after reactivate', () async {
      await storage.saveTranscript(transcript);
      await storage.enqueue('tx-resend');

      var items = await storage.getPendingItems();
      final queueId = items.first.id;

      await storage.markSending(queueId);
      await storage.markFailed(queueId, 'err');

      // Reactivate twice
      await storage.reactivateForResend('tx-resend');
      await storage.reactivateForResend('tx-resend');

      items = await storage.getPendingItems();
      expect(items.length, 1, reason: 'Should never create duplicates');
    });
  });

  group('recoverStaleSending', () {
    final transcript = Transcript(
      id: 'tx-stale',
      text: 'stale test',
      deviceId: 'dev',
      createdAt: 1000,
    );

    test('resets sending items to pending', () async {
      await storage.saveTranscript(transcript);
      await storage.enqueue('tx-stale');

      final items = await storage.getPendingItems();
      final queueId = items.first.id;

      await storage.markSending(queueId);

      // Verify it's no longer pending
      expect(await storage.getPendingItems(), isEmpty);

      // Recover
      final count = await storage.recoverStaleSending();
      expect(count, 1);

      // Now it's pending again
      final recovered = await storage.getPendingItems();
      expect(recovered.length, 1);
      expect(recovered.first.status, SyncStatus.pending);
      expect(recovered.first.errorMessage, isNull);
    });

    test('does not affect pending or failed items', () async {
      await storage.saveTranscript(transcript);
      final t2 = Transcript(id: 'tx-2', text: 'two', deviceId: 'dev', createdAt: 2000);
      final t3 = Transcript(id: 'tx-3', text: 'three', deviceId: 'dev', createdAt: 3000);
      await storage.saveTranscript(t2);
      await storage.saveTranscript(t3);

      await storage.enqueue('tx-stale'); // will stay pending
      await storage.enqueue('tx-2'); // will become failed
      await storage.enqueue('tx-3'); // will become sending (target for recovery)

      final items = await storage.getPendingItems();
      // Mark tx-2 as failed
      final q2 = items.firstWhere((i) => i.transcriptId == 'tx-2');
      await storage.markSending(q2.id);
      await storage.markFailed(q2.id, 'err');

      // Mark tx-3 as sending
      final items2 = await storage.getPendingItems();
      final q3 = items2.firstWhere((i) => i.transcriptId == 'tx-3');
      await storage.markSending(q3.id);

      final count = await storage.recoverStaleSending();
      expect(count, 1); // only tx-3

      // tx-stale still pending (unchanged)
      final pending = await storage.getPendingItems();
      expect(pending.length, 2); // tx-stale (original) + tx-3 (recovered)
    });

    test('returns 0 when no sending items exist', () async {
      await storage.saveTranscript(transcript);
      await storage.enqueue('tx-stale');

      final count = await storage.recoverStaleSending();
      expect(count, 0);
    });
  });
}
