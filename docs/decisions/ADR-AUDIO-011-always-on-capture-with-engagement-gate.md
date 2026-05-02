# ADR-AUDIO-011: Always-on audio capture with engagement gate, volume-button gesture

Status: Accepted
Proposed in: P038

Supersedes the lifecycle portion of ADR-AUDIO-009. ADR-AUDIO-009's runtime category-switching framing reflected the pre-P037 model where the audio session was created on demand. P037 v2 already pinned the session to `.playAndRecord` for hardware-button routing; P038 takes the next step and pins the recorder itself.

## Context

P037 v2 (tap-to-engage AirPods control) closed one half of the iOS hardware-routing problem: `.playAndRecord + .spokenAudio` (rather than the default `.default` mode that iOS treats as a phone call) lets `MPRemoteCommand` events reach the app even with a hot mic — at least for short clicks during a quiet `.playback` window. The other half — recording from a locked screen — was left open. Empirically (PRs #277–#282) every smaller mitigation failed at the I/O-unit acquisition step:

- Keeping `.playAndRecord` active across disengage and re-calling `setActive(true)` in the click handler — `AudioRecorder.startStream` still rejected with `avfaudio error 2003329396`.
- Synchronously priming the session inside the Swift `MPRemoteCommand` handler — same rejection.
- Skipping our `setPlayAndRecord` and letting `record_ios` set its own session — same rejection.
- Activating the audio session at process launch via `AppDelegate.application(launch)` — same rejection.

Root cause: iOS only lets `record_ios` acquire the audio I/O unit from a locked-screen `MPRemoteCommand` callback if the unit was *already attached* before the lock. Our previous lifecycle attached the unit on engage, so the locked-screen click was always too late.

This is the iOS-native pattern for any voice-first app that must work from a locked screen — Voice Memos, Otter, Siri, dictation. They keep the audio engine attached for the lifetime of the app session.

A second empirical finding during implementation: with `.playAndRecord + .spokenAudio` and a hot recorder (mic actively reading chunks), `MPRemoteCommand` delivery is intermittent at best — iOS frequently treats the session as call-mode and rejects hardware-button presses. The original P038 plan assumed MPRemoteCommand would be a reliable engagement gesture; that assumption did not hold.

## Decision

### 1. Always-on audio capture

After the user's first hands-free engagement of an app session, the `AudioRecorder` PCM stream stays attached for the rest of the process lifetime. Engagement and disengagement no longer drive recorder lifecycle; they drive a chunk-level **capture gate** inside `HandsFreeOrchestrator`:

- **Gate open:** chunks flow into VAD; segments emit `EngineSegmentReady`. Equivalent to old `Listening` behaviour.
- **Gate closed:** chunks are read from the recorder stream and immediately discarded. VAD is not invoked. No segment events emit. `_remainder`, `_speechBuffer`, `_speechFrameCount` / `_captureFrameCount` / `_hangoverCount`, the pre-roll ring, and `_inCooldown` are all reset on close so a stale half-segment cannot leak into the next open window.

The audio session stays in `.playAndRecord + .spokenAudio` for the entire app session, primed at `AppDelegate.application(launch)` and never switched. `BackgroundService.startService()` / `stopService()` continue to be called for foreground-service notification management, but their iOS-side `setCategory` calls become same-category fast-path no-ops.

### 2. Volume buttons as the engagement gesture

Hardware volume buttons (iPhone side keys, AirPods stem volume swipe, Apple Watch crown) drive engagement, observed via a KVO on `AVAudioSession.outputVolume` in `VolumeButtonBridge.swift`. This path is NOT gated by the call-mode rule that blocks `MPRemoteCommand`, so presses survive `.playAndRecord` with active mic — including from a locked screen.

- Volume Up → engage (open the gate).
- Volume Down during TTS → interrupt the agent's reply (gate untouched).
- Volume Down while engaged with no TTS → close the gate (mic stays warm).

`MPRemoteCommand` short-click is preserved for **TTS interrupt** (its proven foreground use case) but is no longer an engagement gesture.

### 3. Manual recording stays on the legacy lifecycle

Manual recording (separate from hands-free) keeps the legacy full-teardown lifecycle: `HandsFreeController.suspendForManualRecording` calls `engine.stop()`, the manual recorder takes the mic via its own session swap, and `resumeAfterManualRecording` re-runs the first-time orchestrator setup.

Documented limitation: the first lock-screen press after a manual recording reverts to the old failure mode until the user has performed one foreground engage to re-warm the orchestrator.

### 4. TTS does not swap the audio session

`flutter_tts_service.dart`'s `_acquirePlaybackFocus` / `_releasePlaybackFocus` (the `setActive(false) → setCategory(.playback) → setActive(true)` round-trip from P034 follow-up) are reduced to no-ops. The round-trip tore down the recorder I/O unit, defeating the always-on capture model. Hardware-button routing during TTS now relies on the same `.playAndRecord + .spokenAudio` posture the volume button gesture already uses.

### 5. TTS suspend/resume listener at controller level

The `ttsPlayingProvider → suspendForTts/resumeAfterTts` bridge moved from `RecordingScreen.build()` (Riverpod `ref.listen`) to a direct `ValueNotifier.addListener` in the `HandsFreeController` constructor. The widget-level subscription does not fire reliably when iOS pauses Flutter rendering on a lock screen; ValueNotifier callbacks fire on every value change regardless of UI state.

## Rationale

iOS does not expose an API to "ask for the audio I/O unit from a locked context if you didn't have it before the lock." Apps that need locked-screen recording solve this by holding the I/O unit continuously. We accept the same compromise:

- The orange recording indicator is visible whenever the orchestrator is running (after first engage).
- The mic stays warm; battery cost is real but modest (PCM stream is ~32 KB/s, well below CPU/RF baselines).

The chunk-level gate preserves the privacy invariant that no audio touches VAD, STT, or the network when the user has not engaged — which is the user-facing contract from P037 v2.

The volume-button gesture trades two costs for the lock-screen guarantee:

- The system volume actually changes by one step on each press. Programmatic restore via `MPVolumeView` slider is deferred (would need an in-view-hierarchy MPVolumeView; may flash the volume HUD briefly on lock screen).
- The user has to learn a non-default gesture (volume buttons, not headset click).

Both are acceptable for the hands-free use case where the alternative is "feature does not work from a locked screen."

## Consequences

- **First engage must be unlocked.** Users who lock the phone before ever engaging in the current process cannot use the lock-screen gesture path. Documented limitation; a future "always-ready listening" setting can pre-warm the orchestrator at process launch behind a user toggle.
- **Manual recording resets the always-on guarantee.** First lock-screen press after a manual recording reverts to the old failure mode until one foreground engage re-warms the orchestrator. Closing this gap requires an `engine.reacquire()` API and is deferred.
- **`EngineError` while gate-closed flips Idle → SessionError.** Today an audio-stream error after disengage cannot affect public state (engine is already torn down). After this ADR it can. This is intended — an audio I/O failure in always-on capture is a session-level error worth surfacing.
- **iOS audio interruptions** (phone call, Siri, alarm) tear down the I/O unit. P037's interruption observers (PRs #281/#282) restore the session, but recovery of the recorder stream itself is best-effort and inherits existing behaviour.
- **`startSession` is a fast-path on subsequent calls.** Permission / Groq key / API URL guards still re-validate on each call (they are user-mutable at runtime), but `bg.startService()` and `engine.start()` become no-ops once the orchestrator is running.
- **Privacy contract preserved.** The chunk-level gate guarantees that no audio touches VAD, STT, or the network when the user is not engaged. Pre-roll ring is reset on gate-close so closed-window audio cannot leak into the next segment's pre-roll.
- **Listening tone temporarily disabled.** `AmbientLoopPlayer` (audioplayers package) was re-acquiring the audio session on every `setMode`, killing the recorder. Replacement deferred — needs a tone player that respects the existing shared `AVAudioSession` (likely a small native AVAudioPlayer bridge).

## Relationship to prior ADRs

- **ADR-AUDIO-007** (`ambient` as default): superseded for the entire hands-free codepath. The default-`ambient` posture is no longer accurate; the app keeps `.playAndRecord` active for the process lifetime after first engage.
- **ADR-AUDIO-009** (conditional iOS audio session): the *runtime-switching* portion is superseded. The category-pinning rationale (the silent-switch trade-off, the `BackgroundService` ordering requirement) carries forward.
- **ADR-AUDIO-010** (iOS media button routing constraints): unchanged in spirit. The `.playAndRecord + .spokenAudio` combination from P037 still applies. The empirical finding that `MPRemoteCommand` delivery is unreliable for engagement during a hot mic motivated the volume-button gesture in this ADR — it does not contradict ADR-AUDIO-010, which already documented the call-mode constraint.
- **ADR-PLATFORM-006** (foreground service ordering): unchanged in spirit. `startService` is still called before recorder engage on the very first call; subsequent fast-path engages do not re-start the foreground service.
