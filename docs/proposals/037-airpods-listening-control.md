# Proposal 037 — Hardware-button control of hands-free listening

## Status: Draft — v1 hypothesis empirically DISPROVED 2026-05-01; pivot to v2 or alternative

## Experiment result (2026-05-01)

T2 of v1 was executed on a release build (branch `037/t2-experiment`) with `nextTrackCommand` and `previousTrackCommand` targets registered in `MediaButtonBridge.swift`. User performed single-tap, double-tap, and triple-tap on AirPods Pro stem during hands-free listening. **No Dart-side `_onMediaButtonEvent` ever fired** (Dart `debugPrint` is visible in release; native `NSLog` is filtered, but the Dart-side handler would have logged regardless if iOS delivered the press).

Conclusion: **iOS gates the entire `MPRemoteCommandCenter` on a single rule when the session is `.playAndRecord` with an active mic engine.** Registering different commands does not change the routing decision — iOS uniformly refuses to deliver any of them. The "call protection" check is at the session level, not per-command.

Raw evidence captured in `idevicesyslog`:
- `AudioCategory: PlayAndRecord`
- `InterruptionStyle: 8` (iOS-internal value not in public docs; presumably the call-mode flag)
- `MRNowPlayingPlayerClientRequests` confirms Voice Agent DEV is the active media participant
- 0 × `_onMediaButtonEvent` in Flutter log stream after multi-tap attempts

**v1 (Candidate A) is therefore dead.** Proceed to v2 (Candidate B — tap-to-engage architectural pivot) or one of the documented alternatives.

## Origin

Production session 2026-05-01. P034 + the multi-PR investigation (#266–#270, ADR-AUDIO-010) made AirPods short click work for **TTS interrupt**. It does NOT work for **listening interrupt**: pressing the headset stem during hands-free listening yields the iOS rejection "boop", because `.playAndRecord` with an active mic engine is hardwired by iOS as "call mode" — `togglePlayPauseCommand` / `playCommand` / `pauseCommand` are blocked regardless of `nowPlayingInfo` content or `mode` setting.

User reaction:
> "OK. Zmergujmy to co mamy. […] Napisz proposal rozwiązania problemu z AirPods press w trybie listening i nie UI button jako fallback to za mało."

UI fallback is rejected as a solution. The feature must work via hardware.

## Prerequisites

- 034 (AirPods / media button control) — implemented and verified for TTS interrupt path
- 029 (session-control signals) — implemented; the gesture, once detected, can re-use the same dispatch path
- ADR-AUDIO-010 — documents the iOS constraint this proposal works around

## Are we solving the right problem?

**Root cause restated.** iOS reserves `togglePlayPause` / `play` / `pause` `MPRemoteCommand` for apps in pure-output sessions (`.playback`). When our session is `.playAndRecord` (because the mic engine is engaged for VAD), iOS treats the hardware button press as "call control" rather than "media control" and refuses to deliver it to user-space at all — the rejection sound is the OS's deliberate signal that the press was incompatible with the current audio state.

**Alternatives we already tried and dropped:**

- `.mixWithOthers` removal (#266) — necessary for the TTS path, irrelevant to the listening rejection.
- `setSharedInstance(true)` for flutter_tts (#267) — same.
- `nowPlayingInfo` with `playbackRate=1` and triple registration of `play` / `pause` / `togglePlayPause` (#268) — irrelevant; the rejection happens before any handler is consulted.
- `setActive(false)` → `setCategory(.playback)` → `setActive(true)` around TTS (#269/#270) — works for TTS. Cannot run during listening because the mic engine holds the I/O unit; switching mid-listening tears down recording.
- `mode = .spokenAudio` instead of `.default` for `.playAndRecord` (#270) — does not lift the rejection. The block is on the category, not the mode.
- Silent-loop AVAudioPlayer kept running during listening (#270) — does not lift the rejection. The rejection is keyed on mic engagement, not on the absence of audio output.

The constraint is iOS-architectural. To get a press during listening to reach our code, we need either (a) a different button gesture that travels a different MPRemoteCommand path, or (b) to not be in `.playAndRecord` when the press happens.

## Goals

- A single, learnable hardware gesture stops or pauses hands-free listening on the user's iPhone + AirPods setup.
- The gesture is reachable without the user looking at the screen.
- The gesture does NOT regress existing AirPods short-click TTS interrupt (which currently works).
- Implementation does not introduce >300 ms of latency on the speak ↔ listen turn-around.
- Accessibility / hardware variation: behaviour is documented but consistent across AirPods Pro / Max / 4 / wired Lightning headphones with inline media key.

## Non-goals

- Cross-device sync (iOS-only for v1).
- Configurable gesture in app settings (single, fixed gesture in v1).
- Replacing the on-screen UI button — UI button stays as the fully-reliable path.
- Recovering iOS short-click during listening — that specific gesture is permanently lost to iOS's call-protection rule.

## Solution candidates

We enumerate the four candidates that are technically realistic, score them, and recommend a sequence.

### Candidate A — `nextTrackCommand` / `previousTrackCommand` for double-press

**Idea.** AirPods Pro double-tap is mapped by iOS to `MPRemoteCommandCenter.shared().nextTrackCommand`. AirPods triple-tap maps to `previousTrackCommand`. These commands target a different iOS routing rule than `togglePlayPause`. **Hypothesis to verify**: they are not blocked by `.playAndRecord` because they don't intersect with call-control semantics.

If true: we register handlers for both. **Double-tap during listening = stop listening.** Triple-tap reserved for "new conversation" (replaces / supplements 029's deterministic farewell classifier).

**Cost.** ~30 LOC native + 30 LOC Dart wiring + 1 documentation update of P034. Same `MediaButtonBridge` pattern.

**Risk.** Hypothesis may be false. If iOS gates *all* `MPRemoteCommand`s on the same call-mode check, double-tap is also blocked. **Verifiable in 30 minutes** of native experimentation — register both targets, log NSLog when fired, ask user to double-tap during listening, observe.

**Side effect on TTS.** Double-tap during TTS would fire `nextTrackCommand` instead of skipping nothing — we should map it to "stop TTS and start a new utterance" or simply "stop TTS" depending on UX desire. Triple-tap during TTS is weirder.

### Candidate B — Architectural pivot to "tap-to-engage" listening

**Idea.** Stop holding `.playAndRecord` continuously. Default state is `.playback` (with silent-loop keepalive — already implemented). The hands-free listening session becomes a *bounded* interaction: user gesture starts it, one utterance is captured, session is closed, app returns to `.playback`.

In `.playback` default state, AirPods short-click works (proven by the TTS interrupt path). So short-click could:
- Start a listening turn (if idle)
- Stop a listening turn in progress (if active)
- Stop TTS (if speaking)

This is a major UX change — current model is "always listening once hands-free is on". The new model is "press to engage, one turn at a time".

**Cost.** Significant. Touches:
- `HandsFreeController` lifecycle (no continuous `Listening` state; instead `Idle` ↔ `EngagedOneShot`)
- VAD wiring (turn-bounded, not stream-bounded)
- Audio session transitions on every utterance (deactivate-flip-reactivate, ~100–300 ms each side)
- Recording UI (visual feedback for "listening this turn vs. idle")
- ADR-AUDIO-009 amendment

**Risk.** Latency on each turn. Worse hands-free UX (user must press to start each turn). Possibly unwelcome change to a working flow.

**Side effect.** AirPods short-click becomes a single, unified gesture: short-click = state transition, regardless of which state. Cleaner mental model.

### Candidate C — Bluetooth HID / CoreBluetooth direct observation

**Idea.** Bypass `MPRemoteCommandCenter` entirely. AirPods are a Bluetooth peripheral; their button presses generate HID events delivered over BT. We could open a CoreBluetooth scan, identify AirPods by service UUID, observe their HID notifications directly, and decode press events ourselves.

**Cost.** Heavy. Requires:
- `NSBluetoothAlwaysUsageDescription` Info.plist key (already present? to confirm)
- Potentially `Bluetooth-Sharing` entitlement for some flows
- Reverse-engineering AirPods' HID profile (Apple does not publish it; community work exists)
- Native CBCentralManager + delegate code in Swift
- Coexistence with the audio path — CB scan must not interfere with audio routing
- Testing across AirPods 1/2/3/Pro/Pro 2/Max/4 (different HID layouts)

**Risk.** Apple privately changes HID protocols across firmware updates; brittle. Possible App Store review friction for non-music apps using BT HID. AirPods 3+ encrypts more of the HID stream.

**Side effect.** Once working, the most powerful path — full custom gesture vocabulary independent of iOS routing rules.

### Candidate D — Long-press via `AVAudioSession.routeChangeNotification` heuristic

**Idea.** AirPods Pro long-press currently cycles "Noise Control" (per the user's iOS setting). The cycle changes the AirPods *output mode* (ANC ↔ Off ↔ Transparency). On every change, iOS may emit `AVAudioSessionRouteChangeNotification`. We observe the notification and treat any route change with reason `.override` or `.categoryChange` while hands-free is active as "user wants to interrupt".

**Cost.** Low — a notification observer in Swift bridge plus Dart wiring (~20 LOC).

**Risk.** False positives (any genuine BT reconfiguration would also fire). Behaviour is config-dependent: if the user sets long-press to "Siri" instead of "Listening mode", no route change occurs. Different AirPods models behave differently.

**Side effect.** User would have to keep "Listening mode" as the long-press setting (currently does, per their config). A long press that costs them noise-control cycling is a UX trade-off.

## Recommendation

**Two-step approach.** Both are independent and additive.

1. **Ship Candidate A (next/prev track) as v1.** It is the cheapest experiment, the smallest code change, the closest to user expectation ("press AirPods to control voice agent"), and it avoids the architectural blast radius of B. Validate the hypothesis empirically before committing more code. **If A works, the listening-interrupt feature is solved with ~60 LOC and no UX change.**

2. **If A's hypothesis fails** (i.e. iOS blocks `nextTrackCommand` too): pivot to **Candidate B (tap-to-engage)**. This is the principled architectural answer; the cost is real but the mental model becomes consistent.

C and D are kept as documented alternatives but not in v1 scope.

## v1 implementation (Candidate A)

### Tasks

| # | Task | Layer | LOC |
|---|---|---|---|
| T1 | Native: register targets on `nextTrackCommand` and `previousTrackCommand` in `MediaButtonBridge.swift`. Each forwards a distinct event identifier to Dart (`"nextTrack"` / `"previousTrack"`). | `ios/Runner/MediaButtonBridge.swift` | ~25 |
| T2 | Verify hypothesis empirically: build, install, ask user to double-tap during listening with `idevicesyslog` running. Either we see `[MediaButtonDbg] nextTrack TARGET FIRED` or we see another rejection "boop". This is the gate for the rest of the proposal. | manual | — |
| T3 | If T2 passes: extend `MediaButtonEvent` enum in `core/media_button/` with `nextTrack` and `previousTrack` variants. Update Dart event mapping in `MediaButtonService`. | `lib/core/media_button/` | ~15 |
| T4 | Wire double-tap → "stop hands-free" in `RecordingScreen._onMediaButtonEvent`. Mirror existing `togglePlayPause → stopTts` branching. Triple-tap → `resetSession()` (re-uses 029 dispatch). | `lib/features/recording/presentation/recording_screen.dart` | ~20 |
| T5 | Tests: extend `media_button_matcher` test with double/triple variants. Integration test: simulated `nextTrack` event on `RecordingScreen` calls `handsFreeController.stopSession()`. Verify nothing breaks the existing TTS interrupt path. | `test/` | ~40 |
| T6 | Update ADR-AUDIO-010 with the empirically validated answer to "do other `MPRemoteCommand`s also get blocked by `.playAndRecord`?" | `docs/decisions/` | ~10 |

### Acceptance criteria

- Double-tap of AirPods stem during hands-free listening stops the session within 200 ms (state transitions to `HandsFreeIdle`, mic released, `BackgroundService.stopService` called per ADR-AUDIO-009).
- Triple-tap during listening starts a new conversation (P049/P057 `resetSession` path) and resumes the listening loop.
- Short-click during TTS continues to interrupt TTS (regression guard — already works after #270).
- All three gestures have a haptic + toast confirmation per the existing P029 dispatcher pattern.
- No degradation of TTS playback (the silent-loop keepalive continues to run; native audio output is shared).
- Negative case: if the user has remapped double-tap in iOS Settings (e.g. AirPods 4 → "Volume Up"), our handler is silent — does NOT crash, no false-positive event.

### Verification plan

| Step | Action | Expected |
|---|---|---|
| 1 | Build & install dev. Open app, hands-free engaged. | App in `HandsFreeListening` state. |
| 2 | `idevicesyslog`. User double-taps AirPods. | One of: `[MediaButtonDbg] nextTrack TARGET FIRED` (success path), or `kAudioSessionIncompatibleCategory` rejection (failure → pivot to B). |
| 3 | Success path only: verify Dart-side `_onMediaButtonEvent event=nextTrack` arrives at handler. | Yes. |
| 4 | Verify handler calls `handsFreeController.stopSession()`. | Yes; toast "Stopped" shown; haptic fired. |
| 5 | Triple-tap during listening. Verify `previousTrack` event → `resetSession`. | New `conversation_id` adopted; toast "New conversation" shown. |
| 6 | Short-click during TTS. Verify TTS stops as before. | TTS stopped. |
| 7 | Repeat 1–6 with AirPods 4 / wired headphones. | Behaviour documented; degradation mode documented. |

## v2 — Candidate B (tap-to-engage, with audible state)

v1's hypothesis was disproved on 2026-05-01. v2 is the chosen path. The user-driven design adds an audible-state twist that turns the architectural change into a UX improvement, not just a workaround.

### State model

The hands-free flow becomes a two-state machine driven by a single "engage" gesture (AirPods short-click in the default state, or the on-screen mic button as a fallback).

```
                     ┌──────────────────────────────────┐
                     │ Idle                             │
        ←── disengage│  audio session: .playback         │
        ───────────► │  silence_loop.wav (volume 0)      │
                     │  AirPods media buttons routed     │
                     │  TTS replies play here normally   │
                     └──────────────────────────────────┘
                                  ↓ click engage
                     ┌──────────────────────────────────┐
                     │ Listening                        │
                     │  audio session: .playAndRecord    │
                     │  listening_loop.wav (low volume) │
                     │  mic engine + VAD active          │
                     │  30 s auto-disengage timer        │
                     │  AirPods buttons BLOCKED by iOS   │
                     └──────────────────────────────────┘
```

### State semantics

**Idle (default).**
- Audio session is `.playback` with no mic. Silent loop keeps the app the active media participant — `MPRemoteCommandCenter` routes hardware presses to us.
- AirPods short-click → `engage()` transition.
- TTS replies from the backend play here; nothing about playback changes (it already works).
- Battery/CPU minimal — only the silent loop.

**Listening.**
- Audio session is `.playAndRecord` (mode `.spokenAudio`, no `.mixWithOthers`).
- Silent loop swapped for `listening_loop.wav` — a subtle, low-volume ambient signal so the user *hears* that the mic is hot. Distinct from silence so engagement is unambiguous (no "is it on?" guessing).
- Mic engine starts, VAD active. The first speech detected becomes the captured utterance.
- 30 s auto-disengage timer starts on engage. Cancelled when VAD detects start-of-speech (capture takes as long as it takes); resets are unnecessary because once VAD fires, the session ends naturally on end-of-speech.
- If the timer expires (no speech detected) → disengage to Idle without any utterance.
- iOS still blocks AirPods buttons in this state — but it doesn't matter: the natural end is VAD or timer, not a user click. The user does NOT need a click to interrupt their own listening session.

### Engagement triggers (Idle → Listening)

| Trigger | Source | Available |
|---|---|---|
| AirPods short-click | hardware (MPRemoteCommandCenter `togglePlayPauseCommand` while app in `.playback`) | Always |
| On-screen mic button | UI tap | Always (fallback) |
| Voice wake-word | future | Out of scope for v2 |

### Disengage triggers (Listening → Idle)

| Trigger | Path | Notes |
|---|---|---|
| VAD end-of-speech | `HandsFreeEngine` reports utterance complete → `SyncWorker` enqueues → disengage immediately | The dominant case. Normal user flow. |
| 30 s timer expiry | No speech detected; disengage | Protects against "click but didn't speak". Configurable via `AppConfig` later if user wants. |
| Backend response → TTS plays | TTS reply itself triggers `.playback`-only context as today; no extra disengage needed since utterance flow already disengaged | Automatic. |
| Manual disengage (UI button or voice "stop") | UI / domain event | Optional safety. |
| App backgrounded | Standard iOS behaviour | Already handled by background service stop. |

### Audio assets

| Asset | Format | Purpose | Status |
|---|---|---|---|
| `assets/audio/silence_loop.wav` | 1 s mono PCM 44.1 kHz | Idle keepalive | exists (PR #270) |
| `assets/audio/listening_loop.wav` | seamless loop, soft ambient pad / low hum, ~30–60 dB below TTS, no transients | Listening state cue | **new** — generate before T1 of implementation |

The listening sample must:
- Be **distinguishable** from silence so user notices state change.
- Be **quiet enough** not to trigger our own VAD on the captured input mic. (AirPods echo cancellation handles most of it; sample volume should be low and tonal — broadband noise risks self-trigger.)
- Be **seamlessly loopable** (no click between iterations).
- Be **calm** — not a UI ding/beep that gets old fast. Soft pad / drone / breathing tone.

Initial generation: 2 s sine pad at 220 Hz + 330 Hz, slow LFO amplitude, fade-in/out 100 ms each side, normalize to −30 dBFS. Ship as starting point; iterate on UX feedback.

### Implementation tasks

| # | Task | Layer | LOC |
|---|---|---|---|
| T1 | Generate `listening_loop.wav` + register in `pubspec.yaml`. | assets | n/a |
| T2 | Audio session bridge: `setPlayback` already exists (PR #270). Add a state property tracking which sample is active. | `ios/Runner/AudioSessionBridge.swift` | ~10 |
| T3 | New domain port: `EngagementController` with states `Idle / Listening / Capturing / Error` and methods `engage()`, `disengage()`, `tickTimeout()`. | `lib/features/recording/domain/` | ~80 |
| T4 | Replace `HandsFreeController` continuous lifecycle with one-shot driven by `EngagementController`. Old states (`HandsFreeListening` / `WithBacklog` / `Capturing` / `SuspendedByUser`) collapse into `Idle` / `Listening`. | `lib/features/recording/presentation/hands_free_controller.dart` | ~150 (refactor) |
| T5 | Audio output orchestration: extend `KeepAliveSilentPlayer` to a two-track manager (`AmbientLoopPlayer`) that swaps `silence_loop` ↔ `listening_loop` based on EngagementController state. Volume control hook for tuning. | `lib/core/audio/` | ~60 |
| T6 | 30 s auto-disengage timer in `EngagementController`. Cancelled on VAD start-of-speech; expires → call `disengage()`. | `lib/features/recording/domain/` | ~20 |
| T7 | Wire AirPods short-click during Idle → `engage()`. Reuse the existing `_onMediaButtonEvent` handler — the togglePlayPause case in Idle becomes `engage()` instead of "stop TTS" (TTS-stop branch still applies if TTS is currently playing). | `lib/features/recording/presentation/recording_screen.dart` | ~15 |
| T8 | Update `HandsFreeSessionState` enum / sealed class to match new model. Migrate any consumers (UI conditionals, sync worker checks). | several | ~50 |
| T9 | UI updates: idle screen shows "Tap to talk" or similar; listening screen shows "Listening… 28s remaining" or similar visual cue (synced with the audible loop). | `lib/features/recording/presentation/recording_screen.dart` | ~50 |
| T10 | Tests: integration test of full Idle → engage → speech → capture → disengage cycle with mocked engine. Tests for 30 s timeout. Test for VAD cancelling timer. Audio session category assertions on each transition. | `test/` | ~150 |
| T11 | Update ADR-AUDIO-009 (conditional iOS audio session) — the category is now driven by `EngagementController` state, not by a continuous "background service" assertion. | `docs/decisions/` | ~30 |
| T12 | Delete dead code paths (`HandsFreeWithBacklog`, `HandsFreeCapturing` old, `SuspendedByUser`, suspendForTts complications). | various | -100 (delete) |

### Acceptance criteria

- Default state after app open: Idle. Silence loop running. AirPods media buttons route to app's `MPRemoteCommandCenter` targets (already verified in PR #270 path).
- AirPods short-click in Idle: engage to Listening within 200 ms (audible state change confirms).
- Listening loop audibly distinct from silence; user reports "I can hear that it's listening".
- VAD captures user speech within 30 s of engage → utterance sent to backend → app disengages to Idle automatically.
- No speech for 30 s → app disengages automatically. No user action required.
- Backend TTS reply plays in Idle. AirPods short-click during TTS still stops TTS (PR #266-270 path preserved).
- Battery: idle > listening only by mic engine cost (sample loop volume nearly zero); no measurable impact from audio session category churn.
- VAD does NOT self-trigger on the listening loop sample (regression test on chosen sample).
- iOS hardware-button handling during Listening is documented as "user does not click during listening" — UI is the disengage path if needed (rare, since timer + VAD cover normal flow).

### Risk register (v2-specific)

- **Listening sample triggers our own VAD.** Mitigation: tonal sample at low volume, AirPods echo cancellation. Test pre-ship by recording mic during loop playback and feeding into VAD model offline.
- **Click to engage causes hardware audio "blip" before sample starts.** AVAudioPlayer warm-up time. Mitigation: pre-load asset on app start; transitions feel instantaneous after first cycle.
- **30 s default unreasonable for some users.** Make it configurable via `AppConfig` in T6 implementation (default 30, range 5–120). Defer UI for it to follow-up.
- **TTS interrupts engagement.** If user clicks during a TTS reply, current model: stop TTS, *don't engage* (user's intent was to interrupt, not start a new turn). Expose as preference if desired.
- **Mid-utterance disengage timer race.** Already handled: timer is cancelled on VAD start-of-speech. Need an integration test that proves the cancel happens before timer expiry edge cases.

### v2 cost estimate

~5–8 PRs, ~600 LOC net (more deletions than additions in some areas). One independent code review (`/review-pr`) recommended on the EngagementController + audio session orchestration PR.

## Risk register

- **Hypothesis failure** (T2 negative): we are at the same place we are today. Not net-worse. Pivot triggers a known plan.
- **iOS firmware change** (Apple changes how AirPods buttons map to MP commands): all candidates A / C / D are affected differently. B is the most resilient.
- **AirPods model heterogeneity**: the user owns AirPods Pro per logs; AirPods 4 / Max may behave differently. The double-tap → next-track mapping is consistent across modern Apple wireless headphones, but the hardware-press semantics differ on wired and on third-party BT headphones.
- **Battery / heat** from the silent-loop keepalive (already shipped): negligible; revisit if ever reported.

## Tier

Tier 2. Audio platform behaviour change with cross-platform test surface, plus an empirical-validation gate (T2). One independent second-opinion review recommended before T3 implementation begins.

## Out-of-scope cousin: do other apps do this?

- **Otter.ai / Krisp / Notion AI Voice**: continuous-listen voice apps that do not (apparently) support hardware button to stop listening. They use UI button. Our v1 attempts a feature beyond their baseline.
- **Apple Voice Memos**: uses lock-screen widget controls and Siri, not a stem press. No native solution for our exact gesture.
- **Yet there's a thread of apps that do something like this**: Whisper Memos, MacWhisper iOS — they appear to use either tap-to-talk (Candidate B) or a notification widget. None we can find use double-tap-stop. v1 may be a small Apple-platform first.

## References

- ADR-AUDIO-010 (this repo): the constraint we are working around.
- ADR-AUDIO-007 / 009: the audio-session policy this proposal amends conditionally.
- Voice-agent PRs #266–#270, #271: the multi-PR investigation that yielded ADR-AUDIO-010.
- Apple Developer docs: `MPRemoteCommandCenter`, `AVAudioSession`. The "call protection" rule is undocumented; only inferable empirically.
