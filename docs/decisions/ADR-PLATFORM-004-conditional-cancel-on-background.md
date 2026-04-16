# ADR-PLATFORM-004: Conditional cancel-on-background for activation-triggered sessions

Status: Proposed
Proposed in: P019

## Context

ADR-PLATFORM-002 established an unconditional cancel-on-background policy: all recording and hands-free sessions terminate when the app is backgrounded. P019 introduces background wake word detection and activation-triggered hands-free sessions that must continue operating in the background to fulfill their core purpose (hands-free voice capture without touching the screen).

The unconditional policy must become conditional to support this use case while preserving the safety guarantees of PLATFORM-002 for manual interactions.

## Decision

The cancel-on-background policy (ADR-PLATFORM-002) is refined with a trigger-source distinction:

- **Manual recording** (tap-to-record): still cancels on background (unchanged).
- **Manually-started hands-free session** (user navigates to record tab, session starts on screen mount): still terminates on background (unchanged).
- **Activation-triggered hands-free session** (wake word detection or system shortcut): continues in background. The foreground service (Android) or background audio session (iOS) keeps the process alive.
- **Wake word listening**: continues in background by design — this is the primary purpose of the background service.

The distinction is encoded in a `triggeredByActivation` boolean flag on `HandsFreeController`, set at session start time and cleared at session end. `didChangeAppLifecycleState(paused)` checks this flag before deciding whether to cancel.

All background execution requires explicit user opt-in in Settings (background listening toggle). When background listening is disabled, ADR-PLATFORM-002 applies unconditionally.

## Rationale

The original rationale for PLATFORM-002 (simplicity, no background entitlements, no state recovery) still holds for manual interactions where the user was looking at the screen. Backgrounding during a manual interaction is likely intentional or accidental — either way, canceling is safe.

For activation-triggered sessions, backgrounding is the *expected* state — the user said a wake word while the phone was in a pocket. Canceling would defeat the purpose of the feature.

## Consequences

- `HandsFreeController.didChangeAppLifecycleState()` has two behavioral branches — must be tested for both paths.
- Android requires a foreground service with `microphone` type; iOS requires `UIBackgroundModes: audio` entitlement plus `playAndRecord` audio session (see ADR-AUDIO-009).
- The `triggeredByActivation` flag should be promoted to an enum or passed as the `ActivationEvent` type if additional trigger sources are added in the future.
- ADR-PLATFORM-002 remains in effect for its original scope (manual starts). This ADR extends, not replaces, PLATFORM-002.
