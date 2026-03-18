import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/models/sync_queue_item.dart';
import 'package:voice_agent/core/models/sync_status.dart';

void main() {
  group('SyncQueueItem', () {
    test('fromMap/toMap round-trip with all fields', () {
      final item = SyncQueueItem(
        id: 'q-1',
        transcriptId: 't-1',
        status: SyncStatus.failed,
        attempts: 3,
        lastAttemptAt: 1710000005000,
        errorMessage: 'timeout',
        createdAt: 1710000000000,
      );

      final map = item.toMap();
      final restored = SyncQueueItem.fromMap(map);

      expect(restored, equals(item));
    });

    test('fromMap/toMap round-trip with nullable fields null', () {
      final item = SyncQueueItem(
        id: 'q-2',
        transcriptId: 't-2',
        status: SyncStatus.pending,
        attempts: 0,
        lastAttemptAt: null,
        errorMessage: null,
        createdAt: 1710000001000,
      );

      final map = item.toMap();
      final restored = SyncQueueItem.fromMap(map);

      expect(restored, equals(item));
      expect(restored.lastAttemptAt, isNull);
      expect(restored.errorMessage, isNull);
    });

    test('status round-trips through string', () {
      for (final status in SyncStatus.values) {
        final item = SyncQueueItem(
          id: 'q-${status.name}',
          transcriptId: 't-1',
          status: status,
          attempts: 0,
          createdAt: 100,
        );

        final map = item.toMap();
        expect(map['status'], status.name);

        final restored = SyncQueueItem.fromMap(map);
        expect(restored.status, status);
      }
    });
  });

  group('SyncStatus', () {
    test('fromString parses all valid values', () {
      expect(SyncStatus.fromString('pending'), SyncStatus.pending);
      expect(SyncStatus.fromString('sending'), SyncStatus.sending);
      expect(SyncStatus.fromString('failed'), SyncStatus.failed);
    });

    test('fromString throws on invalid value', () {
      expect(
        () => SyncStatus.fromString('sent'),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => SyncStatus.fromString('unknown'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
