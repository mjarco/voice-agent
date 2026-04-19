# Proposal 007 — Transcript History Screen

## Status: Implemented

## Prerequisites
- Proposal 004 (Local Storage) — provides `transcripts` table, `sync_queue` table, and `StorageService` interface.
- Proposal 005 (API Sync Client) — provides sync-status semantics (sent = no queue row, pending/failed = queue row exists). Resend action re-enqueues via `StorageService.markPendingForRetry`.
- Proposal 008 (App Navigation) — provides the History tab shell route with a placeholder screen that this proposal replaces.

## Scope
- Tasks: ~4
- Layers: features/history, core/storage (read-only query addition)
- Risk: Low — standard list UI with pagination over local data

---

## Problem Statement

After recording and transcribing, users have no way to see what they previously captured,
whether those transcripts were successfully sent, or to take action on failed sends. Without
a history view, the app is fire-and-forget — users cannot verify, retry, or manage their
data.

---

## Are We Solving the Right Problem?

**Root cause:** There is no UI surface for browsing stored transcripts or their sync status.
The data exists in SQLite (Proposal 004), but nothing exposes it to the user.

**Alternatives dismissed:**
- *Notification-based feedback only:* Users would see per-item success/failure as toasts
  but couldn't review past items, retry bulk failures, or copy old transcripts. A list
  view is the standard solution for this use case.
- *Push transcript list into the recording screen:* Overloads the primary recording UI.
  History is a distinct concern that belongs on its own tab.

**Smallest change?** Yes — this proposal adds only the history list UI and its data query.
It does not add search, filtering, or multi-select. Those can be layered on later.

---

## Goals

- Display all transcripts in reverse-chronological order with their sync status (sent, pending, failed)
- Let users take action on individual items: resend failed, copy text, delete
- Support pagination so the list performs well at scale

## Non-goals

- No search or filtering — MVP shows a flat chronological list
- No multi-select or bulk actions — single-item actions only
- No date-based grouping headers — adds complexity without essential value for MVP
- No pull-to-refresh gesture — the list reflects DB state at query time; a `refresh()` method is available for programmatic reload (e.g., after sync completes)

---

## User-Visible Changes

The History tab (from Proposal 008's bottom navigation) shows a scrollable list of past
transcripts. Each item displays: the transcript text (truncated to two lines), a status
indicator (sent / pending / failed), and the creation timestamp. Tapping an item opens a
detail view showing the full text and available actions. Scrolling to the bottom loads the
next page of results.

---

## Solution Design

### List Item Layout

Each item in the list is a `ListTile`-based widget with the following structure:

```
┌─────────────────────────────────────────────────┐
│  "Transcript text truncated to two lines..."    │
│  ● Sent          2026-03-17 14:32               │
└─────────────────────────────────────────────────┘
```

- **Title:** Transcript text, `maxLines: 2`, `overflow: TextOverflow.ellipsis`
- **Subtitle row:** Status indicator (colored dot + label) and formatted timestamp
- **Status colors:** Sent = green, Pending = orange, Failed = red
- **Tap target:** Entire tile navigates to detail view

### Detail View

A full-screen route (pushed, not a tab) showing:
- Full transcript text (scrollable)
- Status indicator
- Timestamp
- Action buttons at the bottom:
  - **Copy** — copies transcript text to clipboard, shows snackbar confirmation. Available on all items.
  - **Resend** — enqueues the item back into `sync_queue` with `pending` status. Only visible when status is `failed`.
  - **Delete** — shows confirmation dialog, then removes transcript and its sync_queue entry. Available on all items.

### Pagination Strategy

Offset-based pagination with 20 items per page:
- `HistoryNotifier` holds `List<TranscriptWithStatus>` and a `currentOffset` counter
- On reaching the end of the list (detected via `ScrollController`), fetch the next page
- Query: `SELECT ... ORDER BY created_at DESC LIMIT 20 OFFSET :offset`
- When no more rows are returned, set a `hasMore = false` flag to stop further loads
- Initial load fetches the first page on screen mount

### Data Query

The history screen needs transcript data joined with sync status. The query joins
`transcripts` with `sync_queue` to derive a per-item status:

```
Contract: TranscriptWithStatus
  - id: String                  // UUIDv4 (matches Transcript.id from 004)
  - text: String
  - createdAt: DateTime
  - status: DisplaySyncStatus (enum: sent, pending, failed)
    // Note: this is a view-level enum, not the storage SyncStatus from 004.
    // "sent" is derived from the absence of a sync_queue row.
```

Query logic (added to storage layer as a StorageService method):
- `LEFT JOIN sync_queue ON transcripts.id = sync_queue.transcript_id`
- If no sync_queue row exists: status = `sent` (it was synced and removed from queue)
- If sync_queue row exists with `status = 'pending'`: status = `pending`
- If sync_queue row exists with `status = 'failed'`: status = `failed`
- Order by `transcripts.created_at DESC`
- `LIMIT :limit OFFSET :offset`

### Provider Structure

```
Feature: lib/features/history/

Providers:
  historyListProvider → StateNotifierProvider<HistoryNotifier, HistoryState>
    - HistoryState: { items: List<TranscriptWithStatus>, isLoading: bool, hasMore: bool }
    - Methods: loadNextPage(), deleteItem(id), resendItem(id), refresh()

  transcriptDetailProvider(id) → FutureProvider.family<TranscriptWithStatus, String>

Widgets:
  history_screen.dart       → Main list screen (plugs into shell from 008)
  history_list_tile.dart    → Single list item widget
  transcript_detail_screen.dart → Full transcript view with actions
```

### Action Behavior

| Action | Precondition | Effect | UI Feedback |
|--------|-------------|--------|-------------|
| Copy | Any item | Copies `text` to system clipboard | Snackbar: "Copied to clipboard" |
| Resend | Status = failed | Updates sync_queue entry to `pending`, triggers sync engine | Status changes to pending, snackbar: "Queued for resend" |
| Delete | Any item | Deletes transcript row and associated sync_queue row | Item removed from list with animation, snackbar with undo (soft delete with 5s timer) |

---

## Affected Mutation Points

| File / Area | Change |
|------------|--------|
| `lib/core/storage/` (from 004) | Add StorageService method for paginated transcript-with-status query |
| `lib/app/router.dart` (from 008) | Add route for transcript detail screen |
| `lib/features/history/` | New directory — all history UI and providers |

---

## Tasks

| # | Task | Layer |
|---|------|-------|
| T1 | Add `getTranscriptsWithStatus(limit, offset)` StorageService method to storage layer. Returns `List<TranscriptWithStatus>` using the LEFT JOIN query. Add `TranscriptWithStatus` model and `SyncStatus` enum to `core/models/`. Include unit test with in-memory database verifying correct status derivation and pagination. | core/storage, core/models |
| T2 | Create `HistoryNotifier`, `HistoryState`, and `historyListProvider`. Implement `loadNextPage()`, `refresh()`, `deleteItem()`, `resendItem()` methods. Include unit tests for state transitions (loading, loaded, pagination exhausted, delete removes item, resend changes status). | features/history |
| T3 | Create `HistoryScreen` with paginated `ListView.builder`, `HistoryListTile` widget, empty state, and loading indicator. Wire to `historyListProvider`. Create `TranscriptDetailScreen` with full text, status, and action buttons (copy, resend, delete). Add detail route to router. Include widget tests for: list renders items, scroll triggers pagination, empty state shown when no items, detail screen shows actions conditionally. | features/history, app |
| T4 | Implement delete-with-undo flow (soft delete with 5s undo snackbar). Implement copy-to-clipboard with snackbar feedback. Implement resend action (update sync_queue status). Include widget tests for action feedback (snackbar appears, undo restores item). | features/history |

---

## Test Impact

### Existing tests affected
None — no existing history tests. The new StorageService method in core/storage extends the storage
layer but does not modify existing methods.

### New tests
- `test/core/storage/transcript_status_query_test.dart` — storage query returns correct status from join, respects pagination limits and offsets
- `test/features/history/history_notifier_test.dart` — state transitions for load, paginate, delete, resend
- `test/features/history/history_screen_test.dart` — widget tests for list rendering, empty state, scroll-to-load
- `test/features/history/transcript_detail_screen_test.dart` — widget tests for action buttons visibility and behavior

---

## Acceptance Criteria

1. `HistoryScreen` displays transcripts in reverse-chronological order.
2. Each list item shows transcript text (truncated to two lines), a colored status indicator (green/orange/red), and a formatted timestamp.
3. Scrolling to the bottom of the list loads the next 20 items without blocking the UI.
4. When no transcripts exist, the screen shows an empty-state message.
5. Tapping a list item navigates to a detail screen showing the full transcript text.
6. The Copy action places the transcript text on the system clipboard and shows a snackbar.
7. The Resend action is only visible for items with `failed` status and changes the status to `pending`.
8. The Delete action shows a confirmation, removes the item, and provides a 5-second undo snackbar.
9. `flutter test` passes with all new tests (storage, notifier, widget).
10. `flutter analyze` exits with zero issues.

---

## Risks

| Risk | Mitigation |
|------|------------|
| Offset-based pagination becomes slow with very large datasets (10k+ rows) | SQLite handles OFFSET efficiently with indexed `created_at`. If performance degrades, switch to cursor-based (keyset) pagination using `created_at < :lastSeen` in a follow-up. |
| LEFT JOIN query returns stale status if sync engine updates between page loads | Acceptable for MVP — the list reflects status at query time. Riverpod watch on sync state provider can trigger a `refresh()` call when sync completes, which reloads from page 0. |
| Delete-with-undo complexity (soft delete timing, undo after navigating away) | Keep undo simple: undo only works while the snackbar is visible. If user navigates away, deletion is finalized immediately. |

---

## Known Compromises and Follow-Up Direction

### No search or filtering (V1 pragmatism)
Users can only scroll through a chronological list. For MVP this is acceptable — the
primary use case is checking recent items. If the history grows large, add a search bar
and status filter chips in a follow-up proposal.

### No date-based grouping headers
Grouping by "Today", "Yesterday", etc. adds visual polish but requires timezone-aware
date math and sticky headers. Deferred to a UI polish pass. The timestamp on each item
provides sufficient context.

### DB-snapshot update model, not live subscription
The list reflects database state at query time. It does not subscribe to live sync
events. Updates happen when: (a) the user navigates to the History tab (initial load),
(b) `HistoryNotifier.refresh()` is called programmatically (e.g., sync worker can call
this after completing a batch), or (c) the user performs an action (delete, resend).
Real-time streaming from the database can be added later with a stream-based query
mechanism (or by migrating to Drift).
