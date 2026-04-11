# ADR-NET-002: Foreground-only sync with no background processing

Status: Accepted
Proposed in: P005

## Context

Pending transcripts need to reach the user's API. The sync worker could run:

- **Foreground only** — simple periodic timer while the app is open. No platform-specific background APIs needed.
- **Background processing** — `workmanager` or `background_fetch` package to sync when the app is closed. Requires platform configuration (iOS `BGTaskScheduler`, Android `WorkManager`), background mode entitlements, and battery-aware scheduling.

## Decision

Foreground-only sync via `Timer.periodic` (5-second poll interval). No `workmanager`, `background_fetch`, or any background processing package. The worker starts when the shell widget renders (`ref.watch(syncWorkerProvider)` in `AppShellScaffold`), pauses on connectivity loss, and stops when the provider is disposed.

## Rationale

iOS severely restricts background execution (~30 seconds for background tasks, requires `BGTaskScheduler` registration and App Store review justification). The app already requires network for both STT (Groq) and sync — if the user is actively using the app, they're online and the worker syncs immediately. Pending items queue safely in SQLite and drain on next app open.

## Consequences

- Transcripts only sync while the user has the app open — pending items wait until next session.
- No iOS background mode entitlements needed — simpler App Store review.
- No battery drain from background wake-ups.
- Worker lifecycle is tied to the shell widget — if the shell unmounts (e.g., full-screen modal replacing navigator), the worker stops.
- Adding background sync later requires `workmanager` integration and platform-specific configuration.
