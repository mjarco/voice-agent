# ADR-NOTIF-001: Local notifications via diff-based reconciliation with reserved ID partitioning

Status: Proposed
Proposed in: P040

## Context

P040 introduces scheduled OS notifications for two purposes:

- Fixed-time daily summaries of action-item activity (four per day).
- Per-occurrence reminders for routine occurrences with a `start_time`.

Push notifications via APNs / FCM were dismissed early: there is no Apple Developer account ([[project_no_apple_developer_account]]), and FCM alone would split behavior across iOS and Android. Local notifications are the only available delivery mechanism.

`flutter_local_notifications` provides scheduling, cancellation, and a `pendingNotificationRequests()` query. The query returns notification IDs reliably across platforms but **body, title, and `fireAt` fields are platform-inconsistent**: iOS returns them, Android may return null depending on whether the notification was scheduled via `zonedSchedule` or recovered from on-disk persistence. Building a value-stable diff against the OS queue using the plugin's API alone is unreliable.

The proposal needs to be re-run from several triggers (foreground fetch, app-resume staleness check, workmanager periodic task, hands-free session-end). Each trigger produces a "desired set" of notifications computed from today's `AgendaResponse`. The reconciliation strategy must:

1. Be idempotent — re-running with the same input yields zero plugin writes.
2. Catch body drift — when summary counts change between reconciles, the OS queue must reflect the new copy.
3. Tolerate cold start — the in-process state may be empty while the OS queue is populated from a prior run.
4. Avoid swap-window duplicate display — `cancelAll()` + reschedule risks duplicate delivery during the cancel/schedule gap.

A naive "schedule everything every time" approach was considered and rejected: the OS treats it as new traffic each cycle (affecting delivery rate-limit accounting and badge counts) and produces flicker on devices that surface a notification toast on schedule.

## Decision

OS notification scheduling in voice-agent is governed by six rules.

1. **Local notifications only.** No APNs / FCM until the Apple Developer constraint changes.
2. **Single writer.** `LocalNotificationService` (in `core/notifications/data/`) is the only code path that calls `FlutterLocalNotificationsPlugin.schedule()`, `.cancel()`, or `.cancelAll()`. Any other call site is an architectural violation.
3. **Single reconciler.** `AgendaNotificationScheduler` (in `core/notifications/`) is the only code path that calls into `LocalNotificationService` write methods. Feature code triggers a reconcile; it does not schedule directly.
4. **Diff-based reconciliation against an in-memory snapshot.** `LocalNotificationService` maintains a `Map<int, ScheduledNotification> _scheduled` updated on every `schedule()` / `cancel()` / `cancelAll()` call. The reconciler diffs the desired set against this map (not against `pendingNotificationRequests()`), using value-equality on `(id, title, body, fireAt, payload)`. Mismatches trigger cancel + schedule. The plugin's `schedule()` replaces an existing notification with the same ID, so re-scheduling is safe.
5. **Reserved ID partitioning.** Each notification kind owns a disjoint integer range:
   - `1000–1003` — fixed-time daily summaries (`Morning`, `Noon`, `Afternoon`, `Evening`).
   - `2_000_000–2_999_999` — reserved for per-item action-item reminders (P041 follow-up).
   - `3_000_000+` — routine-occurrence reminders, ID = `3_000_000 + (crc32(occurrenceId) & 0x7FFFFFFF)`.
   Future kinds claim a new range and amend this ADR.
6. **Permission revocation handling.** On every reconcile, `LocalNotificationService.isPermitted()` is checked. If it returns false after previously returning true (revocation observed), the service calls `cancelAll()` once to clean the OS queue and clears the in-memory snapshot. Subsequent reconciles short-circuit until permission is re-granted.

Session gating (`sessionActiveProvider == true` suppresses per-occurrence reminders; summaries always fire) is part of the reconciler's desired-set computation, not a separate writer. See P027 for the `sessionActiveProvider` contract.

## Rationale

**Single writer + diff-based reconciliation** mirrors ADR-DATA-002 (sync-queue-delete-on-sent), which establishes a sole-writer invariant for the `sync_queue` state machine. The principle generalizes: when an authoritative state lives outside the app's full control (the OS notification queue), funnel all writes through one component that owns the diff invariant. Parallel writers cause exactly the duplicate-delivery and stale-body problems the proposal exists to avoid.

**In-memory snapshot as the diff source** is forced by platform reality. `pendingNotificationRequests()` cannot be trusted for value-stable diff because field availability varies by platform and by how the notification was scheduled. Maintaining a parallel in-process map is the cheapest portable solution. The cost is a one-time rebuild after force-quit: the cold-start map is empty, so the first reconcile post-launch schedules every desired entry; the plugin replaces existing entries by ID, producing no user-visible flicker.

**Diff-based instead of cancel-all-then-reschedule** preserves OS-side delivery accounting. Cancelling all pending notifications and re-scheduling them treats every reconcile as fresh traffic, affecting badge counts, lockscreen grouping, and delivery rate-limits. Diff-based reconciliation is invisible to the OS when the desired set is unchanged.

**Reserved ID partitioning** prevents collisions between notification kinds without requiring the reconciler to track which kind owns which ID. CRC32 over UUID strings gives stable IDs across runs at a negligible collision probability for the scales involved (~10⁻⁵ at ~200 simultaneously scheduled IDs; the plugin replaces on collision, so the consequence is silent loss of the older notification — logged at debug level). Pre-reserving the action-item range (2M–3M) ahead of P041 means future work doesn't need to re-number anything.

**Permission revocation handling** closes a long-tail debugging surface: if a user grants permission, the app schedules notifications, then the user revokes permission in OS settings, the OS-side queue still contains the entries (they just won't fire). Without the false-after-true cleanup, the in-memory snapshot and the OS queue would diverge permanently.

## Consequences

- The reconciler's correctness depends on the in-memory snapshot being preserved across reconciles **within a process lifetime**. After force-quit-and-relaunch, the snapshot is empty; the first reconcile overwrites every entry. This is intentional, not a bug.
- Background isolate (workmanager) starts with an empty snapshot too. Its first reconcile per spawn schedules the full desired set; the plugin's replace-on-id semantics means OS-side state is unchanged when desired equals current.
- A new notification kind requires:
  1. A new reserved ID range documented in this ADR.
  2. An extension to `AgendaNotificationScheduler`'s desired-set computation (or a new reconciler if the kind is sufficiently distinct).
  3. New cases in the reconciler diff tests.
- The "sole writer" and "sole reconciler" invariants are enforced by code review, not by language constructs. PR reviewers must flag any direct call to `FlutterLocalNotificationsPlugin` outside `LocalNotificationService`, and any call into `LocalNotificationService.schedule` / `.cancel` / `.cancelAll` outside the reconciler.
- `LocalNotificationService` is stateful (the in-memory map). **In the foreground process** it must be a Riverpod-managed singleton at app scope (one instance for the lifetime of the app). Tests using `ProviderScope` overrides inject a `FakeNotificationService` that maintains its own map for assertion.

  **In the workmanager background isolate** (per ADR-PLATFORM-007 — "no `ProviderContainer` in isolates"), `LocalNotificationService` is constructed once per task spawn via `coreBoot()` and used directly. The in-memory snapshot is fresh per spawn; the plugin's replace-on-id semantics make this safe — the first reconcile per spawn re-schedules every desired entry, and the OS replaces existing entries by ID with no user-visible flicker. This asymmetry (singleton in foreground, fresh-per-spawn in background) is by design: the foreground needs snapshot stability across many reconciles within one process; the background needs only one reconcile per spawn, and Riverpod is unavailable.
- Permission revocation cleanup costs one `cancelAll()` and one in-memory clear. This may briefly desync from any in-flight reconciliation; the next reconcile sees an empty current set and an empty desired set (because the short-circuit fires first), so the steady state is correct.
- Future cross-platform notification libraries (if the project ever migrates off `flutter_local_notifications`) must preserve the value-stable diff property of the adapter. Adapters that don't expose a reliable "what's pending?" query must implement the in-memory snapshot pattern documented here.
- This ADR does not address notification *actions* ("Mark done" inline, etc.). Those would require a platform-channel handshake from a background context to feature-level mutation code; out of scope for V1, tracked in P040's known compromises.

## Related ADRs

- ADR-DATA-002 (sync-queue-delete-on-sent) — spiritual analog: sole-writer invariant over a state machine.
- ADR-ARCH-008 (ephemeral cross-feature state) — `sessionActiveProvider` is the gating signal the reconciler reads.
- ADR-NET-002 (foreground-only sync, amended in P040) — authorizes the workmanager periodic trigger that runs this reconciler hourly.
- ADR-PLATFORM-007 (shared core boot helper) — `NotificationService` is constructed via `coreBoot()` so foreground and isolate paths share the same instance shape.
