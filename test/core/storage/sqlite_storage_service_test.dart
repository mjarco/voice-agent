import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
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
}
