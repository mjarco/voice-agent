import 'dart:typed_data';

import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:voice_agent/core/models/sync_queue_item.dart';
import 'package:voice_agent/core/models/transcript_with_status.dart';
import 'package:voice_agent/core/models/sync_status.dart';
import 'package:voice_agent/core/models/transcript.dart';
import 'package:voice_agent/core/observability/telemetry_outbox_row.dart';
import 'package:voice_agent/core/storage/storage_service.dart';

class SqliteStorageService implements StorageService {
  SqliteStorageService._(this._db);

  final Database _db;
  static const _uuid = Uuid();
  static const _deviceIdKey = 'device_id';

  static Future<SqliteStorageService> initialize({
    DatabaseFactory? databaseFactory,
    String? path,
  }) async {
    final factory = databaseFactory ?? databaseFactoryDefault;
    final dbPath = path ?? join(await getDatabasesPath(), 'voice_agent.db');

    final db = await factory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 2,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: _createDb,
        onUpgrade: _onUpgrade,
      ),
    );

    return SqliteStorageService._(db);
  }

  static Future<void> _createDb(Database db, int version) async {
    await db.execute('''
      CREATE TABLE transcripts (
        id               TEXT PRIMARY KEY,
        text             TEXT NOT NULL,
        language         TEXT,
        audio_duration_ms INTEGER,
        device_id        TEXT NOT NULL,
        created_at       INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE sync_queue (
        id               TEXT PRIMARY KEY,
        transcript_id    TEXT NOT NULL,
        status           TEXT NOT NULL DEFAULT 'pending',
        attempts         INTEGER NOT NULL DEFAULT 0,
        last_attempt_at  INTEGER,
        error_message    TEXT,
        created_at       INTEGER NOT NULL,
        FOREIGN KEY (transcript_id) REFERENCES transcripts(id) ON DELETE CASCADE
      )
    ''');

    await db.execute(
      'CREATE INDEX idx_sync_queue_status ON sync_queue(status)',
    );

    await _createTelemetryOutbox(db);
  }

  /// P039 T4 — durable OTLP outbox. One row = one OTLP/JSON envelope
  /// the flush worker will POST. See `lib/core/observability/telemetry_outbox_row.dart`.
  static Future<void> _createTelemetryOutbox(Database db) async {
    await db.execute('''
      CREATE TABLE telemetry_outbox (
        id               INTEGER PRIMARY KEY AUTOINCREMENT,
        signal_kind      TEXT NOT NULL CHECK (signal_kind IN ('trace','metric')),
        payload          BLOB NOT NULL,
        created_at       INTEGER NOT NULL,
        attempts         INTEGER NOT NULL DEFAULT 0,
        next_attempt_at  INTEGER NOT NULL DEFAULT 0,
        claimed_at       INTEGER,
        last_error       TEXT
      )
    ''');
    await db.execute('''
      CREATE INDEX telemetry_outbox_due
        ON telemetry_outbox (signal_kind, next_attempt_at, id)
    ''');
  }

  static Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    for (var v = oldVersion + 1; v <= newVersion; v++) {
      switch (v) {
        case 2:
          await _createTelemetryOutbox(db);
        default:
          break;
      }
    }
  }

  // -- Transcripts --

  @override
  Future<void> saveTranscript(Transcript transcript) async {
    await _db.insert(
      'transcripts',
      transcript.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<Transcript?> getTranscript(String id) async {
    final rows = await _db.query(
      'transcripts',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Transcript.fromMap(rows.first);
  }

  @override
  Future<List<Transcript>> getTranscripts({
    int limit = 50,
    int offset = 0,
  }) async {
    final rows = await _db.query(
      'transcripts',
      orderBy: 'created_at DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map(Transcript.fromMap).toList();
  }

  @override
  Future<List<TranscriptWithStatus>> getTranscriptsWithStatus({
    int limit = 20,
    int offset = 0,
  }) async {
    final rows = await _db.rawQuery('''
      SELECT t.id, t.text, t.created_at,
             sq.status AS sync_status
      FROM transcripts t
      LEFT JOIN sync_queue sq ON t.id = sq.transcript_id
      ORDER BY t.created_at DESC
      LIMIT ? OFFSET ?
    ''', [limit, offset]);

    return rows.map((row) {
      final syncStatus = row['sync_status'] as String?;
      DisplaySyncStatus status;
      if (syncStatus == null) {
        status = DisplaySyncStatus.sent;
      } else if (syncStatus == 'pending' || syncStatus == 'sending') {
        status = DisplaySyncStatus.pending;
      } else {
        status = DisplaySyncStatus.failed;
      }

      return TranscriptWithStatus(
        id: row['id'] as String,
        text: row['text'] as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          row['created_at'] as int,
        ),
        status: status,
      );
    }).toList();
  }

  @override
  Future<void> deleteTranscript(String id) async {
    await _db.delete(
      'transcripts',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // -- Sync Queue --

  @override
  Future<void> enqueue(String transcriptId) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.insert('sync_queue', {
      'id': _uuid.v4(),
      'transcript_id': transcriptId,
      'status': SyncStatus.pending.name,
      'attempts': 0,
      'created_at': now,
    });
  }

  @override
  Future<List<SyncQueueItem>> getPendingItems() async {
    final rows = await _db.query(
      'sync_queue',
      where: 'status = ?',
      whereArgs: [SyncStatus.pending.name],
      orderBy: 'created_at ASC',
    );
    return rows.map(SyncQueueItem.fromMap).toList();
  }

  @override
  Future<void> markSending(String id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.rawUpdate(
      '''UPDATE sync_queue
         SET status = ?, attempts = attempts + 1,
             last_attempt_at = ?, error_message = NULL
         WHERE id = ?''',
      [SyncStatus.sending.name, now, id],
    );
  }

  @override
  Future<void> markSent(String id) async {
    await _db.delete(
      'sync_queue',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<void> markFailed(String id, String error, {int? overrideAttempts}) async {
    final values = <String, Object?>{
      'status': SyncStatus.failed.name,
      'error_message': error,
    };
    if (overrideAttempts != null) {
      values['attempts'] = overrideAttempts;
    }
    await _db.update(
      'sync_queue',
      values,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<void> markPendingForRetry(String id) async {
    await _db.update(
      'sync_queue',
      {'status': SyncStatus.pending.name, 'error_message': null},
      where: 'id = ? AND status = ?',
      whereArgs: [id, SyncStatus.failed.name],
    );
  }

  @override
  Future<List<SyncQueueItem>> getFailedItems({int? maxAttempts}) async {
    final rows = await _db.query(
      'sync_queue',
      where: maxAttempts != null
          ? 'status = ? AND attempts < ?'
          : 'status = ?',
      whereArgs: maxAttempts != null
          ? [SyncStatus.failed.name, maxAttempts]
          : [SyncStatus.failed.name],
      orderBy: 'last_attempt_at ASC',
    );
    return rows.map(SyncQueueItem.fromMap).toList();
  }

  @override
  Future<void> reactivateForResend(String transcriptId) async {
    await _db.update(
      'sync_queue',
      {
        'status': SyncStatus.pending.name,
        'attempts': 0,
        'last_attempt_at': null,
        'error_message': null,
      },
      where: 'transcript_id = ? AND status = ?',
      whereArgs: [transcriptId, SyncStatus.failed.name],
    );
  }

  @override
  Future<int> recoverStaleSending() async {
    return await _db.rawUpdate(
      'UPDATE sync_queue SET status = ?, error_message = NULL '
      'WHERE status = ?',
      [SyncStatus.pending.name, SyncStatus.sending.name],
    );
  }

  // -- Device --

  @override
  Future<String> getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    var deviceId = prefs.getString(_deviceIdKey);
    if (deviceId == null) {
      deviceId = _uuid.v4();
      await prefs.setString(_deviceIdKey, deviceId);
    }
    return deviceId;
  }

  // -- Telemetry outbox (P039 T4) --

  @override
  Future<int> appendTelemetryRow({
    required TelemetrySignalKind signalKind,
    required Uint8List payload,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    return _db.transaction((txn) async {
      // Retention: drop rows older than the age cap, regardless of count.
      final ageCutoff = now - kTelemetryMaxAge.inMilliseconds;
      await txn.delete(
        'telemetry_outbox',
        where: 'created_at < ?',
        whereArgs: [ageCutoff],
      );

      // Retention: per-kind cap. Count current rows of this kind; if
      // the insert would exceed the cap, drop oldest by id until we
      // are one below the cap (room for the new row).
      final cap = kTelemetryRetentionByKind[signalKind] ?? 1000;
      final countRow = await txn.rawQuery(
        'SELECT COUNT(*) AS c FROM telemetry_outbox WHERE signal_kind = ?',
        [signalKind.dbValue],
      );
      final count = countRow.first['c']! as int;
      if (count >= cap) {
        final toDrop = (count - cap) + 1;
        final oldest = await txn.query(
          'telemetry_outbox',
          columns: ['id'],
          where: 'signal_kind = ?',
          whereArgs: [signalKind.dbValue],
          orderBy: 'id ASC',
          limit: toDrop,
        );
        final ids = oldest.map((r) => r['id']! as int).toList();
        if (ids.isNotEmpty) {
          final placeholders = List.filled(ids.length, '?').join(',');
          await txn.delete(
            'telemetry_outbox',
            where: 'id IN ($placeholders)',
            whereArgs: ids,
          );
        }
      }

      return txn.insert('telemetry_outbox', {
        'signal_kind': signalKind.dbValue,
        'payload': payload,
        'created_at': now,
        'attempts': 0,
        'next_attempt_at': 0,
        'claimed_at': null,
        'last_error': null,
      });
    });
  }

  @override
  Future<List<TelemetryOutboxRow>> claimDueTelemetryRows({int limit = 50}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    return _db.transaction((txn) async {
      // Find due, unclaimed rows. Use the index
      // (signal_kind, next_attempt_at, id).
      final due = await txn.rawQuery('''
        SELECT id FROM telemetry_outbox
        WHERE claimed_at IS NULL AND next_attempt_at <= ?
        ORDER BY id ASC
        LIMIT ?
      ''', [now, limit]);
      if (due.isEmpty) return <TelemetryOutboxRow>[];

      final ids = due.map((r) => r['id']! as int).toList();
      final placeholders = List.filled(ids.length, '?').join(',');

      // Claim them atomically.
      await txn.rawUpdate(
        'UPDATE telemetry_outbox SET claimed_at = ? '
        'WHERE id IN ($placeholders)',
        [now, ...ids],
      );

      // Re-read the now-claimed rows (full row data).
      final rows = await txn.query(
        'telemetry_outbox',
        where: 'id IN ($placeholders)',
        whereArgs: ids,
        orderBy: 'id ASC',
      );
      return rows.map(TelemetryOutboxRow.fromMap).toList();
    });
  }

  @override
  Future<int> deleteTelemetryRows(List<int> ids) async {
    if (ids.isEmpty) return 0;
    final placeholders = List.filled(ids.length, '?').join(',');
    return _db.delete(
      'telemetry_outbox',
      where: 'id IN ($placeholders)',
      whereArgs: ids,
    );
  }

  @override
  Future<void> markTelemetryRetry({
    required int id,
    required DateTime nextAttemptAt,
    required String lastError,
  }) async {
    await _db.rawUpdate(
      '''UPDATE telemetry_outbox
         SET attempts = attempts + 1,
             next_attempt_at = ?,
             last_error = ?,
             claimed_at = NULL
         WHERE id = ?''',
      [nextAttemptAt.millisecondsSinceEpoch, lastError, id],
    );
  }

  @override
  Future<int> releaseStaleTelemetryClaims({Duration? staleThreshold}) async {
    final threshold = staleThreshold ?? kTelemetryClaimTtl;
    final cutoff =
        DateTime.now().subtract(threshold).millisecondsSinceEpoch;
    return _db.rawUpdate(
      '''UPDATE telemetry_outbox
         SET claimed_at = NULL
         WHERE claimed_at IS NOT NULL AND claimed_at < ?''',
      [cutoff],
    );
  }

  @override
  Future<int> clearTelemetryOutbox() async {
    return _db.delete('telemetry_outbox');
  }
}

final databaseFactoryDefault = databaseFactory;
