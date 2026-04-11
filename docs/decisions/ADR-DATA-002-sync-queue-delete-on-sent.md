# ADR-DATA-002: Sync queue state machine with delete-on-sent

Status: Accepted
Proposed in: P004, P009

## Context

The app queues transcripts for sync to the backend API. The sync queue needs a state machine to track each item's delivery lifecycle. Two approaches:

- **Keep all states** — track `pending`, `sending`, `sent`, `failed` as persisted states. History queries join on the state.
- **Delete on success** — only persist `pending`, `sending`, `failed`. Successful delivery deletes the row. "Sent" is inferred from absence.

Additionally, P009 code review identified a race condition: multiple sync_queue rows could exist for the same transcript (e.g., user resends while original is still queued).

## Decision

Sync queue state machine: `pending -> sending -> (row deleted)` or `sending -> failed -> pending (retry)`.

- `markSent()` deletes the sync_queue row rather than updating status.
- `SyncStatus` enum: `{ pending, sending, failed }` — no `sent` value.
- `DisplaySyncStatus` enum (view-level, history feature only): `{ sent, pending, failed }` — derives "sent" from LEFT JOIN absence.
- At most one sync_queue row per transcript. Resend reactivates the existing failed row via UPDATE (`reactivateForResend`), never INSERT.

## Rationale

Deleting sent rows keeps the queue table small and makes "what still needs syncing?" a trivial query. The at-most-one invariant prevents duplicate deliveries and simplifies the worker's item selection logic.

## Consequences

- "Sent" is never a persisted state — history screen derives it from a LEFT JOIN.
- Resend is an UPDATE (reset attempts, clear error) not an INSERT.
- No delivery audit trail in the sync_queue — if needed later, a separate log table would be required.
- Worker polls `pending` items with backoff eligibility; no per-item timers.
