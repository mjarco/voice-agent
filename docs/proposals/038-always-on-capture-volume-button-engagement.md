# Proposal 038 — Always-on capture with volume-button engagement

## Status: Implemented as experiment on `experiment/volume-button-engage` (2026-05-02). Replaces / consolidates the never-merged P038 draft (PR #283) and the post-review T0 pre-flight risk that landed empirically on the device.

## Origin

P037 v2 closed the AirPods short-click engagement path for the foreground case but left **lock → click → capture** broken: `AudioRecorder.startStream` rejects with `avfaudio error 2003329396` when called from a locked-screen `MPRemoteCommand` callback. PRs #277–#282 tried five smaller mitigations (keep `.playAndRecord` active across disengage; prime in the Swift handler; skip our `setPlayAndRecord`; AppDelegate-launch prime; conservative reactivation). All failed at the I/O-unit acquisition step.

The P038 design pivot was to keep the recorder running for the lifetime of the app session and gate audio chunks at the orchestrator level. The **gesture**, however, did not work via `MPRemoteCommand` — iOS uniformly blocks media-button delivery while `.playAndRecord` has an active mic engine, regardless of `mode`. The user proposed a different gesture: **iPhone / AirPods volume buttons**, observed via `AVAudioSession.outputVolume` KVO. Empirically that path is not gated by the call-mode rule and survives a locked screen with a hot mic.

## Goals (achieved)

1. **lock → press → capture** works on iPhone after the user has engaged at least once during the current app session. ✓ Verified on device.
2. The Dart-level engagement contract is unchanged: a captured segment only flows into VAD → STT → backend → TTS when the user has explicitly engaged. ✓ (chunk-level gate)
3. Privacy: no audio bytes touch VAD or the network when the gate is closed. ✓ (orchestrator early-returns in `_enqueueChunk`; pre-roll cleared on close)
4. Auto-resume after TTS reply opens the gate again. ✓ (subject to `_pendingConversationResume` flag — cold TTS does not engage)
5. Existing P037 v2 invariants hold: public state machine `Idle / Listening / Error`, jobs preserved across `HandsFreeIdle`. ✓

## Non-Goals

- Recording from the lock screen *before* the user has ever engaged in the current process (the orchestrator must be warmed by an unlocked engage first).
- Keeping the AirPods short-click as an engagement trigger. P037 v2's MPRemoteCommand path is preserved but is empirically unreliable for engagement during a hot mic — kept only for **TTS interrupt** (its proven use case).
- A drop-in replacement for the disabled `AmbientLoopPlayer` listening tone — that work is deferred (see *Known Compromises*).

## User-Visible Changes

- **Volume Up = engage** (start hands-free listening). Toast: "Listening". Light haptic.
- **Volume Down behavior is contextual:**
  - During TTS playback → interrupts the agent's reply, leaves the gate state alone (auto-resume after TTS will fire on completion as usual).
  - While engaged with no TTS → suspends listening (closes the gate; mic stays warm but no STT/API).
- **iOS recording indicator** (orange dot / pill) is **continuously visible** after the first engage of an app session. This is the privacy-indicator cost of the always-on capture model.
- **First engagement of an app session must be performed unlocked.** After that, the user can lock the phone and engage from the lock screen with a Volume Up press.
- The system volume **does change** when the user presses volume buttons — we do not yet restore it programmatically (see *Known Compromises*).

## Solution Design (as shipped)

### Engagement gesture: hardware volume buttons

A new native bridge `ios/Runner/VolumeButtonBridge.swift` registers a KVO observer on `AVAudioSession.outputVolume`:

- On each observed change, classify direction by comparing the new value to the previously observed value (NOT to `change[.oldKey]`, which is sometimes equal to `newKey` on the first observation).
- A small `_stepThreshold` filter (0.001) suppresses noise / programmatic restore artifacts.
- Direction → `"up"` or `"down"` event posted to the Dart side via `EventChannel("com.voiceagent/volume_button/events")`.

Dart-side `VolumeButtonPort` / `VolumeButtonService` / `volumeButtonProvider` mirror the existing `MediaButtonPort` shape. `RecordingScreen.initState` calls `_volumeButtonPort.activate()` after first frame; `dispose` deactivates.

`_onVolumeButtonEvent` in `recording_screen.dart` dispatches:

| Event | TTS playing? | hfState | Action |
|---|---|---|---|
| `up` | — | Idle / SessionError | `hfCtrl.startSession()` + toast "Listening" + haptic |
| `up` | — | Listening | no-op (already engaged) |
| `down` | yes | — | `ttsService.stop()` (interrupt agent reply; gate untouched) |
| `down` | no | Listening | `hfCtrl.suspendByUser()` + toast "Paused" + haptic |
| `down` | no | other | no-op |

### Orchestrator capture gate

`HandsFreeOrchestrator` gains:

```dart
bool _captureGateOpen = true;

@override
Future<void> setCaptureGate({required bool open}) async { … }
```

Default state on `start()` is **open** so the first-engage path is unchanged. `_enqueueChunk` early-returns when `!_captureGateOpen` — chunks read from the underlying `AudioRecorder` PCM stream are immediately discarded; the recorder + audio session stay alive.

On gate-**close** the following state is reset (so a half-segment captured before the close cannot leak into the next open window):

- `_remainder.clear()`
- `_speechBuffer = BytesBuilder(copy: false)`
- `_speechFrameCount = 0`
- `_captureFrameCount = 0`
- `_hangoverCount = 0`
- `_preRoll.clear()` — privacy invariant: closed-gate audio cannot appear in the next segment's pre-roll
- `_pendingFrames.clear()`, `_pendingLabels.clear()`, `_pendingSpeechStarted = false`
- `_cooldownTimer?.cancel()` AND `_inCooldown = false` (explicit, not just timer cancel)
- `_chunkQueue.clear()`

On gate-**open** the orchestrator emits a fresh `EngineListening` event so the controller can transition the public state.

### Controller lifecycle (gate-driven)

| Op | Behavior |
|---|---|
| First `startSession` (engine null) | Full setup: guards, `bg.startService`, `_engagement.engage()`, `_startEngine(...)`. |
| Subsequent `startSession` (engine alive) | Guards re-validated, `_pendingConversationResume = false`, `_suspendedByUser = false`, `_suspendedForTts = false`, `_engagement.engage()`, `await _engine!.setCaptureGate(open: true)`. **No** recorder restart. |
| `_disengageOneShot` (per-segment + 30 s timeout) | `await _engine?.setCaptureGate(open: false)` + `_engagement.disengage()` + `state = HandsFreeIdle(jobs)` + `_pendingConversationResume = true`. **No** engine teardown. |
| `suspendByUser` (Volume Down) | Same as `_disengageOneShot` but sets `_suspendedByUser = true` instead of `_pendingConversationResume`. |
| `suspendForTts` (TTS started) | Same gate-close pattern; sets `_suspendedForTts = true`. |
| `resumeAfterTts` (TTS ended) | If not user/manual-suspended AND state is Idle AND (`_suspendedForTts` OR `_pendingConversationResume`) → `_resumeEngagement()`. The flag check is the cold-TTS guard: a TTS that fires without a preceding capture must not silently spin up the mic. |
| `_resumeEngagement` | If engine alive: `engagement.engage()` + `setCaptureGate(open: true)`. If engine null: full `_startEngine`. |
| `stopSession` | Unchanged — full teardown including recorder. |
| `suspendForManualRecording` | **Unchanged from P037 v2** — still does full teardown. The manual recorder swaps the audio session and steals the I/O unit; staying alive is impossible there. Documented limitation: lock-screen-press after manual recording reverts to the old failure mode until one foreground engage warms the orchestrator again. |

### TTS suspend/resume listener (controller-level, not widget-level)

The original P037 v2 wiring put the `ttsPlayingProvider → suspendForTts/resumeAfterTts` bridge in `RecordingScreen.build()` via `ref.listen`. That listener fires reliably in foreground but is paused when iOS pauses Flutter rendering on a lock screen — observed empirically: foreground auto-resume worked, lock-screen did not.

The fix subscribes **directly to the underlying `ValueNotifier<bool>`** in the controller's constructor:

```dart
final tts = _ref.read(ttsServiceProvider);
final isSpeaking = tts.isSpeaking;
void ttsListener() {
  if (!mounted) return;
  if (isSpeaking.value) {
    unawaited(suspendForTts());
  } else {
    unawaited(resumeAfterTts());
  }
}
isSpeaking.addListener(ttsListener);
```

`ValueNotifier` callbacks fire on every `value` change regardless of widget rendering state. Cleanup happens in `dispose`.

### Audio session always `.playAndRecord + .spokenAudio`

`AppDelegate.application(launch)` sets the category and activates the session at process launch (`primeAudioSessionForLaunch`). The foreground service's `setPlayAndRecord` becomes a same-category fast-path no-op (`AudioSessionBridge.swift`). `stopService` skips the iOS category switch entirely — the session never leaves `.playAndRecord` for the lifetime of the process.

### TTS no longer swaps the audio session

`flutter_tts_service.dart`'s `_acquirePlaybackFocus` / `_releasePlaybackFocus` are no-ops. The setActive(false) → setCategory(.playback) → setActive(true) round-trip required to swap to `.playback` for hardware-button routing tore down the recorder I/O unit. Hardware buttons during TTS now route via `.playAndRecord + .spokenAudio` (same path the volume button gesture already uses).

## Affected Mutation Points

**Native (iOS):**
- `ios/Runner/VolumeButtonBridge.swift` — new
- `ios/Runner/AppDelegate.swift` — prime session at launch + register `VolumeButtonBridge`
- `ios/Runner/AudioSessionBridge.swift` — same-category fast-path skip in `setPlayAndRecord`
- `ios/Runner/MediaButtonBridge.swift` — lifecycle observers (interruption, didBecomeActive, routeChange) for `nowPlayingInfo` refresh
- `ios/Runner.xcodeproj/project.pbxproj` — `VolumeButtonBridge.swift` registered as a source file

**Dart (core):**
- `lib/core/volume_button/volume_button_port.dart` / `_service.dart` / `_provider.dart` — new
- `lib/core/audio/ambient_loop_player.dart` — disabled at the call site (`recording_screen.dart`); player itself unchanged
- `lib/core/background/flutter_foreground_task_service.dart` — `stopService` skips iOS category switch; `startService` setPlayAndRecord call left in place (now a no-op via AudioSessionBridge fast path)
- `lib/core/tts/flutter_tts_service.dart` — `_acquirePlaybackFocus` / `_releasePlaybackFocus` reduced to no-ops

**Dart (recording feature):**
- `lib/features/recording/domain/hands_free_engine.dart` — `Future<void> setCaptureGate({required bool open})` added to interface
- `lib/features/recording/data/hands_free_orchestrator.dart` — `_captureGateOpen` field; `_enqueueChunk` early-return; `setCaptureGate` impl with on-close reset list
- `lib/features/recording/presentation/hands_free_controller.dart` — `_disengageOneShot` / `suspendByUser` / `suspendForTts` / `resumeAfterTts` / `_resumeEngagement` / `startSession` updated for gate model; ValueNotifier-based TTS listener in constructor; `_ttsListenerCleanup` in `dispose`
- `lib/features/recording/presentation/recording_screen.dart` — volume button activation + `_onVolumeButtonEvent`; segment list rendering decoupled from `isOn` flag; widget-level TTS listener removed (moved to controller)

## Tests

`test/features/recording/data/hands_free_orchestrator_test.dart` — new `captureGate` group with 4 tests:

1. Chunks discarded when gate closed; recorder stays running.
2. Reopening the gate emits a fresh `EngineListening`.
3. Audio captured before gate-close does not leak into next open window via pre-roll (structural assertion: orchestrator does not crash on close→open cycle; the privacy invariant is enforced by the buffer-reset list).
4. `setCaptureGate` is idempotent (open→open and close→close are no-ops).

`test/features/recording/presentation/hands_free_controller_pause_test.dart` — three tests rewritten for the gate model:

- `resumeByUser from suspended transitions to HandsFreeListening (gate model)` — engine is NOT stopped on suspend (engine.stopped == false).
- `TTS-end after per-segment one-shot reopens the gate` — public state goes from Idle → Listening on resumeAfterTts; engine.stopped stays false throughout.
- `cold TTS-end (no prior engagement) is a no-op` — protects against random TTS spinning up mic from cold.
- `user re-engaging before TTS-end keeps the manual engage` — deferred TTS-end is a no-op while state is already Listening.

All other test fakes that implement `HandsFreeEngine` got a `setCaptureGate` stub.

`make verify` (analyze + 947 tests) passes.

## Acceptance Criteria

1. ✅ **lock → Volume Up → speak → segment captured** works after one foreground engage in the current app session.
2. ✅ Volume Down during TTS interrupts the reply and leaves the gate state for the post-TTS auto-resume to pick up.
3. ✅ Volume Down while engaged (no TTS) closes the gate; mic stays warm.
4. ✅ Volume Up after volume-down opens the gate without restarting the recorder.
5. ✅ Per-segment one-shot still fires (`_disengageOneShot` runs on `EngineSegmentReady`).
6. ✅ Auto-resume after TTS works in both foreground and lock screen (controller-level ValueNotifier listener).
7. ✅ Cold TTS-end (no preceding capture) does not auto-engage.
8. ✅ STT/persist running after `_disengageOneShot` keeps state at `HandsFreeIdle` (PR #278 invariant).
9. ✅ `make verify` passes (947/947).
10. ⚠️ Manual on-device verification: **all functional scenarios confirmed working** by user. Known cosmetic gap: no listening tone (AmbientLoopPlayer disabled).

## Risks

| Risk | Status |
|---|---|
| `MPRemoteCommand` blocked during hot mic — kills the AirPods click engagement path | Confirmed real. Bypassed via volume button gesture. |
| Volume button presses change the actual system volume | **Open**. Programmatic restore via `MPVolumeView` slider trick is not yet wired. UX: each engage / suspend nudges the volume one step. |
| `audioplayers` package fights the audio session, killing the recorder | Confirmed real. `AmbientLoopPlayer` disabled. |
| iOS continuously displays the orange recording indicator | Accepted trade-off (see ADR-AUDIO-011). |
| First engage of a session must be foreground | Accepted limitation. Documented. |
| Manual recording resets the always-on guarantee until one foreground engage warms the orchestrator | Accepted limitation. Documented in T4 carve-out. |
| iOS audio interruptions (phone call, Siri, alarm) tear down the I/O unit | Inherits P037's interruption observers (PRs #281/#282); recovery is best-effort. |

## Known Compromises and Follow-Up Direction

- **Listening tone** (AmbientLoopPlayer) — disabled. Need a tone player that respects the existing shared `AVAudioSession` rather than re-acquiring it. Options: small native AVAudioPlayer bridge, or `audio_session` package configuration that doesn't reset the session on play.
- **Volume restore** — observe the press, then programmatically set the volume back via `MPVolumeView` slider. Tricky: needs an in-view-hierarchy MPVolumeView, may flash the volume HUD briefly.
- **First engage must be unlocked** — closing this needs a "always-ready listening" setting that pre-warms the orchestrator at process launch (one knob away from the current architecture).
- **Manual-recording reacquisition** — `engine.reacquire()` API to re-attach the recorder to a fresh PCM stream without reinitializing VAD state. Defers cleanly out of v1.
- **PushToTalk framework** as an alternative engagement gesture would give us an iOS-native "PTT button on lock screen" + `didActivateAudioSession` callback. Requires `com.apple.developer.push-to-talk` entitlement application. Independent track.

## ADR Impact

`ADR-AUDIO-011 — Always-on capture with engagement gate` (drafted in PR #283 alongside the original P038) captures the always-on-capture decision and the privacy-indicator trade-off. It carries forward unchanged for this implementation; the engagement gesture (volume buttons vs MPRemoteCommand) is a tactical choice within the same architectural model.

The supersession note on `ADR-AUDIO-009` (lifecycle portion superseded by ADR-AUDIO-011) also carries forward unchanged.

## Addendum (2026-05-02): the 30 s auto-disengage timer is removed

P037 v2 added a 30 s auto-disengage timer in `EngagementController` to
auto-close a listening window if no speech arrived. The timer was a
safety net for the `MPRemoteCommand` engagement gesture, where the user
could click AirPods and forget — the app would silently close the
session after a quiet half-minute.

In the P038 always-on capture model that timer is **redundant and
surprising**:

- Engagement is now driven by **explicit hardware gestures** (Volume
  Up to engage, Volume Down to suspend / interrupt TTS). The user has
  unambiguous control over the capture gate at any moment.
- The recorder + audio session stay alive across disengage anyway —
  the cost the timer was minimising (mic warm uselessly) no longer
  matters because the mic is always warm by design.
- A timer-driven "session quietly closed" is harder to reason about
  in a model where the user expects "I pressed Volume Up so I'm
  listening, until I press Volume Down."

The following code is removed in this addendum:

- `kListeningEngagementTimeout` constant
- `EngagementController._timer` / `_timeout` / `tickTimeout()` / the
  `Timer(_timeout, tickTimeout)` start in `engage()`
- `EngagementController.markCaptureStarted()` (its sole purpose was
  to cancel the timer on VAD start-of-speech)
- `EngagementCapturing` state variant (only set by
  `markCaptureStarted`; replaced semantically by `HandsFreeListening`
  with `phase == capturing` at the controller layer)
- The `_engagement.markCaptureStarted()` call in
  `HandsFreeController._onEngineEvent` for `EngineCapturing`

The `EngagementController` API is now: `engage` / `disengage` /
`markError` / `state` / `stream` / `dispose`. State machine collapses
to `Idle / Listening / Error`.

Test impact: the PR #278 regression test ("STT completing after
auto-disengage keeps state HandsFreeIdle") was rewritten to use
`suspendByUser` instead of `tickTimeout` — the underlying invariant
(jobs progressing async after disengage do not flip state back to
Listening) is unchanged; only the trigger differs.

If a future feature needs an inactivity timeout (e.g. "auto-pause
after 5 min of no speech to release the orange dot"), it can be
re-added at the controller layer with explicit user-visible
semantics, rather than at the engagement layer where it produced
silent state changes.
