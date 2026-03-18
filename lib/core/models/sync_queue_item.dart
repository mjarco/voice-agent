import 'package:voice_agent/core/models/sync_status.dart';

class SyncQueueItem {
  const SyncQueueItem({
    required this.id,
    required this.transcriptId,
    required this.status,
    required this.attempts,
    this.lastAttemptAt,
    this.errorMessage,
    required this.createdAt,
  });

  /// UUIDv4.
  final String id;

  /// FK to transcripts.id.
  final String transcriptId;

  /// Queue status: pending, sending, failed. Sent rows are deleted.
  final SyncStatus status;

  /// Number of send attempts.
  final int attempts;

  /// Unix epoch milliseconds of last attempt, null if never attempted.
  final int? lastAttemptAt;

  /// Last failure reason, null on success or pending.
  final String? errorMessage;

  /// Unix epoch milliseconds.
  final int createdAt;

  factory SyncQueueItem.fromMap(Map<String, dynamic> map) {
    return SyncQueueItem(
      id: map['id'] as String,
      transcriptId: map['transcript_id'] as String,
      status: SyncStatus.fromString(map['status'] as String),
      attempts: map['attempts'] as int,
      lastAttemptAt: map['last_attempt_at'] as int?,
      errorMessage: map['error_message'] as String?,
      createdAt: map['created_at'] as int,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'transcript_id': transcriptId,
      'status': status.name,
      'attempts': attempts,
      'last_attempt_at': lastAttemptAt,
      'error_message': errorMessage,
      'created_at': createdAt,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SyncQueueItem &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          transcriptId == other.transcriptId &&
          status == other.status &&
          attempts == other.attempts &&
          lastAttemptAt == other.lastAttemptAt &&
          errorMessage == other.errorMessage &&
          createdAt == other.createdAt;

  @override
  int get hashCode => Object.hash(
        id,
        transcriptId,
        status,
        attempts,
        lastAttemptAt,
        errorMessage,
        createdAt,
      );
}
