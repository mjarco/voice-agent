# Proposal 018 — Sync Reliability Fixes

## Status: Draft

## Prerequisites
- P005 (API Sync) — `SyncWorker` and sync queue must exist; merged
- P004 (Local Storage) — `StorageService` with sync queue operations; merged

## Scope
- Tasks: 3
- Layers: core/storage, features/api_sync
- Risk: Medium — changes sync state machine behavior and database queries

---

## Problem Statement

The sync subsystem has three reliability gaps discovered during an ADR audit:

1. **Stale `sending` state after crash.** If the app is force-killed or crashes while a sync item is in `sending` status, that item is permanently orphaned. `getPendingItems()` only returns `status = 'pending'`, and there is no startup recovery that resets stale `sending` items. The `reactivateForResend` method only operates on `failed` items, so `sending` items cannot be recovered even manually from the History screen.

2. **Auto-retry backoff not implemented.** `_promoteEligibleRetries()` is a stub with a TODO comment. The backoff delay table is defined (`_backoffDelays`: 30s, 1m, 5m, 15m, 1h...) and `backoffForAttempt()` exists as a static method, but neither is used. After one transient failure, items are marked `failed` and stay there until the user manually resends from the History screen.

3. **No database migration path.** The database is at `version: 1` with no `onUpgrade` callback. The first schema change will require migration code, and there is no framework in place to handle it.

---

## Are We Solving the Right Problem?

**Root cause (stale sending):** The `sending` state was designed as a transient lock — items move to `sending` while the HTTP request is in flight, then immediately to `sent` (deleted) or `failed`. But app termination during the HTTP request leaves the lock held forever. The state machine has no recovery path for this scenario.

**Root cause (auto-retry):** The `_promoteEligibleRetries()` stub was left as a TODO because `StorageService` does not expose `getFailedItems()`. Without querying failed items and their `last_attempt_at`, the worker cannot determine backoff eligibility. Additionally, both `ApiPermanentFailure` and `ApiTransientFailure` call `markFailed()` identically, so auto-retry would wastefully retry permanent failures that can never succeed. (Note: 408 and 429 are already classified as transient by `ApiClient._classifyStatusCode`, so the `ApiPermanentFailure` type only covers truly non-retriable errors like 400, 401, 403, 404.)

**Root cause (migrations):** The single-table initial schema did not need migrations. But with 18 proposals implemented, the schema is overdue for a migration framework.

**Smallest change?** Yes — each fix is narrowly scoped to the sync queue and does not change domain logic or UI.

---

## Goals

- Stale `sending` items are recovered to `pending` on app startup
- Failed items with transient errors are automatically retried with exponential backoff
- Database has a migration framework for future schema changes

## Non-goals

- Background sync (remains foreground-only per ADR-NET-002)
- Changing the sync queue state machine states (pending/sending/failed)
- UI changes to History screen

---

## Solution Design

### T1: Recover stale `sending` items on startup

Add a `recoverStaleSending()` method to `StorageService` that resets all `sending` items to `pending`. Call it once during app initialization, after `SqliteStorageService.initialize()` in `main.dart`. The method returns `Future<int>` (the count of recovered rows) so `main.dart` can log diagnostics on debug builds.

**Rationale:** If the app was killed during sync, all `sending` items are definitionally stale — the HTTP request died with the process. Resetting to `pending` is always safe because `markSending` already incremented the attempt counter, so the retry count is preserved.

```dart
// StorageService
Future<int> recoverStaleSending();

// SqliteStorageService
Future<int> recoverStaleSending() async {
  return await _db.rawUpdate(
    "UPDATE sync_queue SET status = ?, error_message = NULL "
    "WHERE status = ?",
    [SyncStatus.pending.name, SyncStatus.sending.name],
  );
}

// main.dart — after initialize(), before runApp()
final recovered = await storage.recoverStaleSending();
if (kDebugMode && recovered > 0) {
  debugPrint('Recovered $recovered stale sending items');
}
```

**Files changed:**
- `lib/core/storage/storage_service.dart` — add `recoverStaleSending()` to interface
- `lib/core/storage/sqlite_storage_service.dart` — implement `recoverStaleSending()`
- `lib/main.dart` — call `recoverStaleSending()` after `initialize()`, log count in debug mode
- `test/core/storage/sqlite_storage_service_test.dart` — test recovery
- All 11 test files with `implements StorageService` fakes (see Affected Mutation Points) — add no-op `recoverStaleSending()` stub

### T2: Implement auto-retry with backoff

#### Failure type discrimination

The current `_drain()` calls `markFailed()` for both `ApiPermanentFailure` and `ApiTransientFailure`. Auto-retry must not retry permanent failures — they will never succeed on retry. Note: `ApiClient._classifyStatusCode` already handles the HTTP status family nuance: 408 (timeout) and 429 (rate limit) are classified as `ApiTransientFailure` despite being 4xx codes. The proposal relies on the existing typed `ApiResult` contract, not raw HTTP status codes.

**Approach:** Add an optional `overrideAttempts` parameter to `markFailed()`. For `ApiPermanentFailure` results, SyncWorker passes `overrideAttempts: _maxRetries` to exhaust the retry budget. `getFailedItems(maxAttempts: _maxRetries)` then naturally excludes these items. This keeps business logic (what counts as permanent, what `_maxRetries` is) in SyncWorker while the storage layer only stores and queries data. The distinction relies entirely on the typed `ApiResult` sealed class from `api_client.dart`, not on raw HTTP status codes. This pattern is documented in ADR-DATA-006.

#### Storage layer: `getFailedItems` and `markFailed` changes

Add `getFailedItems()` to `StorageService` — a pure data query with no business logic. The `maxAttempts` filter runs in SQL.

Enhance `markFailed()` with an optional `overrideAttempts` parameter. When provided, set `attempts` to that value instead of leaving it as-is.

Fix `markPendingForRetry()` to also clear `error_message` (currently only resets status).

```dart
// StorageService — new method
Future<List<SyncQueueItem>> getFailedItems({int? maxAttempts});

// StorageService — enhanced signature
Future<void> markFailed(String id, String error, {int? overrideAttempts});

// SqliteStorageService — getFailedItems
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

// SqliteStorageService — enhanced markFailed
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

// SqliteStorageService — fix markPendingForRetry to clear error_message
Future<void> markPendingForRetry(String id) async {
  await _db.update(
    'sync_queue',
    {'status': SyncStatus.pending.name, 'error_message': null},
    where: 'id = ? AND status = ?',
    whereArgs: [id, SyncStatus.failed.name],
  );
}
```

#### SyncWorker: `_drain()` failure handling and `_promoteEligibleRetries()`

Update `_drain()` to pass `overrideAttempts: _maxRetries` for permanent failures:

```dart
case ApiPermanentFailure(:final message):
  // Exhaust retry budget — permanent failures should never be auto-retried
  await storageService.markFailed(
    item.id, message, overrideAttempts: _maxRetries,
  );
  unawaited(audioFeedbackService.playError());
case ApiTransientFailure(:final reason):
  final attempts = item.attempts + 1; // markSending already incremented
  if (attempts >= _maxRetries) {
    await storageService.markFailed(
      item.id,
      'Max retries exceeded ($attempts attempts). Last error: $reason',
    );
  } else {
    await storageService.markFailed(item.id, reason);
  }
  unawaited(audioFeedbackService.playError());
```

Replace the `_promoteEligibleRetries()` stub. Backoff filtering runs in SyncWorker, not in the storage layer:

```dart
Future<void> _promoteEligibleRetries() async {
  final now = DateTime.now().millisecondsSinceEpoch;
  final failed = await storageService.getFailedItems(maxAttempts: _maxRetries);
  for (final item in failed) {
    final delay = backoffForAttempt(item.attempts);
    if ((item.lastAttemptAt ?? 0) + delay.inMilliseconds <= now) {
      await storageService.markPendingForRetry(item.id);
    }
  }
}
```

**Files changed:**
- `lib/core/storage/storage_service.dart` — add `getFailedItems()`, update `markFailed()` signature
- `lib/core/storage/sqlite_storage_service.dart` — implement `getFailedItems()`, update `markFailed()`, fix `markPendingForRetry()` to clear `error_message`
- `lib/features/api_sync/sync_worker.dart` — replace `_promoteEligibleRetries()` stub, update `_drain()` permanent failure handling
- `test/core/storage/sqlite_storage_service_test.dart` — test `getFailedItems`, `markFailed` with `overrideAttempts`, `markPendingForRetry` clearing `error_message`
- `test/features/api_sync/sync_worker_test.dart` — test promotion logic, permanent failure not retried, update `FakeStorageService` with new methods

### T3: Add database migration framework

Add an `onUpgrade` callback to `SqliteStorageService.initialize()` that dispatches to versioned migration functions. No schema changes in this task — just the framework. The version stays at `1`.

The pattern uses a `for` loop from `oldVersion + 1` to `newVersion`, calling a versioned migration function for each step. This ensures upgrades run sequentially regardless of how many versions the user has skipped (e.g., v1 → v4 runs migrations 2, 3, 4 in order).

```dart
static Future<SqliteStorageService> initialize({
  DatabaseFactory? databaseFactory,
  String? path,
}) async {
  final factory = databaseFactory ?? databaseFactoryDefault;
  final dbPath = path ?? join(await getDatabasesPath(), 'voice_agent.db');

  final db = await factory.openDatabase(
    dbPath,
    options: OpenDatabaseOptions(
      version: 1,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _createDb,
      onUpgrade: _onUpgrade,
    ),
  );

  return SqliteStorageService._(db);
}

static Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
  for (var v = oldVersion + 1; v <= newVersion; v++) {
    switch (v) {
      // Example for a future migration:
      // case 2:
      //   await _migrateV1ToV2(db);
      default:
        break;
    }
  }
}

// Example migration template (not added until needed):
// static Future<void> _migrateV1ToV2(Database db) async {
//   await db.execute('ALTER TABLE sync_queue ADD COLUMN new_col TEXT');
// }
```

**Files changed:**
- `lib/core/storage/sqlite_storage_service.dart` — add `onUpgrade` callback with sequential migration loop

**Testing note:** With the database staying at version 1, `onUpgrade` will never fire in existing tests — `sqflite` only calls it when `oldVersion < newVersion`. This task is pure scaffolding; the first real migration (in a future proposal that bumps the version to 2) will be the true integration test of the framework. No new tests are needed for T3.

---

## Affected Mutation Points

**New methods on existing interfaces:**
- `lib/core/storage/storage_service.dart` — `recoverStaleSending()`, `getFailedItems()`
- `lib/core/storage/sqlite_storage_service.dart` — implement both new methods, update `markFailed()`, fix `markPendingForRetry()`

**Modified methods:**
- `lib/core/storage/storage_service.dart` — `markFailed()` adds optional `overrideAttempts` parameter
- `lib/core/storage/sqlite_storage_service.dart` — `markFailed()` handles `overrideAttempts`, `markPendingForRetry()` clears `error_message`, `initialize()` adds `onUpgrade`
- `lib/features/api_sync/sync_worker.dart` — `_drain()` permanent failure handling, `_promoteEligibleRetries()` replaced

**Modified entry point:**
- `lib/main.dart` — call `recoverStaleSending()` after storage init

**Test fakes updated (new `recoverStaleSending` and `getFailedItems` stubs):**
Every class that `implements StorageService` needs no-op stubs for the two new methods. The `markFailed` signature change (adding optional named parameter) is non-breaking.
- `test/features/api_sync/sync_worker_test.dart` — `FakeStorageService`
- `test/features/recording/presentation/recording_screen_test.dart` — `_StubStorage`
- `test/features/recording/presentation/recording_screen_mic_button_test.dart` — `_StubStorage`
- `test/features/recording/presentation/recording_screen_hands_free_test.dart` — `_StubStorage`
- `test/features/recording/presentation/recording_controller_test.dart` — `FakeStorageService`
- `test/features/recording/presentation/hands_free_controller_test.dart` — `FakeStorageService`
- `test/features/history/history_notifier_test.dart` — `FakeStorageService`
- `test/features/settings/settings_screen_test.dart` — `_StubStorage`
- `test/features/settings/advanced_settings_screen_test.dart` — `_StubStorage`
- `test/app/router_test.dart` — `_StubStorageService`
- `test/app/app_test.dart` — `_StubStorageService`

**Project documentation:**
- `CLAUDE.md` — refresh StorageService Contract section to match the current interface (it is already stale, missing `getTranscriptsWithStatus` and `reactivateForResend`); include the two new methods (`recoverStaleSending`, `getFailedItems`) and the updated `markFailed` signature

---

## Tasks

| # | Task | Layer | Depends on |
|---|------|-------|------------|
| T1 | Recover stale `sending` items on startup | core/storage, main.dart | — |
| T2 | Auto-retry with backoff + permanent failure discrimination | core/storage, features/api_sync | — |
| T3 | Database migration framework (`onUpgrade`) | core/storage | — |

### T1 details

- Add `Future<int> recoverStaleSending()` to `StorageService` interface
- Implement in `SqliteStorageService`: `rawUpdate` resetting `sending` → `pending`
- Call in `main.dart` after `SqliteStorageService.initialize()`, log recovered count guarded by `kDebugMode` (stripped in release builds, compliant with PR checklist)
- Update all 11 test files with `implements StorageService` fakes — add no-op `recoverStaleSending()` stub returning `0`
- Tests: insert items with `sending` status, call `recoverStaleSending()`, verify they become `pending`

### T2 details

- Add `Future<List<SyncQueueItem>> getFailedItems({int? maxAttempts})` to `StorageService`
- Implement in `SqliteStorageService`: query with `status = 'failed'` and optional `attempts < maxAttempts`
- Update `markFailed()` signature to `Future<void> markFailed(String id, String error, {int? overrideAttempts})`
- Update `SqliteStorageService.markFailed()` to set `attempts` when `overrideAttempts` is non-null
- Fix `SqliteStorageService.markPendingForRetry()` to clear `error_message` (add `'error_message': null`)
- Update `SyncWorker._drain()`: for `ApiPermanentFailure`, pass `overrideAttempts: _maxRetries` to exhaust retry budget
- Replace `SyncWorker._promoteEligibleRetries()` stub: fetch failed items via `getFailedItems(maxAttempts: _maxRetries)`, filter by backoff timing, call `markPendingForRetry` for eligible items
- Update all 11 test files with `implements StorageService` fakes — add no-op `getFailedItems()` stub returning `[]`
- Refresh `CLAUDE.md` StorageService Contract section to match the full current interface (including pre-existing missing methods) plus the two new ones
- Tests:
  - `sqlite_storage_service_test.dart`: `getFailedItems` returns failed items below max attempts, `markFailed` with `overrideAttempts` sets attempts, `markPendingForRetry` clears `error_message`
  - `sync_worker_test.dart`: eligible item promoted after backoff, non-eligible item (too recent) not promoted, permanent failure (attempts = _maxRetries) not promoted, transient failure promoted after delay

### T3 details

- Add `onUpgrade` callback to `SqliteStorageService.initialize()` `OpenDatabaseOptions`
- Implement `_onUpgrade` with sequential `for` loop and `switch` statement (empty for now)
- Version stays at `1` — no actual migration needed
- No new tests — `onUpgrade` never fires at version 1 (scaffolding only; first real migration will be the integration test)

---

## Acceptance Criteria

1. On app startup, previously-sending items are recovered to `pending` status. They are then retried when the foreground sync worker runs with a configured API URL.
2. Failed items with transient errors (`ApiTransientFailure`) are retried with the defined backoff schedule (30s, 1m, 5m, 15m, 1h...).
3. Items exceeding `_maxRetries` (10) remain in `failed` state permanently.
4. Items that failed with a permanent error (`ApiPermanentFailure`) are never auto-retried regardless of attempt count.
5. `markPendingForRetry` clears `error_message` so re-promoted items don't carry stale error text.
6. `flutter test` and `flutter analyze` pass.
7. No changes to History screen UI or user-facing behavior (except items now auto-retry).

---

## Risks

| Risk | Mitigation |
|------|------------|
| `recoverStaleSending()` runs on every app start, even cold starts with no stale items | The UPDATE is a no-op when no rows match `status = 'sending'`. SQLite handles this efficiently. |
| Auto-retry creates a burst of retries on app foreground after long pause | `_promoteEligibleRetries()` runs once per `_pollInterval` (5s) and `_drain()` processes one item per cycle (FIFO). Burst is naturally throttled. |
| `overrideAttempts: _maxRetries` on permanent failures loses the real attempt count | Acceptable trade-off — permanent failures are terminal. The error message still records the failure reason. Users who want to retry can use "Resend" from History, which calls `reactivateForResend()` and resets attempts to 0. |
| `markPendingForRetry` clearing `error_message` makes debugging harder | The error message served its purpose while the item was in `failed` state. Once re-promoted to `pending`, a fresh attempt will either succeed or generate a new error. |
| Migration framework (T3) has no migrations to test | Pure scaffolding — `onUpgrade` never fires at version 1. The first real migration (a future proposal that bumps to version 2) will be the true integration test. Acceptable: the code is trivial and only wires a callback. |

---

## Test Impact

### Existing tests affected

- `test/core/storage/sqlite_storage_service_test.dart` — new test cases for `recoverStaleSending()`, `getFailedItems()`, enhanced `markFailed()`, `markPendingForRetry()` clearing `error_message`
- `test/features/api_sync/sync_worker_test.dart` — new test cases for promotion logic, permanent failure discrimination; `FakeStorageService` needs `recoverStaleSending()` and `getFailedItems()` stubs, `markFailed` signature update
- All 11 test files with `implements StorageService` fakes need `recoverStaleSending()` and `getFailedItems()` stubs (see Affected Mutation Points for full list)

### New tests

**T1 (sqlite_storage_service_test.dart):**
- Insert items with `sending` status → `recoverStaleSending()` resets them to `pending`
- Items in `pending` and `failed` are unaffected by `recoverStaleSending()`
- Return value equals the count of recovered items

**T2 (sqlite_storage_service_test.dart):**
- `getFailedItems()` returns only items with `status = 'failed'`
- `getFailedItems(maxAttempts: 5)` excludes items with `attempts >= 5`
- `markFailed(id, error, overrideAttempts: 10)` sets `attempts` to 10
- `markPendingForRetry` sets `error_message` to null

**T2 (sync_worker_test.dart):**
- Failed item with elapsed backoff is promoted to pending
- Failed item with recent `last_attempt_at` (within backoff window) is not promoted
- Permanently failed item (attempts = _maxRetries) is not promoted
- Transient failure → `markFailed` called without `overrideAttempts`
- Permanent failure → `markFailed` called with `overrideAttempts: _maxRetries`

Run: `flutter analyze && flutter test`
