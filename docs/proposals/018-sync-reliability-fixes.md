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

**Root cause (auto-retry):** The `_promoteEligibleRetries()` stub was left as a TODO because `StorageService` does not expose `getFailedItems()`. Without querying failed items and their `last_attempt_at`, the worker cannot determine backoff eligibility.

**Root cause (migrations):** The single-table initial schema did not need migrations. But with 18 proposals implemented, the schema is overdue for a migration framework.

**Smallest change?** Yes — each fix is narrowly scoped to the sync queue and does not change domain logic or UI.

---

## Goals

- Stale `sending` items are recovered to `pending` on app startup
- Failed items with transient errors are automatically retried with exponential backoff
- Database has a migration framework for future schema changes

## Non-goals

- Background sync (remains foreground-only per ADR-022)
- Changing the sync queue state machine states (pending/sending/failed)
- UI changes to History screen

---

## Solution Design

### T1: Recover stale `sending` items on startup

Add a `recoverStaleSending()` method to `StorageService` that resets all `sending` items to `pending`. Call it once during app initialization, after `SqliteStorageService.initialize()` in `main.dart`.

**Rationale:** If the app was killed during sync, all `sending` items are definitionally stale — the HTTP request died with the process. Resetting to `pending` is always safe because `markSending` already incremented the attempt counter, so the retry count is preserved.

```dart
// StorageService
Future<int> recoverStaleSending();

// SqliteStorageService
Future<int> recoverStaleSending() async {
  return await _db.rawUpdate(
    "UPDATE sync_queue SET status = ?, error_message = 'Recovered after app restart' "
    "WHERE status = ?",
    [SyncStatus.pending.name, SyncStatus.sending.name],
  );
}

// main.dart — after initialize(), before runApp()
await storage.recoverStaleSending();
```

**Files changed:**
- `lib/core/storage/storage_service.dart` — add `recoverStaleSending()` to interface
- `lib/core/storage/sqlite_storage_service.dart` — implement `recoverStaleSending()`
- `lib/main.dart` — call `recoverStaleSending()` after `initialize()`
- `test/core/storage/sqlite_storage_service_test.dart` — test recovery

### T2: Implement auto-retry with backoff

Add `getRetryEligibleItems()` to `StorageService` that returns `failed` items whose `last_attempt_at + backoff_for_attempt` has elapsed and whose `attempts < _maxRetries`.

Replace the `_promoteEligibleRetries()` stub in `SyncWorker` with a real implementation that calls `getRetryEligibleItems()` and transitions eligible items back to `pending` via `markPendingForRetry()`.

```dart
// StorageService
Future<List<SyncQueueItem>> getRetryEligibleItems(int maxRetries, Duration Function(int) backoffFor);

// SqliteStorageService
Future<List<SyncQueueItem>> getRetryEligibleItems(
  int maxRetries,
  Duration Function(int) backoffFor,
) async {
  final now = DateTime.now().millisecondsSinceEpoch;
  final rows = await _db.query(
    'sync_queue',
    where: 'status = ? AND attempts < ?',
    whereArgs: [SyncStatus.failed.name, maxRetries],
    orderBy: 'last_attempt_at ASC',
  );
  return rows
      .map(SyncQueueItem.fromMap)
      .where((item) {
        final delay = backoffFor(item.attempts);
        return (item.lastAttemptAt ?? 0) + delay.inMilliseconds <= now;
      })
      .toList();
}

// SyncWorker._promoteEligibleRetries()
Future<void> _promoteEligibleRetries() async {
  final eligible = await storageService.getRetryEligibleItems(
    _maxRetries,
    backoffForAttempt,
  );
  for (final item in eligible) {
    await storageService.markPendingForRetry(item.id);
  }
}
```

**Files changed:**
- `lib/core/storage/storage_service.dart` — add `getRetryEligibleItems()` to interface
- `lib/core/storage/sqlite_storage_service.dart` — implement `getRetryEligibleItems()`
- `lib/features/api_sync/sync_worker.dart` — replace `_promoteEligibleRetries()` stub
- `test/core/storage/sqlite_storage_service_test.dart` — test backoff eligibility
- `test/features/api_sync/sync_worker_test.dart` — test promotion logic

### T3: Add database migration framework

Add an `onUpgrade` callback to `SqliteStorageService.initialize()` that dispatches to versioned migration functions. No schema changes in this task — just the framework.

```dart
static Future<SqliteStorageService> initialize() async {
  final db = await openDatabase(
    'voice_agent.db',
    version: 1,
    onCreate: _onCreate,
    onUpgrade: _onUpgrade,
  );
  return SqliteStorageService._(db);
}

static Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
  // Each migration runs in sequence: version 1->2, 2->3, etc.
  // Add migration functions here as the schema evolves.
}
```

**Files changed:**
- `lib/core/storage/sqlite_storage_service.dart` — add `onUpgrade` callback, extract `_onCreate`

---

## Acceptance Criteria

- [ ] On app startup after a simulated crash during sync, previously-sending items are retried automatically
- [ ] Failed items with transient errors are retried with the defined backoff schedule (30s, 1m, 5m, 15m, 1h...)
- [ ] Items exceeding `_maxRetries` (10) remain in `failed` state permanently
- [ ] `flutter test` and `flutter analyze` pass
- [ ] No changes to History screen UI or user-facing behavior (except items now auto-retry)
