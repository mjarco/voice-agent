# Proposal 004 — Local Storage & Offline Queue

## Status: Draft

## Prerequisites
Proposal 000 (Project Bootstrap) — project structure and dependencies exist.
No code dependency — only requires that `lib/core/storage/` and `lib/core/models/`
directories exist.

## Scope
- Tasks: ~4
- Layers: core/storage, core/models
- Risk: Medium — introduces database dependency and data integrity concerns

---

## Problem Statement

The app is offline-first: transcripts must survive app restarts, process kills, and
network outages. Currently there is no persistence layer. Without local storage,
approved transcripts are lost when the app exits, and there is no mechanism to queue
API requests for later delivery. Every downstream feature that reads or writes
transcript data (003 Review, 005 API Sync, 007 History) depends on a reliable local
persistence layer.

---

## Are We Solving the Right Problem?

**Root cause:** No persistence layer exists. Transcript data lives only in memory and
is lost on process termination.

**Alternatives dismissed:**
- *SharedPreferences for transcript storage:* Not designed for structured, queryable
  data. No support for pagination, ordering, or relational integrity (sync queue
  referencing transcripts). Appropriate only for scalar config values like device ID.
- *Drift (formerly Moor):* Type-safe, powerful, but requires `build_runner` codegen
  and adds significant complexity. For an MVP with two tables, `sqflite` with raw SQL
  is simpler, has zero codegen, and is sufficient. Drift can be adopted later if schema
  grows beyond 5-6 tables.
- *Hive / Isar (NoSQL):* Lose relational integrity between transcripts and sync queue.
  The sync queue pattern is inherently relational (queue items reference transcripts).
- *Server-first with local cache:* Violates the offline-first requirement. The user
  may have no connectivity for extended periods.

**Smallest change?** Yes — this proposal provides the storage layer and data models
only. It does not implement sync logic (005), UI for history (007), or network calls.

---

## Goals

- Persist transcripts and sync queue entries in local SQLite, surviving app restarts
- Provide a clean `StorageService` interface that higher layers consume without knowing SQL details
- Define sync queue state machine (pending / sending / sent / failed) for Proposal 005 to drive
- Generate and persist a stable device ID for transcript attribution

## Non-goals

- No network sync logic — owned by Proposal 005
- No automatic retry scheduling — owned by Proposal 005
- No data expiration or cleanup policy — manual delete only for MVP
- No encryption at rest — acceptable for MVP; revisit if handling sensitive data
- No database migration framework beyond a version-checked `onCreate` / `onUpgrade`

---

## User-Visible Changes

None directly. This proposal is infrastructure. Its effects become visible through
Proposal 003 (Approve saves a transcript), 005 (sync queue drains to API), and
007 (history screen reads saved transcripts).

---

## Solution Design

### Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| `sqflite` | ^2.3 | SQLite database for iOS and Android |
| `path` | ^1.9 | Construct database file path from `getDatabasesPath()` |
| `uuid` | ^4.4 | Generate UUIDv4 for transcript and sync queue IDs |

All three are added to `pubspec.yaml` by this proposal.

For tests, `sqflite_common_ffi` (dev dependency) provides an in-memory SQLite backend
that runs on the host machine without a device.

### SQLite Schema

```sql
-- Version 1

CREATE TABLE transcripts (
  id               TEXT PRIMARY KEY,          -- UUIDv4, generated client-side
  text             TEXT NOT NULL,             -- transcript content (user-editable)
  language         TEXT,                      -- ISO 639-1 code, e.g. "pl", "en"
  audio_duration_ms INTEGER,                  -- original audio length in milliseconds
  device_id        TEXT NOT NULL,             -- stable device identifier
  created_at       INTEGER NOT NULL           -- Unix epoch milliseconds
);

CREATE TABLE sync_queue (
  id               TEXT PRIMARY KEY,          -- UUIDv4
  transcript_id    TEXT NOT NULL,             -- FK → transcripts.id
  status           TEXT NOT NULL DEFAULT 'pending',  -- enum: pending | sending | sent | failed
  attempts         INTEGER NOT NULL DEFAULT 0,
  last_attempt_at  INTEGER,                   -- Unix epoch milliseconds, NULL if never attempted
  error_message    TEXT,                      -- last failure reason, NULL on success
  created_at       INTEGER NOT NULL,          -- Unix epoch milliseconds
  FOREIGN KEY (transcript_id) REFERENCES transcripts(id) ON DELETE CASCADE
);

CREATE INDEX idx_sync_queue_status ON sync_queue(status);
```

Foreign key enforcement is enabled via `PRAGMA foreign_keys = ON` at connection open.

The `ON DELETE CASCADE` on `sync_queue.transcript_id` ensures that deleting a
transcript also removes its queue entry, preventing orphaned rows.

### Sync Queue State Machine

```
                      ┌─────────────────────────────────┐
                      │                                 │
                      ▼                                 │
  [pending] ──pick──► [sending] ──success──► (row deleted)
                         │                              │
                         └──failure──► [failed] ─retry──┘
```

State transitions and their owners:

| Transition | Method | Owner |
|------------|--------|-------|
| (new) to pending | `enqueue(transcriptId)` | Proposal 003 (Approve action) |
| pending to sending | `markSending(id)` | Proposal 005 (sync worker) |
| sending to (deleted) | `markSent(id)` | Proposal 005 (sync worker) |
| sending to failed | `markFailed(id, error)` | Proposal 005 (sync worker) |
| failed to pending | `markPendingForRetry(id)` | Proposal 005 (retry logic) |

**Sent row lifecycle:** `markSent(id)` **deletes** the sync_queue row rather than
keeping it with `status = 'sent'`. The `sent` state is terminal — there is no
transition out of it, so persisting it wastes space. Downstream consumers (Proposal
007 History) derive "sent" status by the **absence** of a sync_queue row for a
given transcript: if a transcript exists but has no sync_queue entry, it was
successfully synced.

The `attempts` counter increments on each `markSending` call. The `last_attempt_at`
timestamp updates on each `markSending` call. `error_message` is set on `markFailed`
and cleared on `markSending`.

### StorageService Interface

```
abstract class StorageService {
  // -- Transcripts --
  Future<void> saveTranscript(Transcript transcript);
  Future<Transcript?> getTranscript(String id);
  Future<List<Transcript>> getTranscripts({int limit = 50, int offset = 0});
  Future<void> deleteTranscript(String id);

  // -- Sync Queue --
  Future<void> enqueue(String transcriptId);
  Future<List<SyncQueueItem>> getPendingItems();
  Future<void> markSending(String id);
  Future<void> markSent(String id);       // deletes the sync_queue row
  Future<void> markFailed(String id, String error);
  Future<void> markPendingForRetry(String id);

  // -- Device --
  Future<String> getDeviceId();
}
```

### Data Models

```
class Transcript {
  final String id;            // UUIDv4
  final String text;
  final String? language;     // ISO 639-1
  final int? audioDurationMs;
  final String deviceId;
  final int createdAt;        // Unix epoch milliseconds

  // Factory: fromMap(Map<String, dynamic>) — for SQLite row mapping
  // Method: toMap() — for SQLite insert
}

class SyncQueueItem {
  final String id;            // UUIDv4
  final String transcriptId;
  final SyncStatus status;    // enum { pending, sending, failed } — sent rows are deleted
  final int attempts;
  final int? lastAttemptAt;   // Unix epoch milliseconds
  final String? errorMessage;
  final int createdAt;        // Unix epoch milliseconds

  // Factory: fromMap(Map<String, dynamic>)
  // Method: toMap()
}

enum SyncStatus { pending, sending, failed }
// Note: there is no `sent` value. Successfully synced items are deleted from
// sync_queue. "Sent" is derived by the absence of a queue row (used by 007).
```

Models are plain Dart classes with `fromMap` / `toMap` for SQLite serialization.
No codegen (json_serializable, freezed) — two simple models do not justify the
build_runner dependency.

### SqliteStorageService Implementation

```
class SqliteStorageService implements StorageService
```

Key implementation notes:

- **Database initialization:** `openDatabase(path, version: 1, onCreate: _createDb)`
  where `_createDb` runs the schema SQL above.
- **Database path:** `join(await getDatabasesPath(), 'voice_agent.db')`
- **Foreign keys:** Execute `PRAGMA foreign_keys = ON` in `onConfigure` callback.
- **Thread safety:** `sqflite` serializes database operations internally; no additional
  locking needed.
- **`getTranscripts`:** `SELECT * FROM transcripts ORDER BY created_at DESC LIMIT ? OFFSET ?`
- **`getPendingItems`:** `SELECT * FROM sync_queue WHERE status = 'pending' ORDER BY created_at ASC`
- **`enqueue`:** Inserts a new row with `status = 'pending'`, generates a new UUID for
  the queue item ID, sets `created_at` to now.
- **`markSending`:** `UPDATE sync_queue SET status = 'sending', attempts = attempts + 1, last_attempt_at = ?, error_message = NULL WHERE id = ?`
- **`markPendingForRetry`:** `UPDATE sync_queue SET status = 'pending' WHERE id = ? AND status = 'failed'`

### Device ID Generation Strategy

- On first call to `getDeviceId()`, generate a UUIDv4 via the `uuid` package.
- Persist it in `SharedPreferences` under key `device_id`.
- On subsequent calls, return the cached value from SharedPreferences.
- `SharedPreferences` is used (not SQLite) because the device ID must survive database
  deletion/recreation. It is a device-scoped value, not an app-data value.
- The `shared_preferences` package is already available in Flutter's standard set; if
  not present in `pubspec.yaml`, it is added by this proposal.

### Riverpod Providers

```
final storageServiceProvider = Provider<StorageService>((ref) {
  throw UnimplementedError('Override in main.dart with initialized instance');
});
```

The `SqliteStorageService` requires async initialization (opening the database).
In `main.dart`, the database is opened before `runApp`, and the provider is overridden:

```
final db = await SqliteStorageService.initialize();
runApp(
  ProviderScope(
    overrides: [storageServiceProvider.overrideWithValue(db)],
    child: const App(),
  ),
);
```

---

## Affected Mutation Points

| File | Change |
|------|--------|
| `pubspec.yaml` | Add `sqflite`, `path`, `uuid`, `shared_preferences` dependencies; add `sqflite_common_ffi` dev dependency |
| `lib/core/models/` | New files: `transcript.dart`, `sync_queue_item.dart`, `sync_status.dart` |
| `lib/core/storage/` | New files: `storage_service.dart` (interface), `sqlite_storage_service.dart` (implementation), `storage_provider.dart` (Riverpod provider) |
| `lib/main.dart` | Initialize database before `runApp`, override `storageServiceProvider` |

---

## Tasks

| # | Task | Layer |
|---|------|-------|
| T1 | Add `sqflite`, `path`, `uuid`, `shared_preferences` to `pubspec.yaml`. Add `sqflite_common_ffi` as dev dependency. Create data model classes: `Transcript`, `SyncQueueItem`, `SyncStatus` enum with `fromMap`/`toMap` methods. Add unit tests for model serialization round-trips. | core/models |
| T2 | Create `StorageService` abstract class. Implement `SqliteStorageService` with database initialization, schema creation, and all CRUD methods for transcripts. Add integration tests using `sqflite_common_ffi` in-memory database: save, get, list with pagination, delete (verify cascade). | core/storage |
| T3 | Implement sync queue methods in `SqliteStorageService`: `enqueue`, `getPendingItems`, `markSending`, `markSent` (deletes row), `markFailed`, `markPendingForRetry`. Add integration tests: full state machine cycle (pending to sending to deleted via markSent), failure path (pending to sending to failed to pending via retry), verify `attempts` counter increments, verify `error_message` set/cleared, verify markSent removes the row. | core/storage |
| T4 | Implement `getDeviceId()` with UUID generation and SharedPreferences persistence. Create `storageServiceProvider` Riverpod provider. Update `main.dart` to initialize database and override provider before `runApp`. Add test: `getDeviceId` returns same value on repeated calls; verify provider is accessible from widget tree. | core/storage, app |

### T1 details

- Create `lib/core/models/transcript.dart` with `Transcript` class
- Create `lib/core/models/sync_queue_item.dart` with `SyncQueueItem` class
- Create `lib/core/models/sync_status.dart` with `SyncStatus` enum (includes `fromString`/`toString` for SQLite mapping)
- Unit tests in `test/core/models/transcript_test.dart` and `test/core/models/sync_queue_item_test.dart`
- Tests verify: `toMap()` then `fromMap()` round-trip produces equal object; null-safe fields handled correctly

### T2 details

- Create `lib/core/storage/storage_service.dart` — abstract interface
- Create `lib/core/storage/sqlite_storage_service.dart` — implementation
- Database file: `voice_agent.db`
- Schema version: 1
- Enable foreign keys in `onConfigure`
- Integration tests in `test/core/storage/sqlite_storage_service_test.dart`
- Use `sqflite_common_ffi` with `databaseFactoryFfi` and `inMemoryDatabasePath` for tests
- Test: save transcript, retrieve by ID, list with limit/offset, delete removes transcript and cascaded queue entry

### T3 details

- All sync queue methods are in `SqliteStorageService`
- `enqueue` validates that `transcript_id` exists (FK constraint handles this; catch and rethrow with clear message)
- Tests: enqueue item, verify appears in `getPendingItems`; walk full happy path; walk failure+retry path; verify `attempts` increments; verify `error_message` lifecycle

### T4 details

- `getDeviceId()` in `SqliteStorageService`: check `SharedPreferences` for `device_id` key; if absent, generate UUIDv4, store, return; if present, return stored value
- Create `lib/core/storage/storage_provider.dart` with `storageServiceProvider`
- Update `lib/main.dart`: `WidgetsFlutterBinding.ensureInitialized()`, initialize `SqliteStorageService`, override provider
- Test `getDeviceId`: first call generates UUID, second call returns same value (use mock SharedPreferences)

---

## Test Impact

### Existing tests affected
- `test/app/app_test.dart` — must provide a `storageServiceProvider` override since `main.dart` now depends on it. Add a mock/stub `StorageService` override to the existing test's `ProviderScope`.

### New tests
- `test/core/models/transcript_test.dart` — model serialization
- `test/core/models/sync_queue_item_test.dart` — model serialization, status enum mapping
- `test/core/storage/sqlite_storage_service_test.dart` — integration tests for all CRUD and queue operations
- `test/core/storage/device_id_test.dart` — device ID generation and persistence
- Run with: `flutter test`

---

## Acceptance Criteria

1. `pubspec.yaml` contains `sqflite`, `path`, `uuid`, and `shared_preferences` as dependencies.
2. `Transcript.fromMap(transcript.toMap())` produces an equivalent object for all field combinations (including nullable fields).
3. `SyncQueueItem.fromMap(item.toMap())` produces an equivalent object, and `SyncStatus` enum round-trips through string representation.
4. `SqliteStorageService.initialize()` creates the database with both tables and the index.
5. `saveTranscript` followed by `getTranscript(id)` returns the saved transcript.
6. `getTranscripts(limit: 10, offset: 0)` returns transcripts in descending `created_at` order.
7. `deleteTranscript(id)` removes the transcript and any associated sync queue entry (cascade).
8. `enqueue(transcriptId)` creates a sync queue entry with `status = 'pending'` and `attempts = 0`.
9. `getPendingItems()` returns only items with `status = 'pending'`, ordered by `created_at` ascending.
10. Walking the full state machine: `enqueue` → `markSending` (increments attempts, sets `last_attempt_at`) → `markSent` deletes the sync_queue row. After `markSent`, no sync_queue entry exists for that transcript.
11. `markFailed(id, error)` sets `error_message`; subsequent `markPendingForRetry(id)` resets status to `pending`.
12. `getDeviceId()` returns a valid UUIDv4 on first call and the same value on all subsequent calls.
13. The app starts successfully with the initialized `StorageService` available via `storageServiceProvider`.
14. `flutter test` passes with all new tests.
15. `flutter analyze` exits with zero issues.

---

## Risks

| Risk | Mitigation |
|------|------------|
| `sqflite` does not support desktop platforms for development/testing | Use `sqflite_common_ffi` for host-machine tests; actual app targets mobile only |
| Schema migration needed in future proposals | Use `version` parameter in `openDatabase` with `onUpgrade` callback; schema is versioned from day one |
| SharedPreferences cleared by user (losing device ID) | Acceptable for MVP — a new device ID is generated, old transcripts retain the previous ID. No functional breakage. |
| Large number of pending sync items after extended offline period | `getPendingItems` has no limit, which could return many rows. For MVP this is acceptable; add pagination in Proposal 005 if needed |
| Database file corruption on unexpected process kill during write | SQLite WAL mode (sqflite default) provides crash resilience; no additional mitigation needed |

---

## Known Compromises and Follow-Up Direction

### No data expiration (V1 pragmatism)
Transcripts accumulate indefinitely. For MVP, users can delete manually (via history
screen, Proposal 007). If storage grows large, add a configurable retention policy
in a follow-up.

### No encryption at rest
SQLite data is stored in plain text on the device filesystem. Acceptable for
voice-note transcripts. If the app handles sensitive content in the future, adopt
`sqcipher` (encrypted SQLite) or Flutter's secure storage for sensitive fields.

### Raw SQL instead of type-safe query builder
Two tables with simple queries do not justify Drift's codegen overhead. If the schema
grows beyond 5 tables or queries become complex (joins, aggregations), migrate to
Drift in a follow-up proposal.

### `shared_preferences` for device ID only
Using SharedPreferences for a single value is lightweight. If more app-config values
emerge (API endpoint, theme preference), they can coexist in SharedPreferences
without needing a separate proposal.
