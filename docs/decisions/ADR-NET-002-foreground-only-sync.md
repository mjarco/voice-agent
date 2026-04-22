# ADR-NET-002: Foreground-only sync with session-active carve-out

Status: Accepted
Proposed in: P005
Amended in: P027

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
