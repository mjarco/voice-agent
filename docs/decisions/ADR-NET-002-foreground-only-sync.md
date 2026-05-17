# ADR-NET-002: Foreground-only sync with session-active carve-out

Status: Accepted
Proposed in: P005
Amended in: P027, P039 (dev-flavor telemetry flusher exception), P040 (workmanager for agenda notification reconciliation)

## Context

Pending transcripts need to reach the user's API. The sync worker could run:

- **Foreground only** — simple periodic timer while the app is open. No platform-specific background APIs needed.
- **Background processing** — `workmanager` or `background_fetch` package to sync when the app is closed. Requires platform configuration (iOS `BGTaskScheduler`, Android `WorkManager`), background mode entitlements, and battery-aware scheduling.

P026 introduced hands-free sessions that continue running while the phone is
locked (per ADR-PLATFORM-004). Transcripts captured during a locked session
should reach the API without waiting for the user to unlock — but we still
want to avoid general-purpose background sync.

## Decision

Sync runs when the app is foregrounded OR while a hands-free session is
active. The predicate is checked inside `SyncWorker._drain()` at the start of
each iteration; no new background processing package is added.

- Foreground path: unchanged from P005 — `Timer.periodic` (5-second poll
  interval), started when the shell widget renders
  (`ref.watch(syncWorkerProvider)` in `AppShellScaffold`), paused on
  connectivity loss, stopped when the provider is disposed.
- Session-active path: `HandsFreeController` writes a core
  `StateProvider<bool>` (`sessionActiveProvider`) at three lifecycle
  transitions (`startSession`, `stopSession`, `_terminateWithError`).
  `SyncWorker` reads the combined `shouldProcessQueue = foreground OR
  sessionActive` predicate through its constructor callback.
- Immediate drain on session start: `SyncWorker.kickDrain()` is a public,
  idempotent method (short-circuits when `_draining` is true) triggered
  from `ref.listen(sessionActiveProvider, ...)` in `sync_provider.dart` on
  the idle→active edge. This is the canonical pattern for event-triggered
  drains; future triggers (e.g. connectivity-up) reuse it.

## Rationale

The original 30-second iOS background limit no longer applies to the
hands-free path: P026's foreground service (Android) and `playAndRecord`
audio session (iOS `UIBackgroundModes: audio`, see ADR-AUDIO-009 and
ADR-PLATFORM-006) keep the process alive for the full duration of a
hands-free session. Sync riding on that keepalive has the same survivability
as the capture itself — no `BGTaskScheduler` or `workmanager` dependency.

The spirit of the original ADR (no surprise background data usage) is
preserved because the carve-out is conditional on an explicit user action:
the user tapped the Record tab and started a session. The session ends as
soon as they switch tabs or force-close the app, which stops both capture
and sync.

`kickDrain()` is preferred over `await`-ing the next periodic tick because
first-utterance end-to-end latency drops from ~5-10 seconds (up to one poll
gap) to "capture + one HTTP round trip."

Users who do not start a hands-free session see zero behavior change.

## Consequences

- Transcripts sync live during active hands-free sessions — including while
  backgrounded or locked.
- No iOS background mode entitlements are added for this carve-out;
  `UIBackgroundModes: audio` was already declared for hands-free capture.
- Battery impact is additive to P026's (VAD + FG service): periodic network
  activity while a session is active. Stopping the session (tab switch,
  force-close, or error) restores foreground-only behavior.
- TTS playback of replies during backgrounded drain is **temporarily
  foreground-gated in P027** (the Dart `_handleReply()` path checks
  `isAppForegrounded()` before calling `ttsService.speak()`). P028 lifts
  this gate after adding Android `FOREGROUND_SERVICE_MEDIA_PLAYBACK`.
  `latestAgentReplyProvider` is always populated regardless, so the user
  sees the reply on return to foreground even when TTS is gated.
- Worker lifecycle is still tied to the shell widget. If the shell unmounts
  (full-screen modal replacing navigator), the worker stops — session-active
  consumers should be aware of this limitation.
- Future event-triggered drains (connectivity-up, schema migration, etc.)
  should call `SyncWorker.kickDrain()` rather than inventing parallel
  mechanisms.
- Adding true background sync (sync without any active session) still
  requires `workmanager` integration — not planned.

## P039 amendment — dev-flavor telemetry flusher exception

The dev-flavor telemetry flusher in `lib/core/observability/` runs on
its own 10s foreground / 60s background cadence, **unconditional on
`sessionActiveProvider`**.

Justified by:
- **Dev flavor only.** The `stable` build does not include the OTel
  package or the flusher (see ADR-OBS-001). Zero impact on production
  users.
- **Small payloads.** OTLP batches are bounded by the per-cycle row
  limit (50 rows) and span sizes are kilobytes, not megabytes.
- **Observability requires backgrounded delivery** to capture
  lock-screen audio state — the very thing telemetry exists to debug.
  Gating the flusher on `sessionActiveProvider` would lose the data
  whenever the user leaves the app mid-session.

**This exception does not authorise other features to add background
sync without ADR-level justification.** It is narrowly scoped to
dev-flavor observability traffic. See ADR-OBS-001 for the full rule.

## P040 amendment — workmanager for agenda notification reconciliation

A `workmanager` periodic task may fetch today's agenda and update the OS
notification queue while the app is not in any of the previously-authorized
states (not foregrounded, no hands-free session active). The task is
limited to one job — agenda reconciliation — and to one network call —
`GET /agenda` for today's date.

The task is scheduled via `Workmanager().registerPeriodicTask(...)` with a
1-hour frequency hint and `Constraints(networkType: connected)`. iOS routes
this through `BGAppRefreshTask`, which is opportunistic and not guaranteed
to honor the cadence; the proposal accepts that flakiness explicitly. The
foreground "fetch if last sync >1h ago" trigger compensates whenever the
user opens the app.

Justified by:

- **Reconciler freshness requirement.** ADR-NOTIF-001 governs how the app
  maintains an OS-side notification schedule. Without periodic refresh,
  items added through the personal-agent web UI between app opens would
  never produce reminders — defeating the purpose of the feature.
- **Single network surface.** `GET /agenda` is read-only, idempotent, and
  small. No write traffic flows over this path; the carve-out cannot be
  used to drain the sync queue or to do anything other than reconcile.
- **No new entitlements on iOS.** `UIBackgroundModes: fetch` is the only
  addition; the existing `UIBackgroundModes: audio` (P027) remains for
  hands-free capture.
- **Battery-bounded.** WorkManager respects device constraints (network,
  charging-only opt-in available, etc.); the task runs at most once per
  hour and skips when `now - lastAgendaFetchAt < 50 min`.

Consequences:

- `workmanager: ^0.5.2` enters the dependency tree. **This ADR is its
  sole authorization.** Any other use case for `workmanager` (background
  sync, telemetry flush, etc.) requires a separate amendment with
  independent justification.
- Background isolate dependency construction is governed by
  ADR-PLATFORM-007 (shared core boot helper). The reconciler invoked in
  the isolate is the same code path invoked in the foreground; see
  ADR-NOTIF-001.
- `SyncWorker` is **not** affected by this amendment. Transcript sync
  continues to require either foregrounded state or an active hands-free
  session.
- Future features that want background work for **non-agenda** reasons
  still require separate ADR-level justification — the workmanager
  package being present in the project does not generalize the carve-out.

**Third amendment caveat.** This is the third amendment to ADR-NET-002
(P027 session-active, P039 dev-telemetry, P040 workmanager-for-agenda).
If a fourth use case arises, the maintainer should consider restructuring
this ADR — for example, splitting it into a general "sync policy"
statement plus a registered list of approved background exceptions —
rather than adding a fourth narrow carve-out. Each carve-out individually
is justified; collectively they erode the ADR's original "foreground-only"
clarity.
