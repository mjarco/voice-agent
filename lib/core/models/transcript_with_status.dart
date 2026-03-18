import 'package:voice_agent/core/models/sync_status.dart';

class TranscriptWithStatus {
  const TranscriptWithStatus({
    required this.id,
    required this.text,
    required this.createdAt,
    required this.status,
  });

  /// UUIDv4 (matches Transcript.id from Proposal 004).
  final String id;
  final String text;
  final DateTime createdAt;

  /// View-level status. "sent" is derived from the absence of a sync_queue row.
  final DisplaySyncStatus status;
}
