import 'package:voice_agent/core/models/sync_queue_item.dart';
import 'package:voice_agent/core/models/transcript.dart';
import 'package:voice_agent/core/models/transcript_with_status.dart';

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
}
