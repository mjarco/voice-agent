# Proposal 009 — Code Review Fixes

## Status: Approved

## Prerequisites
All proposals 000–008 merged.

## Scope
- Tasks: ~5
- Layers: core, features (recording, transcript, api_sync, history, settings), app
- Risk: Medium — touches every layer, fixes silent bugs

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
  to the right layer, fix ID mismatches, recreate a StreamController.

**Smallest change?** Yes — each fix is targeted at a specific file and does not
change behavior except where bugs are being corrected.

---

## Goals

- Eliminate all architecture violations (no cross-feature imports, no core→features)
- Fix the StreamController reuse bug so recording works across multiple sessions
- Fix the resend ID mismatch so history resend actually works
- Improve code quality in areas flagged by review

## Non-goals

- No new features
- No test coverage additions (separate follow-up)
- No backoff retry implementation (documented as known gap)

---

## User-Visible Changes

- Recording now works correctly across multiple sessions (was broken after first stop/cancel)
- History resend action now actually re-queues the transcript (was silently failing)
- Detail screen preserves bottom navigation bar

---

## Tasks

| # | Task | Layer | Issues Fixed |
|---|------|-------|-------------|
| T1 | **Fix architecture violations:** Move `TranscriptResult` and `TranscriptSegment` from `features/recording/domain/` to `core/models/`. Move `apiUrlConfiguredProvider` from `core/providers/` to `app/` or make it not import features. Restructure `apiConfigProvider` to avoid api_sync→settings import. Extract `ApiClient` usage from `SettingsScreen` to avoid settings→api_sync import. Update all imports. | core, features, app | B2, B3, B4, B5 |
| T2 | **Fix StreamController reuse bug:** In `RecordingServiceImpl`, recreate `_elapsedController` on each `start()` call instead of closing the single instance. Add test: start→stop→start→stop works without error. | features/recording | B1 |
| T3 | **Fix resend ID mismatch:** `HistoryNotifier.resendItem` receives transcript ID but `markPendingForRetry` expects sync_queue ID. Add `StorageService.resendByTranscriptId(String transcriptId)` that re-enqueues the transcript (creates new pending queue item). Update `HistoryNotifier` to call it. Add test. | core/storage, features/history | I1 |
| T4 | **Fix miscellaneous important issues:** (a) Timestamp: `/ 1000` → `~/ 1000` in ApiClient. (b) `AppSettings.copyWith` nullable fields — use sentinel or `Function()` wrapper. (c) `HistoryScreen` detail: use GoRouter instead of `Navigator.push`. (d) Test Connection: add `"test": true` field to distinguish from real transcripts. | core/network, features/settings, features/history | I3, I4, I5, I6 |
| T5 | **Add missing tests:** `getTranscriptsWithStatus` storage integration test. `HistoryNotifier` unit tests (loadNextPage, refresh, delete, resend). `SettingsService` round-trip test with mocked SharedPreferences. | test/ | Coverage gaps |

---

## Test Impact

### Existing tests affected
- All tests importing `TranscriptResult` from `features/recording/domain/` must update import to `core/models/`
- `RecordingServiceImpl` tests need a new multi-session test
- `HistoryNotifier` tests are new

### New tests
- `test/features/recording/data/recording_service_impl_test.dart` — multi-session test
- `test/core/storage/sqlite_storage_service_test.dart` — `getTranscriptsWithStatus` tests
- `test/features/history/history_notifier_test.dart` — state transitions
- `test/features/settings/settings_service_test.dart` — persistence round-trip

---

## Acceptance Criteria

1. `flutter analyze` exits with zero issues.
2. `flutter test` passes — all tests green.
3. Zero cross-feature imports: `grep -r "import.*features/" lib/features/X/ | grep -v "features/X"` returns empty for every feature X.
4. `core/` does not import from `features/` or `app/`.
5. Recording works across multiple start/stop cycles without error.
6. History resend action changes a failed transcript's status to pending.
7. History detail screen preserves bottom navigation bar.
8. `getTranscriptsWithStatus` correctly derives sent/pending/failed status.

---

## Risks

| Risk | Mitigation |
|------|------------|
| Moving `TranscriptResult` to core/ breaks many imports | Mechanical find-and-replace, verified by `flutter analyze` |
| Restructuring providers may break provider dependency graph | Run full test suite after each change |

---

## Known Compromises and Follow-Up Direction

### Backoff retry still not implemented
`_promoteEligibleRetries()` remains a no-op. Implementing it requires adding
`getFailedItems()` to StorageService and time-aware retry logic. Tracked as a
separate enhancement, not a bug fix.

### Test coverage still incomplete
T5 adds critical path tests but does not cover all gaps (SettingsScreen widget
tests, RecordingController.startRecording, app lifecycle). Those can be added
incrementally in follow-up work.
