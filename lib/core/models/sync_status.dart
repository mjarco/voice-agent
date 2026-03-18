/// Sync queue item status as persisted in SQLite.
///
/// Note: there is no `sent` value. Successfully synced items are deleted
/// from sync_queue. "Sent" is derived by the absence of a queue row
/// (used by Proposal 007 History via [DisplaySyncStatus]).
enum SyncStatus {
  pending,
  sending,
  failed;

  static SyncStatus fromString(String value) {
    return SyncStatus.values.firstWhere(
      (s) => s.name == value,
      orElse: () => throw ArgumentError('Invalid SyncStatus: $value'),
    );
  }
}

/// View-level sync status used by the History screen (Proposal 007).
/// Includes `sent` which is derived from the absence of a sync_queue row.
enum DisplaySyncStatus {
  sent,
  pending,
  failed,
}
