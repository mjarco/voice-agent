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
  Future<void> markFailed(String id, String error);
  Future<void> markPendingForRetry(String id);

  // -- Device --
  Future<String> getDeviceId();
}
