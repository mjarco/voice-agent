# Proposal 038 — Always-on capture with engagement gate

## Status: Draft — revised after proposal review + post-review concern (T0 empirical pre-flight added)

> **Critical pre-flight risk** (added 2026-05-02 after user review): the entire P038 architecture assumes that `.playAndRecord + mode: .spokenAudio` with an active recorder reading mic data delivers `MPRemoteCommand` events to the app. P037 v1 was empirically disproved because `.playAndRecord + .default` *does not* deliver these events (iOS treats the session as call-mode and rejects hardware-button presses with the "boop" sound). P037 v2 settled on `.spokenAudio` as a workaround, but the existing code (`recording_screen.dart` `_onMediaButtonEvent`) explicitly notes "iOS blocks media buttons during `.playAndRecord` with active mic, so this branch rarely fires in production". The current P037 v2 working flow side-steps this by switching to `.playback` between engagements — exactly the lifecycle P038 wants to remove. If `.spokenAudio` does not lift the block while the mic is hot, P038 breaks the entire AirPods-click feature. Task **T0** below is a pre-flight smoke test to answer this question before any of the gate work is built.

## Prerequisites

- 037 (AirPods listening control, v2 tap-to-engage) — implemented; this proposal extends its lifecycle model
- ADR-AUDIO-009 / ADR-AUDIO-010 — current iOS audio session ownership rules
- ADR-PLATFORM-006 — platform background behavior

## Origin

Production attempt on 2026-05-01 to engage hands-free listening from a locked screen via an AirPods short-click. The path **lock → click → capture** consistently fails with `PlatformException(record, com.apple.coreaudio.avfaudio error 2003329396)` when the recorder tries to start.

User reaction (paraphrased): *"Listening doesn't resume after phone lock. Could we have the app always listen, but not run VAD or the rest of the app pipeline (Groq, API, TTS playback) while a capture gate is closed?"*

Multiple per-attempt mitigations were tried and dismissed in the same session: keeping `.playAndRecord` active across disengage, priming `AVAudioSession` synchronously inside the `MPRemoteCommand` handler, skipping the foreground service's category switch. None of them got the recorder past the `2003329396` rejection on a locked screen. The error is a CoreAudio-level decision that the recorder cannot acquire the audio I/O unit in the post-lock context, regardless of the AVAudioSession state we set up around it.

## Problem Statement

Today the recorder is started on each `engage` and stopped on each `disengage`. From a locked screen, iOS does not let `AudioRecorder.startStream` acquire the I/O unit even when the audio session is correctly configured: the activation token that `MPRemoteCommand` hands the app is consumed before the asynchronous Dart pipeline reaches the recorder.

That makes the headline P037 v2 use case — *"lock the phone, click AirPods, talk"* — impossible. The user has to unlock first, which defeats the point of a hardware activator.

## Are We Solving the Right Problem?

**Root cause:** iOS only lets a recorder start from a locked context if the audio I/O unit is *already attached* and the session is *already active* before the lock event. Our current lifecycle starts the recorder *in response to* the click, which is too late — the I/O unit has been torn down by the time we ask for it.

**Alternatives dismissed:**

| Option | Why not |
|---|---|
| Keep `.playAndRecord` active across disengage and re-call `setActive(true)` in the click handler | Tried (commits in this session). The session category stays `.playAndRecord`, but the recorder still fails at `startStream` because the *I/O unit*, not just the *session*, is what iOS suspends across the lock. |
| Synchronously prime the session inside the Swift `MPRemoteCommand` handler | Tried. Activation succeeds, recorder still fails. Activation token is for *session*, not for *I/O unit acquisition*. |
| Switch to `record` package's own session management (skip our `setPlayAndRecord`) | Tried. Same rejection — the failure is in `record_ios`'s own activation path. |
| Pre-warm the recorder for a few seconds on app foreground and immediately stop it | Doesn't survive a lock event; defeats the goal. |
| Activate audio session permanently from `AppDelegate.application(launch)` | Tried. Session is active, recorder still cannot acquire I/O on locked screen. |

**Smallest change that could work:** keep the recorder *itself* running continuously after the user's first engagement. The I/O unit stays attached across lock events, and engaging/disengaging becomes a *gate* over the audio chunks rather than a *lifecycle* of the recorder.

This mirrors how iOS-native voice apps that record from a locked screen are built (Voice Memos, Otter, dictation): the audio engine is started once, then run forever.

## Goals

- `lock → click → capture` works the first time and every subsequent time within the session.
- The Dart-level engagement contract is unchanged: a captured segment only flows into VAD → STT → backend → TTS when the user has explicitly engaged.
- Privacy: no audio bytes touch VAD or the network when the gate is closed.
- The 30 s auto-disengage timer continues to fire as in P037 v2.
- The auto-resume-after-TTS conversational turn from P037 v2 (#280) continues to work.
- Existing Tier 2/3 invariants from P037 hold: the public state machine `Idle / Listening / Error` still describes UI state.

## Non-Goals

- Recording in the background while the user is in a *different app* (still gated by iOS background-audio rules; out of scope here).
- Per-segment power optimisation. The cost is the privacy/battery trade we are accepting; mitigations (e.g. dropping to `.playback` after long idle) are follow-up work.
- Pre-engagement recorder warm-up at process launch. We accept that the *first* engagement must happen with the device unlocked; only *subsequent* engagements need to survive a lock.

## User-Visible Changes

- **iOS recording indicator (orange dot / pill).** As long as the orchestrator is running (i.e. after the first user-initiated engagement of the app session), iOS shows the privacy indicator continuously. This is the user-visible cost of the always-on model. We accept it because the alternative is the feature not working.
- The very first engagement of a session must be performed with the screen unlocked. After that, the user can lock the phone and engage from the lock screen with an AirPods click.

## Solution Design

### State separation

Today's `HandsFreeOrchestrator` conflates two responsibilities:

1. **Audio capture lifecycle** — owning the `AudioRecorder` PCM stream
2. **Engagement pipeline** — VAD detection, segment extraction, WAV emission

We split them. The orchestrator owns capture and runs continuously after first start. A new boolean field — `_captureGateOpen` — controls whether incoming PCM chunks are forwarded to the VAD pipeline or dropped on the floor.

### Orchestrator gate semantics

| Gate | Behaviour |
|---|---|
| Open | Chunks are forwarded to VAD; segments emit `EngineSegmentReady`; current behaviour. |
| Closed | Chunks are read from the recorder stream and immediately discarded. VAD is not invoked. No segment events emit. The pre-roll buffer and any in-flight speech accumulator are reset on the close transition (so a stale half-segment from before the close is not flushed when the gate reopens). |

The recorder stream itself keeps draining whether the gate is open or closed — that is the entire point. The gate is a chunk-level filter, not a recorder-level pause.

### Engagement lifecycle (controller)

| Op | Today | After P038 |
|---|---|---|
| First `startSession` | `engine.start()` creates orchestrator, recorder begins. | Same — orchestrator created, recorder begins, gate is **opened**. |
| Subsequent `startSession` | New `engine.start()` (recorder restart). | Orchestrator already running. Just `await engine.setCaptureGate(open: true)`. |
| `_disengageOneShot` | `engine.stop()` (recorder torn down), `_engineSub` cancelled. | `await engine.setCaptureGate(open: false)`. Recorder *and* event subscription stay alive. |
| `stopSession` (explicit shutdown) | `engine.stop()`, full teardown. | Unchanged — full teardown including recorder. |
| Engagement-layer error (`_terminateWithError`) | Tear down. | Tear down (treat as full stop). |

#### `startSession` fast-path side-effect table

When `_engine != null` (orchestrator already running with gate closed), the call collapses to gate-open + selective re-validation. Each side effect is classified explicitly:

| Side effect | First call | Fast-path call | Notes |
|---|---|---|---|
| Microphone permission check | yes | yes | User can revoke mic in iOS Settings while backgrounded; on revoke we `_terminateWithError(requiresSettings: true)` before opening the gate. |
| Groq API key check | yes | yes | Mutable from in-app Settings; on miss `_terminateWithError(requiresAppSettings: true)`. |
| API URL check | yes | yes | Same — mutable. |
| `sessionActiveProvider = true` | yes | yes | Required so SyncWorker drains promptly. |
| `bg.startService()` (foreground service) | yes | no | The foreground service stays running across disengage; its iOS-side `setPlayAndRecord` is already a fast-path no-op (same-category check) so calling it twice is harmless but wasteful. |
| Notification update (`Recording session active`) | yes | yes | UI cue. |
| `_pendingConversationResume = false` | yes | yes | User taking explicit control cancels any deferred conversational resume. |
| `_jobCounter` reseed if `_jobs.isEmpty` | yes | yes | Cheap; no harm running it on each engage. |
| `_engagement.engage()` | yes | yes | Restarts the 30 s auto-disengage timer. |
| `_startEngine(...)` | yes | no | Replaced by `setCaptureGate(open: true)`. |
| `state = _listeningOrBacklog()` (transition) | yes (implicit, on first engine event) | yes (immediately, since engine is already emitting `EngineListening`) | Public state must reach `HandsFreeListening` synchronously on fast-path. |

### Audio session category

The session is set to `.playAndRecord` once (`AppDelegate.primeAudioSessionForLaunch`) and stays there for the lifetime of the process. Foreground service start/stop calls become no-ops on iOS for category management.

### TTS feedback prevention

When TTS plays we do **not** want the recorder picking up the speaker output. Today this is handled by `suspendForTts` tearing down the recorder. After P038, `suspendForTts` instead **closes the gate** for the duration of TTS playback; the recorder keeps draining but the chunks are dropped. `resumeAfterTts` reopens the gate (subject to the existing `_pendingConversationResume` / `_suspendedByUser` / `_suspendedForManualRecording` checks).

### Manual-recording handover (scoped out of v1)

The manual recording path (`suspendForManualRecording` → `record_ios` plugin starts its own recorder via its own AVAudioSession swap) **destroys the always-on guarantee**: the manual recorder steals the audio I/O unit and our orchestrator's PCM stream emits `onError` or `onDone`. By the time `resumeAfterManualRecording` runs, the orchestrator has fired `_terminateWithError` via the existing `onError` path; we'd then need to recreate it via `engine.start()`. If the user locks the phone in that window, we re-hit `2003329396` — the exact failure this proposal exists to fix.

For v1 we **scope the manual-recording flow out of the always-on guarantee**:

- `suspendForManualRecording` continues to call `_engine.stop()` (full teardown), as today.
- `resumeAfterManualRecording` continues to call `_resumeEngagement()` which goes through `_startEngine()` again, starting the orchestrator from scratch.
- Documented limitation: **immediately after a manual recording, the lock-screen-click path will not work until the user has performed at least one foreground engage to re-warm the orchestrator.**

This trades a known UX hole (manual recording resets the lock-screen capability for one engagement) for v1 simplicity. Closing the gap requires a `Future<void> engine.reacquire()` API that re-attaches the recorder to a fresh PCM stream without reinitializing VAD state — substantial enough to defer.

The TTS-suspend / user-suspend paths do **not** swap the audio session, so they keep the always-on guarantee and use the gate.

### Public engine interface

Add to `HandsFreeEngine`:

```dart
/// Opens or closes the chunk-processing gate. The underlying audio
/// stream keeps draining either way; only chunks observed through
/// the gate flow into VAD/segment emission.
///
/// On close: returns once the gate-close reset (buffers, cooldown,
/// in-flight WAV write) has been observed. The implementation does
/// NOT await the in-flight WAV write to disk — the write completes
/// asynchronously and any partial WAV is discarded by the existing
/// `_afterWavWrite` idle guard.
///
/// On open: synchronous; takes effect on the next chunk.
Future<void> setCaptureGate({required bool open});
```

Default state on `start()` is **open** so the first engagement does not require an extra method call.

### State machine effects

The public `HandsFreeSessionState` is unchanged. `Listening` corresponds to `gate=open`; `Idle` corresponds to `gate=closed` (with the same `jobs` semantics from P037 v2). The "STT/persist completes after disengage stays Idle" invariant from PR #278 is preserved.

#### Engine-event handling while gate is closed

With the engine subscription kept alive across disengage, the controller continues to receive engine events even when the public state is `HandsFreeIdle`. The mapping:

| Engine event | While gate is closed | Notes |
|---|---|---|
| `EngineListening` | Ignored at the controller layer (engagement is `EngagementIdle` so `_listeningOrBacklog()` returns `HandsFreeIdle(jobs:…)` — no public state flip). | Existing logic in PR #278 already keys off `_engagement.state`. |
| `EngineCapturing` | Cannot occur — the gate filters chunks before VAD sees them. | Documented invariant; T5 test asserts. |
| `EngineStopping` | Cannot occur for the same reason. | Same. |
| `EngineSegmentReady` | Cannot occur for the same reason. | Same. |
| `EngineError` | **Triggers `_terminateWithError`**, flipping public state from Idle to `HandsFreeSessionError`. | **New invariant compared to today**: today an audio-stream error after disengage cannot affect public state because the engine is already torn down. After P038 it can. |

The `EngineError`-while-Idle case is intended (an audio I/O failure in the always-on capture is genuinely a session-level error that should surface to the user) but has to be tested.

## Affected Mutation Points

**Needs change:**

- `HandsFreeEngine` (interface) — add `setCaptureGate({required bool open})`.
- `HandsFreeOrchestrator` —
  - new `bool _captureGateOpen = true` field.
  - `_enqueueChunk`: if `!_captureGateOpen`, return without queueing.
  - on **gate-close** the following state is reset:
    - `_remainder.clear()`
    - `_speechBuffer = BytesBuilder(copy: false)`
    - `_speechFrameCount = 0`
    - `_captureFrameCount = 0`
    - `_hangoverCount = 0`
    - `_preRoll.clear()` — required so pre-roll cannot leak audio captured during a closed-gate window into the next segment. **Privacy invariant: when the gate reopens, the segment starts with zero pre-roll.** This trades a small (configurable, default 200 ms) front-of-segment quality hit for the privacy guarantee that no closed-gate audio touches VAD or STT. Acceptable because TTS-suspend → resume is the most common gate-close→open path and we explicitly do **not** want TTS tail in the next segment's pre-roll.
    - `_cooldownTimer?.cancel()` AND `_inCooldown = false` (explicit reset — cancelling the timer alone leaves `_inCooldown = true` if cancellation happens between hangover-end and the timer's natural expiry).
  - `setCaptureGate(open: false)` impl drives the above transitions and returns once the reset is complete.
  - `setCaptureGate(open: true)` is a synchronous flag flip; takes effect on the next chunk.
- `HandsFreeController` —
  - `startSession`: if `_engine != null`, call `_engine!.setCaptureGate(open: true)` instead of recreating; otherwise existing first-time path.
  - `_disengageOneShot`: `await _engine?.setCaptureGate(open: false)` plus `_engagement.disengage()`. **Do not** cancel `_engineSub` and **do not** call `_engine?.stop()`. Continue to set `state = HandsFreeIdle(jobs: ...)` and `_pendingConversationResume = true`.
  - `suspendForTts`, `resumeAfterTts`, `suspendForManualRecording`, `resumeAfterManualRecording`, `suspendByUser`, `resumeByUser`: replace recorder teardown / restart with gate close / open.
  - `stopSession`: unchanged — still does full teardown.
  - `dispose`: unchanged — full teardown.
- `flutter_foreground_task_service.dart` — iOS branch in `stopService` already skips category switch (kept). `startService` calls `setPlayAndRecord` which is now a fast-path no-op (kept).
- `AppDelegate.swift` — keep the launch-time `primeAudioSessionForLaunch`. This is what guarantees the session is active before any lock event after first engage.

**No change needed:**

- VAD service — still receives chunks only when gate is open.
- Engagement controller — engagement state machine is independent of gate.
- Job queue / STT slot / persistence — already async and decoupled from engine lifecycle.
- Public state types (`HandsFreeIdle` / `HandsFreeListening` / `HandsFreeSessionError`) — unchanged.
- `AmbientLoopPlayer` — still drives ambient cues from public state. Idle = silent (`audioplayers` does not touch the session); Listening = listening loop. The `audioplayers` lock-screen reactivation issue from session #1 is sidestepped because the recorder owns the session continuously.
- Tests for the public state machine — should be a small adjustment, see Test Impact.

## Tasks

Tasks ship in order; each row is one mergeable PR. Test updates ride along with the controller change that breaks them (see "Test ride-along" column) instead of being deferred to a single late T5 — that was the under-estimate the proposal review caught.

**T0 is a gate.** If T0 fails, P038 is dead and a different architecture is needed (see *Fallback if T0 fails* below).

| # | Task | Layer | Test ride-along | Depends on | Notes |
|---|---|---|---|---|---|
| T0 | **Empirical pre-flight: does iOS deliver `MPRemoteCommand` events while `.playAndRecord + .spokenAudio` is active and `AudioRecorder.startStream` is currently reading mic chunks?** Hard-code the orchestrator to keep the recorder running (don't wire the gate yet), keep `.playAndRecord` always, then on a physical device measure whether AirPods short-clicks reach `MediaButtonBridge` while the mic is hot — both foreground (app frontmost) and locked-screen. Capture native `idevicesyslog` evidence and check whether the existing "rarely fires" comment in `recording_screen.dart` reflects a real race or a true block. | manual + native diagnostics | — | — | **If T0 reports "clicks reach app reliably, both foreground and locked," proceed to T1. If not, P038 is killed; pivot to fallback (see below).** Time-box T0 to one device session — answer is binary. |
| T1 | Add `Future<void> setCaptureGate({required bool open})` to `HandsFreeEngine` interface; implement in `HandsFreeOrchestrator` with chunk-level discard and the full on-close reset list (incl. pre-roll clear and explicit `_inCooldown = false`). | domain + data | Orchestrator-only tests for the gate (~4 new): chunks discarded when closed, buffers reset on close, pre-roll empty on reopen, `_inCooldown = false` after cancel. | T0 | Default state on `start()` = open. |
| T2 | Update `HandsFreeController._disengageOneShot` to call `await _engine?.setCaptureGate(open: false)` instead of `engine.stop()` + `_engineSub.cancel()`. Keep `_engagement.disengage()`. Keep `state = HandsFreeIdle(jobs:…)`. Keep `_pendingConversationResume = true`. | presentation | Updates ~12 tests in `hands_free_controller_test.dart` that assert `engine.stopped == true` after disengage — they now assert gate-closed and engine-still-alive. New test: engine event `EngineError` while gate-closed flips Idle → SessionError (per State Machine Effects). | T0, T1 | The `mounted` guards from PR #278 stay. |
| T3 | Update `HandsFreeController.startSession` per the side-effect table: when `_engine != null` and not in error state, run the perm/key/url re-validation and gate-open path; otherwise full first-time setup. Add `state = _listeningOrBacklog()` synchronous flip on fast-path. | presentation | Updates ~6 tests for "second startSession after disengage": engine instance is the same, gate transitions from closed to open, public state reaches `HandsFreeListening` synchronously. New test: revoked mic permission while orchestrator running → fast-path startSession surfaces `requiresSettings` error. | T2 | The session-start guards must be runtime-recheckable (perm/key/url), not first-call-only. |
| T4 | Update `suspendForTts` / `resumeAfterTts` / `suspendByUser` / `resumeByUser` to drive the gate instead of `_closeEngagement` / `_resumeEngagement`. **`suspendForManualRecording` / `resumeAfterManualRecording` are explicitly out of scope for v1** — they keep the full-teardown path and accept the documented "first lock-screen click after manual recording reverts to old failure mode" limitation. | presentation | Updates ~10 tests in `hands_free_controller_pause_test.dart` for TTS / user suspend paths. Manual-recording suspend tests are unchanged. New test: `suspendForTts` does not tear down engine; `resumeAfterTts` reopens gate without restarting engine. | T2 | Preserve the existing flag interactions (`_suspendedByUser`, `_pendingConversationResume`). |
| T5 | Manual on-device verification matrix (foreground / background / locked / lock-then-tts / lock-then-manual-record-then-lock-click). | manual | — | T1–T4 | See Acceptance Criteria. Lock-then-manual-record-then-lock-click documents the v1 limitation. |

**Note:** `ADR-AUDIO-011 — Always-on capture with engagement gate` and the supersession edit on `ADR-AUDIO-009` ride with this proposal's merge to `main` per CLAUDE.md "Proposal and ADR Commit", **before** any of the implementation tasks T0–T5 begin. T0 itself is implementation work and runs after the proposal lands; only if T0 succeeds do T1–T5 follow.

### Fallback if T0 fails

If iOS does **not** deliver `MPRemoteCommand` events to the app while `.playAndRecord + .spokenAudio` is active with a hot recorder, P038 is dead and the lock-screen-click headline goal is impossible under the current iOS audio architecture. Two fallback directions, in priority order:

1. **Hybrid: keep recorder warm but bounce the session category for click delivery.** While the gate is closed, keep `_audioRecorder` *attached* but flip `AVAudioSession` to `.playback` so iOS routes clicks. On click → flip back to `.playAndRecord` and reopen the gate. Risky because `record_ios` may detach from the I/O unit on category change; the whole reason P038 exists is that re-attaching from a locked context fails. Needs its own pre-flight.
2. **Accept the limitation** and document P037 v2 as the final iOS behaviour: lock-screen click does not engage. The user must unlock first. UX hole, but consistent with iOS apps that respect call-mode rules. Ship a Settings note and stop iterating.

T0 must record evidence sufficient to choose between these. Until T0 lands, the rest of P038 is speculative.

Test impact estimate: **~22 controller-side test updates + ~5 new orchestrator tests + ~3 new controller tests**, distributed across T1/T2/T3/T4 PRs as ride-alongs. The two test files together hold 64 tests across 1731 LOC; the proposal is reshaping ~⅓ of them.

## Test Impact / Verification

Re-estimated after proposal review using `grep` against the actual test files (1731 LOC, 64 tests, 79 engine-lifecycle assertions):

- **Existing tests affected — ~22 controller-side updates** distributed across T2/T3/T4 PRs:
  - `hands_free_controller_test.dart`: ~12 tests asserting `engine.stopped == true` or `_engineSub == null` after disengage.
  - `hands_free_controller_pause_test.dart`: ~10 tests asserting recorder teardown on TTS/user-suspend.
  - Manual-recording tests unchanged (T4 keeps the legacy path for that flow).
- **New tests — ~5 orchestrator + ~3 controller**:
  - Orchestrator: gate-closed discards chunks; gate-close resets buffers; pre-roll empty on reopen; cooldown reset on gate-close; chunk-level gate is observably synchronous on open.
  - Controller: engine instance survives across disengage; second `startSession` reuses the same engine; `EngineError` while gate-closed flips Idle → SessionError; revoked mic permission during fast-path startSession surfaces `requiresSettings`.
- **Coverage invariants preserved:** PR #278's "STT completes after auto-disengage stays Idle" regression test must continue to pass.
- **Commands:** `make verify` (analyze + test) per task PR. On-device manual tests against the matrix in *Acceptance Criteria* run as part of T6 only.

## Acceptance Criteria

1. **lock → click → capture** works on iPhone after the user has engaged at least once during the current app session. Verified: phone unlocked, click AirPods, speak, segment captured (visible in segment list), TTS reply plays, then lock the phone, click AirPods on the lock screen, speak, segment captured.
2. **No segment, STT call, or API call is emitted while the gate is closed.** Verified by leaving the app idle for 60 s and confirming no entries arrive in the backend.
3. **30 s auto-disengage** continues to fire after a captured utterance.
4. **TTS playback** does not feed back into the mic — the user does not hear their own captured TTS as a follow-up segment. Verified by triggering TTS reply and confirming no immediate segment is emitted while it plays.
5. **stopSession** still tears the engine down completely (e.g. when the user navigates away from the Record tab).
6. The iOS recording indicator (orange dot) is visible whenever the orchestrator is running. This is documented as expected behaviour in `ADR-AUDIO-009` (or follow-up ADR).
7. **940/940 existing tests** that survived the P037 v2 work either pass or have a documented update in the same PR. No drop in coverage of the public state machine.

## Risks

| Risk | Mitigation |
|---|---|
| **iOS does not deliver `MPRemoteCommand` while the recorder is hot** (the existing `recording_screen.dart` comment says "rarely fires"). If true, the entire P038 architecture fails: lock-screen click never reaches the app. **Highest risk; must be resolved before any other work.** | Task T0 (pre-flight smoke test on a physical device). T0 result determines whether T1–T5 proceed or P038 pivots to a fallback. See *Fallback if T0 fails* below the task table. |
| iOS shows the orange recording indicator continuously, which users may find creepy. | Document explicitly in onboarding / Settings. Optional follow-up: drop to `.playback` after N minutes of idle to release the indicator, and re-prime on next user interaction. |
| Battery drain from continuous mic streaming. | The `AudioRecorder` PCM stream is roughly 32 KB/s of mic samples; the cost is modest but real. Mitigations are follow-up work. |
| Gate-closed window leaks a partial segment if the buffer is not reset properly. | T1 explicitly resets speech buffer and counts on close; orchestrator test asserts this. |
| First engagement still has to happen with the device unlocked; users may expect lock-screen to work from a fresh launch. | Documented as a non-goal here. Acceptable because the alternative is the entire feature being broken. |
| `record` package upgrades may change internal session ownership and reintroduce the lock-screen failure. | Lock the package version; add a smoke check to the on-device verification matrix on each upgrade. |
| Gate semantics interact poorly with the manual recording path (which swaps the audio session). | **v1 carve-out:** manual recording keeps the legacy full-teardown lifecycle. The lock-screen-click after manual recording is documented as a known limitation. Permanent fix deferred to a future proposal that introduces `engine.reacquire()`. |
| Permission / API key / URL changes while the orchestrator runs with a closed gate go undetected until the user engages again. | T3 fast-path explicitly re-validates perm/key/url on each `startSession` call, even when the engine is already running. On revoke, surface the standard `requiresSettings` / `requiresAppSettings` error. |
| `EngineError` arriving while gate is closed flips Idle → SessionError. | Documented in §"State Machine Effects" as intended; new test case in T2. |

## Alternatives Considered

Documented in *Are We Solving the Right Problem?*. The decisive one is "keep `.playAndRecord` active and reactivate inside the `MPRemoteCommand` handler" — that path was empirically tried and failed because the activation token does not survive into the Dart-side recorder start.

## Known Compromises and Follow-Up Direction

- **First engagement must be unlocked.** A future variant could pre-warm the orchestrator at process launch (e.g. via a setting "always-ready listening") at the cost of an immediate orange indicator on app open. The architecture in P038 already supports this — it is one knob away (`engine.start(); await engine.setCaptureGate(open: false)` at process launch behind a setting). Naming the knob lets the next proposal extend rather than redesign.
- **Manual-recording resets always-on.** T4 explicitly scopes manual recording out of v1: that path keeps the legacy full-teardown, so the first lock-screen click *after* a manual recording reverts to the old failure mode until the user has performed one foreground engage. Closing this gap requires a `Future<void> engine.reacquire()` API that re-attaches the recorder to a fresh PCM stream without reinitializing VAD state.
- **Battery / privacy mitigation.** Drop the recorder to paused after N minutes of idle to release the orange indicator, re-prime on next interaction. Out of scope here.
- **iOS audio interruptions** (phone call, Siri, alarm) will tear down the I/O unit. P037's interruption observers (PR #281/#282) restore the session; recording recovery after interruption is not explicitly covered by this proposal and inherits the existing behaviour.
- **"Drainable but gateable stream" pattern.** This is the second place in the codebase that needs intermittent-processing semantics (TTS suspend, user pause, disengage all map to a closed gate). Future features (wake-word detector, noise-floor calibrator) can adopt the same shape rather than reinventing it.

## ADR Impact

**Decision:** Author a new ADR `ADR-AUDIO-011 — Always-on capture with engagement gate` (T5). Mark the relevant section of `ADR-AUDIO-009` as superseded with a forward link to ADR-AUDIO-011. New ADR (rather than amending in place) chosen because:

1. The supersession trail is explicit — readers of `ADR-AUDIO-009` see "this part was replaced by ADR-AUDIO-011" rather than discovering the change via `git log`.
2. `git blame` on `ADR-AUDIO-011` points cleanly to this proposal's commit, with no commingled history.
3. The decision is genuinely new (always-on capture, gate-as-filter, privacy-indicator trade-off) — it is not a clarification of the previous decision but a different one.

A short ADR-level summary of the trade-off (will be expanded in T5):

> The app keeps `AVAudioSession` in `.playAndRecord` and the `AudioRecorder` PCM stream draining for the entire app session after first engagement. iOS does not allow the recorder to acquire the audio I/O unit from a locked-screen `MPRemoteCommand` callback if the unit was torn down before the lock; the only way to support the headline lock-screen-click flow is to keep it attached. The cost is a continuous recording indicator and the battery overhead of an always-warm mic. We accept this cost; it is the iOS-native pattern for voice-first apps (Voice Memos, Siri, Otter). The manual-recording flow is explicitly carved out of the always-on guarantee and reverts to the old full-teardown lifecycle for that path.

Per CLAUDE.md "Proposal and ADR Commit": this proposal merges to `main` together with `ADR-AUDIO-011` and the ADR-AUDIO-009 supersession edit, before any implementation work begins.

## Open Questions

These are flagged for the implementation review, not blockers for proposal approval:

1. **iOS interruption handling.** Does `record_ios` keep `AudioRecorder.startStream`'s I/O unit attached across an `AVAudioSessionInterruptionNotification` (phone call, Siri, alarm)? The P037 interruption observers (PRs #281/#282) restore the session, but the recorder may be in an unrecoverable state — needs on-device verification.
2. **Orange indicator visibility from background.** Does iOS show the recording indicator continuously while the orchestrator runs, including when the app is backgrounded? Confirm in T6.
3. **Post-stopSession lock-screen behaviour.** After an explicit `stopSession` (e.g. user navigates away from Record tab), the orchestrator is fully torn down. The next `startSession` restarts it. If that next start happens from a locked screen, we re-hit `2003329396`. Should `stopSession` be reserved for app-shutdown cases only? Re-evaluate in T6.
