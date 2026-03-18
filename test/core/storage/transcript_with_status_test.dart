import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:voice_agent/core/models/sync_status.dart';
import 'package:voice_agent/core/models/transcript.dart';
import 'package:voice_agent/core/storage/sqlite_storage_service.dart';

void main() {
  late SqliteStorageService storage;

  setUpAll(() {
    sqfliteFfiInit();
  });

  setUp(() async {
    final tempDir = Directory.systemTemp.createTempSync('voice_agent_test_');
    storage = await SqliteStorageService.initialize(
      databaseFactory: databaseFactoryFfi,
      path: '${tempDir.path}/test.db',
    );
  });

  group('getTranscriptsWithStatus', () {
    test('transcript with no queue row has status sent', () async {
      await storage.saveTranscript(Transcript(
        id: 'tx-1',
        text: 'sent transcript',
        deviceId: 'dev',
        createdAt: 1000,
      ));

      final items = await storage.getTranscriptsWithStatus();
      expect(items.length, 1);
      expect(items.first.status, DisplaySyncStatus.sent);
    });

    test('transcript with pending queue row has status pending', () async {
      await storage.saveTranscript(Transcript(
        id: 'tx-2',
        text: 'pending transcript',
        deviceId: 'dev',
        createdAt: 2000,
      ));
      await storage.enqueue('tx-2');

      final items = await storage.getTranscriptsWithStatus();
      expect(items.length, 1);
      expect(items.first.status, DisplaySyncStatus.pending);
    });

    test('transcript with failed queue row has status failed', () async {
      await storage.saveTranscript(Transcript(
        id: 'tx-3',
        text: 'failed transcript',
        deviceId: 'dev',
        createdAt: 3000,
      ));
      await storage.enqueue('tx-3');

      final pending = await storage.getPendingItems();
      await storage.markSending(pending.first.id);
      await storage.markFailed(pending.first.id, 'server error');

      final items = await storage.getTranscriptsWithStatus();
      expect(items.length, 1);
      expect(items.first.status, DisplaySyncStatus.failed);
    });

    test('transcript with sending queue row has status pending', () async {
      await storage.saveTranscript(Transcript(
        id: 'tx-4',
        text: 'sending transcript',
        deviceId: 'dev',
        createdAt: 4000,
      ));
      await storage.enqueue('tx-4');

      final pending = await storage.getPendingItems();
      await storage.markSending(pending.first.id);

      final items = await storage.getTranscriptsWithStatus();
      expect(items.length, 1);
      expect(items.first.status, DisplaySyncStatus.pending);
    });

    test('returns in descending created_at order', () async {
      for (var i = 0; i < 3; i++) {
        await storage.saveTranscript(Transcript(
          id: 'tx-order-$i',
          text: 'text $i',
          deviceId: 'dev',
          createdAt: i * 1000,
        ));
      }

      final items = await storage.getTranscriptsWithStatus();
      expect(items[0].id, 'tx-order-2');
      expect(items[1].id, 'tx-order-1');
      expect(items[2].id, 'tx-order-0');
    });

    test('respects limit and offset', () async {
      for (var i = 0; i < 5; i++) {
        await storage.saveTranscript(Transcript(
          id: 'tx-page-$i',
          text: 'text $i',
          deviceId: 'dev',
          createdAt: i * 1000,
        ));
      }

      final page1 = await storage.getTranscriptsWithStatus(limit: 2, offset: 0);
      expect(page1.length, 2);

      final page2 = await storage.getTranscriptsWithStatus(limit: 2, offset: 2);
      expect(page2.length, 2);

      final page3 = await storage.getTranscriptsWithStatus(limit: 2, offset: 4);
      expect(page3.length, 1);
    });
  });
}
