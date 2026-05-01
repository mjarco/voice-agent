# ADR-AUDIO-011: Always-on audio capture with engagement gate

Status: Accepted
Proposed in: P038

Supersedes the lifecycle portion of ADR-AUDIO-009. The default-`ambient` and runtime-category-switching framing in ADR-AUDIO-009 reflected a pre-P037 model where the audio session was created on demand. P037 v2 already pinned the session to `playAndRecord` for hardware-button routing; P038 takes the next step: pin the recorder itself.

## Context

P037 v2 (tap-to-engage AirPods control) closed one half of the iOS hardware-routing problem: with `.playAndRecord + .spokenAudio` mode, hardware-button presses reach the app's `MPRemoteCommandCenter` targets even with a hot mic. The other half — *recording from a locked screen* — was left open. Empirically (PRs #277–#282) every smaller mitigation failed:

- Keeping `.playAndRecord` active across disengage and re-calling `setActive(true)` in the click handler — `AudioRecorder.startStream` still rejected with `avfaudio error 2003329396`.
- Synchronously priming the session inside the Swift `MPRemoteCommand` handler (which holds iOS's audio activation token) — same rejection.
- Skipping our `setPlayAndRecord` and letting `record_ios` set its own session — same rejection.
- Activating the audio session at process launch via `AppDelegate.application(launch)` — same rejection.

The root cause is at the I/O-unit level, not the session level: iOS only lets `record_ios` acquire the audio I/O unit from a locked-screen `MPRemoteCommand` callback if the unit was *already attached* before the lock. Our previous lifecycle attached the unit on engage, so the locked-screen click was always too late.

This is the iOS-native pattern for any voice-first app that must work from a locked screen — Voice Memos, Otter, Siri, dictation. They keep the audio engine attached for the lifetime of the app session.

## Decision

After the user's first hands-free engagement of an app session, the `AudioRecorder` PCM stream stays attached for the rest of the process lifetime. Engagement and disengagement no longer drive recorder lifecycle; they drive a chunk-level **capture gate** inside `HandsFreeOrchestrator`:

- **Gate open:** chunks flow into VAD; segments emit `EngineSegmentReady`. Equivalent to old `Listening` behaviour.
- **Gate closed:** chunks are read from the recorder stream and immediately discarded. VAD is not invoked. No segment events emit. `_remainder`, `_speechBuffer`, `_speechFrameCount` / `_captureFrameCount` / `_hangoverCount`, the pre-roll ring, and `_inCooldown` are all reset on close so a stale half-segment cannot leak into the next open window.

The audio session stays in `.playAndRecord` for the entire app session, primed at `AppDelegate.application(launch)` and never switched. `BackgroundService.startService()` / `stopService()` continue to be called for foreground-service notification management, but their iOS-side `setCategory` calls become same-category fast-path no-ops.

Manual recording (separate from hands-free) keeps the legacy full-teardown lifecycle: `HandsFreeController.suspendForManualRecording` calls `engine.stop()`, the manual recorder takes the mic via its own session swap, and `resumeAfterManualRecording` re-runs the first-time orchestrator setup.

## Rationale

iOS does not expose an API to "ask for the audio I/O unit from a locked context if you didn't have it before the lock." Apps that need locked-screen recording solve this by holding the I/O unit continuously. We accept the same compromise:

- The orange recording indicator is visible whenever the orchestrator is running (after first engage).
- The mic stays warm; battery cost is real but modest (PCM stream is ~32 KB/s, well below CPU/RF baselines).

The chunk-level gate preserves the privacy invariant that no audio touches VAD, STT, or the network when the user has not engaged — which is the user-facing contract from P037 v2.

## Consequences

- **First engage must be unlocked.** Users who lock the phone before ever engaging in the current process cannot use the lock-screen-click path. Documented as a known limitation; future "always-ready listening" setting may pre-warm the orchestrator at process launch.
- **Manual recording resets the always-on guarantee.** The first lock-screen click after a manual recording reverts to the old failure mode until the user has performed one foreground engage. Closing this gap requires an `engine.reacquire()` API and is deferred.
- **`EngineError` while gate-closed flips Idle → SessionError.** Today an audio-stream error after disengage cannot affect public state (engine is already torn down). After this ADR it can. This is intended — an audio I/O failure in always-on capture is a session-level error worth surfacing.
- **iOS audio interruptions** (phone call, Siri, alarm) tear down the I/O unit. P037's interruption observers (PRs #281/#282) restore the session, but recovery of the recorder stream itself is best-effort and inherits existing behaviour.
- **`startSession` becomes a fast-path on subsequent calls.** Permission / Groq key / API URL guards still re-validate on each call (they are user-mutable at runtime), but `bg.startService()` and `engine.start()` become no-ops once the orchestrator is running.
- **Privacy contract preserved.** The chunk-level gate guarantees that no audio touches VAD, STT, or the network when the user is not engaged. Pre-roll ring is reset on gate-close so closed-window audio cannot leak into the next segment's pre-roll.

## Relationship to prior ADRs

- **ADR-AUDIO-007** (`ambient` as default): superseded for the entire hands-free codepath. The default-`ambient` posture is no longer accurate; the app keeps `.playAndRecord` active for the process lifetime after first engage.
- **ADR-AUDIO-009** (conditional iOS audio session): the *runtime-switching* portion is superseded. The category-pinning rationale (the silent-switch trade-off, the `BackgroundService` ordering requirement) carries forward.
- **ADR-AUDIO-010** (iOS media button routing constraints): unchanged. The `.playAndRecord + .spokenAudio` combination from P037 still applies and is what makes hardware-button routing work even with the recorder hot.
- **ADR-PLATFORM-006** (foreground service ordering): unchanged in spirit. `startService` is still called before recorder engage on the very first call; subsequent fast-path engages do not re-start the foreground service.
