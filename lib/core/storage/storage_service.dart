import 'dart:typed_data';

import 'package:voice_agent/core/models/sync_queue_item.dart';
import 'package:voice_agent/core/models/transcript.dart';
import 'package:voice_agent/core/models/transcript_with_status.dart';
import 'package:voice_agent/core/observability/telemetry_outbox_row.dart';

abstract class StorageService {
  // -- Transcripts --
  Future<void> saveTranscript(Transcript transcript);
  Future<Transcript?> getTranscript(String id);
  Future<List<Transcript>> getTranscripts({int limit = 50, int offset = 0});
  Future<void> deleteTranscript(String id);

  // -- History query --
  Future<List<TranscriptWithStatus>> getTranscriptsWithStatus({
    int limit = 20,
    int offset = 0,
  });

  // -- Sync Queue --
  Future<void> enqueue(String transcriptId);
  Future<List<SyncQueueItem>> getPendingItems();
  Future<void> markSending(String id);
  Future<void> markSent(String id); // deletes the sync_queue row
  Future<void> markFailed(String id, String error, {int? overrideAttempts});
  Future<void> markPendingForRetry(String id);
  Future<List<SyncQueueItem>> getFailedItems({int? maxAttempts});

  /// Reactivate a failed sync queue entry for the given transcript.
  /// Resets status to pending, attempts to 0, clears error.
  /// Only affects rows with status='failed'. No-op if already pending.
  /// Invariant: at most one sync_queue row per transcript.
  Future<void> reactivateForResend(String transcriptId);

  /// Reset all `sending` items to `pending` on app startup.
  /// Returns the number of recovered rows.
  Future<int> recoverStaleSending();

  // -- Device --
  Future<String> getDeviceId();

  // -- Telemetry outbox (P039 T4) --
  //
  // Test stubs that `implements StorageService` but do NOT exercise
  // telemetry can pull in default no-op implementations via the
  // [TelemetryStorageNoop] mixin defined below. Production code uses
  // SqliteStorageService which overrides every method.

  /// Persist one OTLP/JSON envelope. Enforces the per-kind retention
  /// cap (`kTelemetryRetentionByKind`) and 7-day age cap before
  /// inserting — oldest rows of the same kind are dropped to make
  /// room. Returns the new row id.
  Future<int> appendTelemetryRow({
    required TelemetrySignalKind signalKind,
    required Uint8List payload,
  });

  /// Claim up to [limit] outbox rows whose `next_attempt_at <= now`
  /// and which are not currently claimed by another worker. Sets
  /// `claimed_at = now` in a single transaction. Returns the claimed
  /// rows in oldest-first order.
  Future<List<TelemetryOutboxRow>> claimDueTelemetryRows({int limit = 50});

  /// Drop rows by id (called after a 2xx response or after a permanent
  /// failure beyond the retry budget). Returns the number of rows
  /// actually deleted.
  Future<int> deleteTelemetryRows(List<int> ids);

  /// Mark a row for retry: increment attempts, set last_error, set
  /// next_attempt_at to the supplied future timestamp. Releases the
  /// claim atomically (claimed_at = NULL).
  Future<void> markTelemetryRetry({
    required int id,
    required DateTime nextAttemptAt,
    required String lastError,
  });

  /// On boot, release any claims older than [staleThreshold] (default
  /// `kTelemetryClaimTtl`). Returns the number of rows released.
  Future<int> releaseStaleTelemetryClaims({Duration? staleThreshold});

  /// User-initiated purge — wipes the entire outbox. Called from the
  /// T5c "Clear telemetry buffer" button.
  Future<int> clearTelemetryOutbox();
}

/// Convenience mixin for test stubs that implement [StorageService] but
/// do not need to exercise telemetry persistence. Provides safe no-op
/// implementations of every telemetry-outbox method.
///
/// Usage: `class _StubStorage with TelemetryStorageNoop implements StorageService { … }`
mixin TelemetryStorageNoop implements StorageService {
  @override
  Future<int> appendTelemetryRow({
    required TelemetrySignalKind signalKind,
    required Uint8List payload,
  }) async =>
      0;

  @override
  Future<List<TelemetryOutboxRow>> claimDueTelemetryRows(
          {int limit = 50}) async =>
      const <TelemetryOutboxRow>[];

  @override
  Future<int> deleteTelemetryRows(List<int> ids) async => 0;

  @override
  Future<void> markTelemetryRetry({
    required int id,
    required DateTime nextAttemptAt,
    required String lastError,
  }) async {}

  @override
  Future<int> releaseStaleTelemetryClaims({Duration? staleThreshold}) async => 0;

  @override
  Future<int> clearTelemetryOutbox() async => 0;
}
