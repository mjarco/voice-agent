# ADR-AUDIO-009: Conditional iOS audio session category for background listening

Status: Proposed
Proposed in: P019

## Context

ADR-AUDIO-007 established `ambient` as the audio session category for all audio playback, respecting the iOS hardware silent switch and mixing with other audio. P019 requires background audio processing for wake word detection, which is impossible under the `ambient` category — iOS terminates background audio sessions that use `ambient`. The `playAndRecord` category keeps the process alive but ignores the silent switch.

## Decision

The iOS audio session category is runtime-configurable based on background listening state:

- **Background listening disabled (default):** category remains `ambient` per ADR-AUDIO-007. Silent switch is respected, audio mixes with other apps.
- **Background listening enabled:** category switches to `playAndRecord` via `AudioSessionManager` (a platform channel bridge in `core/background/` to native `AVAudioSession.setCategory()`). Silent switch is ignored while active.

The `AudioSessionManager` manages the app-level AVAudioSession. When background listening is active, the app-level `playAndRecord` session supersedes per-player `AudioContextIOS(category: ambient)` settings. On `stopService()`, the manager reverts to `ambient`.

## Rationale

The `ambient` category cannot keep the app alive in background — iOS explicitly reclaims resources from `ambient` sessions when backgrounded. `playAndRecord` is the only category that supports both microphone input and background execution simultaneously. The silent switch trade-off is acceptable because the user has explicitly opted into background listening.

Audio feedback volume is still controlled by the `AudioFeedbackService.getEnabled()` guard — the audio session category determines *capability*, not *whether sounds play*.

## Consequences

- The iOS hardware silent switch is ignored while background listening is active. Users must disable background listening to restore silent switch behavior. This should be documented in the Settings UI.
- The runtime category switch introduces a potential AVAudioSession reconfiguration race if switching happens during active playback. `setPlayAndRecord()` should be called before any audio capture starts, and `setAmbient()` after all capture stops.
- ADR-AUDIO-007 remains the default for all non-background-listening usage. This ADR documents a conditional override, not a replacement.
