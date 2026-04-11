# ADR-PLATFORM-002: Cancel-on-background policy for recording

Status: Accepted
Proposed in: P001, P012

## Context

Mobile operating systems reclaim audio hardware when an app moves to the background. On iOS, the microphone is forcibly released unless the app holds a background audio session entitlement (`UIBackgroundModes: audio`). On Android, foreground services are required to keep recording alive.

When the user switches apps or locks the screen during an active recording or hands-free session, the app must choose a response:

- **Pause and resume** — save partial audio, resume when foregrounded. Requires background audio entitlements and complex state recovery.
- **Save what you have** — stop recording, transcribe the partial audio, save the result.
- **Cancel** — discard the recording and any in-progress state.

## Decision

Cancel everything on background. Specifically:

- **Manual recording** (`RecordingController.didChangeAppLifecycleState`): calls `cancelRecording()`, which deletes the partial WAV file and returns to idle state.
- **Hands-free session** (`HandsFreeController.didChangeAppLifecycleState`): calls `_terminateWithError('Interrupted: app backgrounded')`, which stops the engine and transitions to an error state requiring user action to restart.

Both controllers implement `WidgetsBindingObserver` and react to `AppLifecycleState.paused`.

## Rationale

Attempting to save partial audio adds complexity (partial transcription, truncated WAV handling) for a scenario that produces low-quality results. Background audio entitlements add platform-specific configuration, App Store review complications, and battery drain. The simplest safe behavior — cancel and discard — prevents orphaned recording state and corrupted files.

## Consequences

- Users lose in-progress recordings if they switch apps or lock the screen.
- No background audio entitlements needed — simpler platform configuration.
- Hands-free requires manual restart after backgrounding — the error state communicates what happened.
- No partial audio files left on disk after backgrounding.
- If background recording is needed later, this decision must be reversed with platform entitlements and state recovery logic.
