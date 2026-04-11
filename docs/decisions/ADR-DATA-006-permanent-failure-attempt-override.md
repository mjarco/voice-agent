# ADR-DATA-006: Permanent failure discrimination via attempt count override

Status: Accepted
Proposed in: P018

## Context

The sync worker needs to prevent auto-retry of permanently failed items
(e.g., 400 Bad Request, 401 Unauthorized) while allowing retry of
transiently failed items (e.g., 503 Service Unavailable, timeout).
The failure type is determined by `SyncWorker` using the sealed `ApiResult`
type from `ApiClient` (`ApiPermanentFailure` vs `ApiTransientFailure`),
but the retry eligibility check happens in `_promoteEligibleRetries()`
which queries `StorageService`.

`StorageService` is a pure data layer (ADR-ARCH-003) and must not contain
business logic about failure types. The sync queue state machine
(ADR-DATA-002) has three states: `pending`, `sending`, `failed` — adding
a fourth state would violate that ADR.

Options considered:

- **Separate status value** (`permanent_failed`) — adds a fourth state to
  the sync queue state machine, violating ADR-DATA-002's three-state design.
- **Boolean column** (`is_permanent`) — requires a schema migration and
  pollutes the storage layer with business concepts.
- **Attempt count override** — `SyncWorker` sets `attempts = _maxRetries`
  for permanent failures. `getFailedItems(maxAttempts: _maxRetries)`
  naturally excludes them. No schema change, no new state.

## Decision

Use the `overrideAttempts` optional parameter on `markFailed()` to set the
attempt counter to `_maxRetries` for permanent failures. The storage layer
remains unaware of failure types — it only stores and queries numeric
attempt counts. The business rule "permanent failures are non-retriable"
is encoded as "permanent failures have their retry budget exhausted."

## Rationale

This avoids schema changes and preserves the three-state sync queue
machine (ADR-DATA-002). The storage layer stays a pure data layer — it
never interprets failure types. The trade-off (losing the real attempt
count for permanent failures) is acceptable because permanent failures are
terminal; the error message preserves the failure reason for diagnostics.

Users can still manually retry via "Resend" from the History screen,
which calls `reactivateForResend()` and resets attempts to 0.

## Consequences

- The `attempts` column has dual semantics: real attempt count for
  transient failures, synthetic budget-exhaustion for permanent failures.
- `getFailedItems(maxAttempts: N)` is the canonical query for
  retry-eligible items. Any code that queries failed items for retry
  purposes must use this filter.
- If the project later needs to distinguish "gave up after 10 retries"
  from "permanent failure on first try," a separate column or log will
  be needed.
