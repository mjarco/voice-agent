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

## v2 fallback (Candidate B — tap-to-engage)

If T2 of v1 demonstrates that `nextTrackCommand` is also blocked under `.playAndRecord` (i.e. iOS's call-mode check applies to the entire `MPRemoteCommandCenter`, not just the play/pause family), we abandon v1 and design a separate proposal for Candidate B. Sketch of the B-proposal scope:

- HandsFreeController lifecycle: replace `Listening / WithBacklog / Capturing / SuspendedByUser` with `Idle / Engaged(one-shot)`.
- Default audio session: `.playback` with silent-loop keepalive.
- Engagement: AirPods short-click (or on-screen mic button) → `setActive(false)` → `setCategory(.playAndRecord, mode: .spokenAudio, …)` → `setActive(true)` → start engine → capture one utterance → engine.stop() → reverse the audio-session flip → `.playback` resumes.
- VAD parameters tuned for one-shot capture (probably more aggressive end-of-utterance than today's continuous tuning).
- ADR-AUDIO-009 amendment.

Estimated cost for B: 5–8 PRs, plus a UX review of the new engagement model.

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
