# Proposal 009 — Code Review Fixes

## Status: Implemented

## Prerequisites
All proposals 000–008 merged.

## Scope
- Tasks: ~5
- Layers: core, features (recording, transcript, api_sync, history, settings), app
- Risk: Medium — touches every layer, fixes silent bugs and architecture violations

---

## Problem Statement

A full codebase review after MVP implementation revealed 5 blocker architecture
violations, 1 functional blocker (StreamController reuse), and 6 important issues
including a silently broken resend action and dead backoff logic. These must be
fixed before the app can ship.

---

## Are We Solving the Right Problem?

**Root cause:** Fast implementation across 9 proposals introduced cross-feature
imports that violate the layered architecture, and integration bugs at proposal
boundaries that were not caught by unit tests.

**Alternatives dismissed:**
- *Ignore architecture violations:* They compound over time and make future
  proposals harder to implement correctly.
- *Rewrite affected features:* Over-scoped. The fixes are surgical — move types
  to the right layer, fix contracts, fix bugs.

**Smallest change?** Yes — each fix is targeted at a specific file and does not
change behavior except where bugs are being corrected.

---

## Goals

- Eliminate all architecture violations (no cross-feature imports, no core→features)
- Establish clear ownership for shared app configuration (API URL, token)
- Fix the StreamController bug so recording works across multiple sessions
- Fix the resend action so it actually works
- Improve code quality in areas flagged by review

## Non-goals

- No new features
- No backoff retry implementation (documented as known gap)

---

## User-Visible Changes

- Recording now works correctly across multiple sessions (was broken after first stop/cancel)
- History resend action now actually re-queues the transcript (was silently failing)
- History detail screen preserves bottom navigation bar

---

## Solution Design

### App Configuration Ownership (T1)

The root problem is that API URL, API token, and their "configured?" check are
used by multiple features but currently owned by `features/settings/`. This forces
cross-feature imports everywhere.

**New structure:** Shared app configuration lives in `core/config/`:

```
lib/core/config/
  app_config.dart            # AppConfig model (url, token, autoSend, language, keepHistory)
  app_config_service.dart    # AppConfigService — the SOLE persistence adapter for config
  app_config_provider.dart   # appConfigProvider (StateNotifier reading/writing via AppConfigService)
  api_url_configured_provider.dart  # derived provider (url != null)
```

**Persistence boundary:** `AppConfigService` is the single adapter that knows
about `SharedPreferences` keys and `FlutterSecureStorage`. It replaces
`features/settings/settings_service.dart` entirely — there is no longer a
separate `SettingsService`. All config persistence lives in one place:

```
core/config/app_config_service.dart
  - load() → reads all keys from SharedPreferences + token from SecureStorage
  - saveApiUrl(url) → writes to SharedPreferences
  - saveApiToken(token) → writes to SecureStorage
  - saveAutoSend(value) → writes to SharedPreferences
  - saveLanguage(language) → writes to SharedPreferences
  - saveKeepHistory(value) → writes to SharedPreferences
```

`features/settings/settings_screen.dart` becomes a pure UI that calls
`ref.read(appConfigProvider.notifier).updateApiUrl(url)` — it has zero
knowledge of storage keys, SharedPreferences, or FlutterSecureStorage.

`features/settings/settings_service.dart` is **deleted** (not refactored).
Its tests move to `test/core/config/app_config_service_test.dart`.

- `features/api_sync/api_config.dart` derives `ApiConfig` from
  `core/config/app_config_provider.dart` — no settings import.
- `app/router.dart` can import from `core/` freely.

This eliminates **all four import violations** (B2, B3, B4, B5) by establishing
core as the single owner of shared state AND shared persistence.

### StreamController Lifecycle (T2)

The `_elapsedController` in `RecordingServiceImpl` must maintain a stable identity
across the service's entire lifecycle. The contract says `elapsed` is a broadcast
stream — subscribers can listen before `start()` is called and remain subscribed
across multiple recording sessions.

**Fix:** Do NOT close `_elapsedController` in `_cleanup()`. The controller is
treated as an **app-lifetime singleton** — it is created once and never closed.
The `_cleanup()` method cancels the timer and resets `_startTime`/`_currentPath`,
but the stream stays open and simply stops emitting until the next `start()`.

No `dispose()` method is added. The `RecordingService` interface is not extended.
The `recordingServiceProvider` is a plain `Provider<RecordingService>` with no
`ref.onDispose` — the service lives for the entire app lifetime, and the
`StreamController` is garbage-collected with it. This is a conscious design
choice: recording is a core app capability, not a transient resource.

This preserves the subscription chain:
```
controller subscribes → service.elapsed (stable stream identity)
  start() → timer fires → controller adds to stream
  stop() → timer cancelled → stream goes quiet (NOT closed)
  start() → new timer → stream resumes emitting
  (app termination) → GC cleans up controller + stream
```

**Test:** `start→stop→start→stop` produces elapsed events in both sessions on the
same stream subscription.

### Sync Queue Resend Model (T3)

**Invariant: at most one active sync_queue row per transcript.**

A transcript can have zero or one sync_queue entries:
- Zero: transcript was sent (or was never queued)
- One with status `pending`/`sending`/`failed`: transcript is in the sync pipeline

Resend reactivates the **existing failed row**, not creates a new one.

**Fix:** Replace the broken `resendItem` flow with:

```
StorageService.reactivateForResend(String transcriptId)
  → UPDATE sync_queue SET status = 'pending', attempts = 0,
    last_attempt_at = NULL, error_message = NULL
    WHERE transcript_id = ? AND status = 'failed'
```

This is an update/reset, not an insert. It:
- Resets attempts to 0 (fresh retry cycle)
- Clears error message
- Only affects `failed` rows (no-op if already pending/sending)
- Preserves the one-row-per-transcript invariant

`HistoryNotifier.resendItem(transcriptId)` calls this method directly.

**Acceptance criteria:**
- After resend, `getTranscriptsWithStatus` returns exactly one row for that
  transcript with status `pending` (not duplicated)
- Resending an already-pending transcript is a no-op

### History Detail Route (T4c)

Add a child route under `/history` for the detail screen:

```
GoRoute(
  path: '/history',
  builder: ... HistoryScreen,
  routes: [
    GoRoute(
      path: ':id',
      builder: (context, state) {
        final id = state.pathParameters['id']!;
        return TranscriptDetailScreen(transcriptId: id);
      },
    ),
  ],
)
```

- Path: `/history/:id` — transcript ID as path parameter
- `TranscriptDetailScreen` loads data from `StorageService.getTranscript(id)` +
  sync status query
- Bottom navigation bar stays visible (child route within History branch)
- Navigation: `context.push('/history/${item.id}')` instead of `Navigator.push`
- Works after cold start — data loaded from local SQLite, no server needed

### Test Connection Contract (T4d)

Create a separate `ApiClient.testConnection(url, token)` method that does NOT use
the transcript POST contract. The test connection sends:

```http
POST {url}
Authorization: Bearer {token}
Content-Type: application/json

{ "test": true }
```

This is a dedicated method, not a modification of `ApiClient.post()`. The production
`post()` contract remains unchanged. `SettingsScreen` calls `testConnection` instead
of `post`.

Returns the same `ApiResult` sealed type for response classification.

---

## Affected Mutation Points

| File | Change |
|------|--------|
| `lib/features/recording/domain/transcript_result.dart` | Move to `lib/core/models/transcript_result.dart` |
| `lib/core/providers/api_url_provider.dart` | Move to `lib/core/config/api_url_configured_provider.dart`, read from core config |
| `lib/features/api_sync/api_config.dart` | Read from `core/config/` instead of `features/settings/` |
| `lib/features/settings/settings_service.dart` | **Deleted** — persistence moves to `core/config/app_config_service.dart` |
| `lib/features/settings/settings_provider.dart` | **Deleted** — replaced by `core/config/app_config_provider.dart` |
| `lib/features/settings/settings_model.dart` | **Deleted** — replaced by `core/config/app_config.dart` (nullable copyWith fix applied to the new model in T4b) |
| `lib/features/settings/settings_screen.dart` | Remove import of `sync_provider.dart`, use `ApiClient.testConnection` |
| `lib/features/recording/data/recording_service_impl.dart` | Keep `_elapsedController` open (app-lifetime singleton, no dispose) |
| `lib/core/storage/storage_service.dart` | Add `reactivateForResend(String transcriptId)` |
| `lib/core/storage/sqlite_storage_service.dart` | Implement `reactivateForResend` as UPDATE, implement `getTranscriptsWithStatus` |
| `lib/features/history/history_notifier.dart` | Call `reactivateForResend` instead of `markPendingForRetry` |
| `lib/features/history/history_screen.dart` | Use `context.push('/history/$id')` instead of `Navigator.push` |
| `lib/app/router.dart` | Add `/history/:id` child route |
| `lib/core/network/api_client.dart` | Fix `~/ 1000`, add `testConnection()` method |
| All test files importing `TranscriptResult` | Update import path |

---

## Tasks

| # | Task | Layer | Issues Fixed |
|---|------|-------|-------------|
| T1 | **Fix architecture: establish core/config ownership.** Move `TranscriptResult`/`TranscriptSegment` to `core/models/`. Create `core/config/` with `AppConfig` model, `AppConfigService` (sole persistence adapter — replaces `features/settings/settings_service.dart`), `appConfigProvider` (StateNotifier), `apiUrlConfiguredProvider` (derived). Delete `settings_service.dart`, `settings_provider.dart`, `settings_model.dart` from features/settings/. `SettingsScreen` becomes pure UI calling `appConfigProvider.notifier`. Refactor `features/api_sync/api_config.dart` to read from `core/config/`. Remove all cross-feature imports. Update all import paths. Verify: `grep -r "import.*features/" lib/features/X/ | grep -v "features/X"` returns empty for every X. `grep -r "import.*features/" lib/core/` returns empty. Move `settings_service_test.dart` to `test/core/config/app_config_service_test.dart`. | core, features, app | B2, B3, B4, B5 |
| T2 | **Fix StreamController lifecycle.** Keep `_elapsedController` open across recording cycles — treat service as app-lifetime singleton. `_cleanup()` stops the timer but does NOT close the stream. No `dispose()` added — `RecordingService` interface unchanged, provider has no `ref.onDispose`. Update `RecordingServiceImpl` tests: verify `start→stop→start→stop` produces elapsed events in both sessions on the same subscription. | features/recording | B1 |
| T3 | **Fix resend: reactivate existing failed row.** Add `StorageService.reactivateForResend(String transcriptId)` — UPDATE sync_queue SET status='pending', attempts=0, error=NULL WHERE transcript_id=? AND status='failed'. Update `HistoryNotifier.resendItem` to call it. Add tests: resend changes failed to pending, resend is no-op for pending, no duplicate rows after resend, `getTranscriptsWithStatus` returns one row per transcript after resend. | core/storage, features/history | I1 |
| T4 | **Fix misc important issues.** (a) `ApiClient`: `/ 1000` → `~/ 1000`. (b) `AppConfig.copyWith` (in `core/config/app_config.dart`, the new model from T1): use `Object` sentinel for nullable fields so they can be set back to null. (c) History detail: add `/history/:id` child route, load from StorageService, use `context.push`. (d) Test connection: add `ApiClient.testConnection(url, token)` as separate method, update `SettingsScreen` to use it instead of `post()`. | core/network, core/config, features/settings, features/history, app | I3, I4, I5, I6 |
| T5 | **Add missing tests.** `getTranscriptsWithStatus` storage integration test (status derivation). `HistoryNotifier` unit tests (loadNextPage, refresh, delete, resend). `AppConfigService` round-trip test with mocked SharedPreferences. | test/ | Coverage gaps |

---

## Test Impact

### Existing tests affected
- All tests importing `TranscriptResult` from `features/recording/domain/` → update import to `core/models/`
- `RecordingServiceImpl` tests: add multi-session test
- App/router tests: may need update for new `/history/:id` route

### New tests
- `test/features/recording/data/recording_service_impl_test.dart` — multi-session stream stability test
- `test/core/storage/sqlite_storage_service_test.dart` — `reactivateForResend` (no duplicates, only affects failed), `getTranscriptsWithStatus` (status derivation)
- `test/features/history/history_notifier_test.dart` — state transitions for all methods
- `test/core/config/app_config_service_test.dart` — persistence round-trip (replaces settings_service_test)

---

## Acceptance Criteria

1. `flutter analyze` exits with zero issues.
2. `flutter test` passes — all tests green.
3. Zero cross-feature imports: `grep -r "import.*features/" lib/features/X/ | grep -v "features/X"` returns empty for every feature X.
4. `core/` does not import from `features/` or `app/`.
5. Recording works across multiple start/stop cycles — elapsed stream emits in both sessions on the same subscription.
6. History resend reactivates the existing failed row (UPDATE, not INSERT). After resend, exactly one sync_queue row exists for that transcript with status `pending`.
7. Resending an already-pending transcript is a no-op (no duplicate).
8. History detail screen is at `/history/:id`, loads from StorageService, preserves bottom navigation bar.
9. `ApiClient.testConnection` exists as a separate method from `post()`. `SettingsScreen` uses `testConnection`, not `post`.
10. `getTranscriptsWithStatus` correctly derives sent/pending/failed status.

---

## Risks

| Risk | Mitigation |
|------|------------|
| Moving `TranscriptResult` to core/ breaks many imports | Mechanical find-and-replace, verified by `flutter analyze` |
| Restructuring providers may break provider dependency graph | Run full test suite after each change |
| `reactivateForResend` UPDATE may affect non-failed rows | WHERE clause guards with `AND status = 'failed'` |
| `/history/:id` route requires loading transcript from DB | Acceptable latency — local SQLite query is sub-millisecond |

---

## Known Compromises and Follow-Up Direction

### Backoff retry still not implemented
`_promoteEligibleRetries()` remains a no-op. Implementing it requires adding
`getFailedItems()` to StorageService and time-aware retry logic. Tracked as a
separate enhancement, not a bug fix.

### History detail is local-only
`/history/:id` loads from local SQLite. Works after cold start (data persists
locally). No server-side resolution — if the transcript is deleted from the device,
the route shows an error. Acceptable for MVP.

### Test coverage still incomplete
T5 adds critical path tests but does not cover all gaps (SettingsScreen widget
tests, RecordingController.startRecording, app lifecycle). Those can be added
incrementally in follow-up work.
