# ADR-PLATFORM-004: Conditional cancel-on-background — hands-free continues, manual cancels

Status: Accepted
Proposed in: P019
Amended in: P026

## Context

ADR-PLATFORM-002 established an unconditional cancel-on-background policy: all recording and hands-free sessions terminate when the app is backgrounded. P019 introduced background wake word detection and activation-triggered hands-free sessions that need to continue operating in the background. P026 removes the wake word feature but keeps background continuity for any active hands-free session (the user explicitly starts a session by navigating to the Record tab and expects it to continue when the screen is locked).

## Decision (P026 amendment)

Cancel-on-background policy splits by recording mode:

- **Manual recording** (`RecordingController`): cancels on background per ADR-PLATFORM-002 (unchanged).
- **Hands-free session** (`HandsFreeController`): continues across background transitions. The foreground service (Android) and `playAndRecord` audio session (iOS) keep the process alive for the duration of the session.

There is now a single hands-free session type. The previous trigger-source distinction (activation-triggered vs manually-started) and the `backgroundListeningEnabled` opt-in are removed by P026. Background continuity is unconditional for any active hands-free session and is controlled solely by session state, not by user setting or trigger source.

## Rationale

The original rationale for PLATFORM-002 (simplicity, no background entitlements, no state recovery) still holds for manual interactions where the user was looking at the screen. Backgrounding during a manual interaction is likely intentional or accidental — either way, canceling is safe.

P019's wake-word-vs-manual distinction was tied to the assumption that activation-triggered sessions were the primary background use case. P026 establishes that the user's intent is "lock-screen-keeps-listening" for any session they explicitly started — making the trigger-source distinction noise. Removing it eliminates the `_triggeredByActivation` flag, the `backgroundListeningEnabled` gate, and the `wakeWordPauseRequestProvider` coordination, simplifying `HandsFreeController`.

## Consequences

- `HandsFreeController.didChangeAppLifecycleState(paused)` is a no-op.
- The foreground service start/stop is driven by `HandsFreeController.startSession()` and `stopSession()` / `_terminateWithError()` via explicit calls (see ADR-PLATFORM-006).
- Android requires a foreground service with `microphone` type; iOS requires `UIBackgroundModes: audio` entitlement plus `playAndRecord` audio session (see ADR-AUDIO-009).
- Manual recording behavior is unchanged — ADR-PLATFORM-002 applies.
- ADR-PLATFORM-002 remains in effect for its original scope (manual starts). This ADR extends, not replaces, PLATFORM-002.
