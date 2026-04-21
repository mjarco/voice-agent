# ADR-AUDIO-009: Conditional iOS audio session category tied to hands-free session lifecycle

Status: Accepted
Proposed in: P019
Amended in: P026

## Context

ADR-AUDIO-007 established `ambient` as the audio session category for all audio playback, respecting the iOS hardware silent switch and mixing with other audio. P019 required background audio processing which is impossible under the `ambient` category — iOS terminates background audio sessions that use `ambient`. The `playAndRecord` category keeps the process alive but ignores the silent switch. P026 removes the `backgroundListeningEnabled` setting; the category switch is now tied to active hands-free session state instead of a user toggle.

## Decision

The iOS audio session category is runtime-configurable, driven by hands-free session lifecycle:

- **No active hands-free session (default):** category remains `ambient` per ADR-AUDIO-007. Silent switch is respected, audio mixes with other apps.
- **Active hands-free session:** category switches to `playAndRecord` via `AudioSessionBridge` (a platform channel bridge in `ios/Runner/` to native `AVAudioSession.setCategory()`). Silent switch is ignored while active.

The category switch happens via `BackgroundService.startService()` / `stopService()`, which `HandsFreeController` calls explicitly at session boundaries per ADR-PLATFORM-006. When a session is active, the app-level `playAndRecord` session supersedes per-player `AudioContextIOS(category: ambient)` settings. On `stopService()`, the bridge reverts to `ambient`.

## Rationale

The `ambient` category cannot keep the app alive in background — iOS explicitly reclaims resources from `ambient` sessions when backgrounded. `playAndRecord` is the only category that supports both microphone input and background execution simultaneously. The silent switch trade-off is acceptable because the user has explicitly started a hands-free session.

Audio feedback volume is still controlled by the `AudioFeedbackService.getEnabled()` guard — the audio session category determines *capability*, not *whether sounds play*.

## Consequences

- The iOS hardware silent switch is ignored while a hands-free session is active. Silent switch behavior is restored as soon as the session ends (navigation off the Record tab, force-close, or an error).
- **The category switch must happen BEFORE audio capture starts.** `HandsFreeController` must await `BackgroundService.startService()` (which sets `playAndRecord` on iOS) before invoking `HandsFreeEngine.start()`. Reverse order risks recording in `ambient` category and switching mid-flight, which has produced `allowBluetooth`/`playAndRecord` option loss in past testing. Symmetrically, on session end, await `stopService()` before transitioning state to `HandsFreeIdle`. This ordering requirement is the architectural reason ADR-PLATFORM-006 mandates explicit `startService` / `stopService` calls from the controller rather than a state-listener pattern.
- ADR-AUDIO-007 remains the default for all non-session usage. This ADR documents a conditional override, not a replacement.
