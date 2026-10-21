# ADR-NOTIF-002: Routine reminders keyed by routine and day, within the 32-bit id range

Status: Accepted
Decided in: #357, PR #360
Supersedes: the routine-reminder id formula in item 5 of [ADR-NOTIF-001](./ADR-NOTIF-001-diff-based-reconciliation-with-id-partitioning.md)

## Context

ADR-NOTIF-001 keyed a routine-occurrence reminder by `occurrenceId`:
`3_000_000 + (crc32(occurrenceId) & 0x7FFFFFFF)`. Two facts break it:

- personal-agent's `GET /agenda` returns `occurrence_id: null` for an occurrence that has not been
  acted on yet; the row exists only once the occurrence is done or skipped. The reconciler skipped
  items without an id, so a pending occurrence never got a reminder (#357, found by case T5 of
  `docs/manual-tests/android-pixel-baseline.md` on 2026-10-21).
- `3_000_000 + (crc & 0x7FFFFFFF)` can exceed `0x7FFFFFFF`. `flutter_local_notifications` validates
  ids as 32-bit and throws `ArgumentError`, which aborts the whole reconcile.

## Decision

1. The reminder key is `"$routineId@$scheduledFor"` for every occurrence, whether or not
   `occurrenceId` is set.
2. The id is `3_000_000 + crc32(key) % (0x7FFFFFFF - 3_000_000 + 1)`, always in
   `3_000_000..0x7FFFFFFF`.

The client keeps the personal-agent API as it is (owner, 2026-10-21).

## Rationale

A routine has at most one occurrence per day, so routine and day identify it. The key is known
before personal-agent materialises the occurrence and does not change afterwards, so the reconciler
does not cancel and reschedule the same reminder when the row appears. The modulo keeps the existing
range start and costs nothing in collision terms at the scales of ADR-NOTIF-001.

## Consequences

- Reminders scheduled under the old formula (only materialised, still-pending occurrences) are not
  cancelled by id after an upgrade; they fire once at their time, as they would have.
- If personal-agent ever allows several occurrences of one routine on one day, this key collides
  and must be revisited.
- The rest of ADR-NOTIF-001 (single writer, diff against the in-memory snapshot, ranges for other
  kinds, revocation handling) stands.
