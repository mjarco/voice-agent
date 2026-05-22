# Proposal 042 — Recover hands-free capture across audio route changes

## Status: Implemented (manual device verification pending). Tier 3 (microphone / audio-session ownership).

## Problem

While a hands-free session is engaged, removing or changing the audio
route — taking out an AirPod, un/plugging headphones — silently kills
microphone capture. The UI stays in `HandsFreeListening` (mic button
orange) but no audio is captured: no recording indicator, no segments,
no transcripts. The session only recovers if the user navigates away
from the Record tab and back.

This is the on-device face of the long-standing "mic-silent regression"
known issue.

## Root cause (device evidence)

Captured with `[HFDIAG]` / `[HFODiag]` instrumentation on an iPhone
(iOS 26.4.2), dev build:

```
state HandsFreeIdle -> HandsFreeListening      ← session engaged, mic live
[MediaButtonDbg] raw event from native: togglePlayPause   ← AirPod removed
_onMediaButtonEvent ... hfState=HandsFreeListening
branch=listening-noop
   ←←← then total silence: no EngineStopping, no EngineError,
       no _onStreamDone, no audioStream onError.
```

When the active route disappears (AirPod out), iOS changes the audio
route. The `record` package's PCM stream **stops delivering audio
without emitting `onError` or `onDone`** — it just goes quiet. The
`HandsFreeOrchestrator` has no route-change awareness, so:

- `_audioSub` stays subscribed but never fires `_enqueueChunk` again.
- No `EngineError` / `EngineStopping` is emitted.
- `HandsFreeController` stays in `HandsFreeListening` — orange UI, gate
  "open", but the microphone is dead.

Recovery via tab-switch works only by accident: leaving the Record tab
runs `stopSession()` (full engine teardown — `_engine.stop()`,
`_engine = null`), and returning runs `startSession()`, which does a
cold `_doStart()` → fresh `AudioRecorder.startStream()` on the *current*
route.

The pipeline has **no detection of, and no recovery from, audio route
changes**. That is the bug.

## Goals

1. A route change during an active session (device removed, added, or
   reconfigured) keeps capture working — capture continues on the new
   route automatically.
2. The app's `HandsFreeListening` state never diverges from reality: if
   the mic is not capturing, the state is either recovered or surfaced
   as `HandsFreeSessionError` — never a fake-listening orange state.
3. A dead microphone is recovered automatically regardless of cause,
   without requiring the user to navigate away and back.

## Non-goals

- Reworking the volume-button / media-button engagement gestures (P038).
- Changing the one-shot conversational-turn model (P037 v2).
- Lock-screen route-change behaviour beyond what the existing
  always-on-capture model (ADR-AUDIO-011) already supports.

## Solution design

### Layer 1 — Native route-change events (`AudioSessionBridge.swift`)

Add an `EventChannel` `com.voiceagent/audio_session/route_changes`.
Register an observer on `AVAudioSession.routeChangeNotification` and
emit the change reason as a string (`oldDeviceUnavailable`,
`newDeviceAvailable`, `routeConfigurationChange`, `categoryChange`,
`override`, `wakeFromSleep`, `noSuitableRouteForCategory`, `unknown`).

`AudioSessionBridge` is the right home — it already owns the
`AVAudioSession` category lifecycle.

### Layer 2 — Core port (`core/audio/audio_route_service.dart`)

- `abstract class AudioRouteService { Stream<AudioRouteChange> get changes; }`
- `AudioRouteChange` — small model carrying an `AudioRouteChangeReason`
  enum.
- `PlatformAudioRouteService` — platform-channel adapter, alongside the
  other `core/audio/` implementations.
- `audioRouteServiceProvider` in `core/audio/`.

### Layer 3 — Orchestrator restart (`HandsFreeOrchestrator`)

Inject `AudioRouteService`. While `_phase != idle`, on a route change
whose reason can affect the input route (`oldDeviceUnavailable`,
`newDeviceAvailable`, `routeConfigurationChange`):

`_restartCapture()`:
1. cancel `_audioSub`,
2. `await _audioRecorder.stop()`,
3. `_audioRecorder.startStream(...)` again, re-attach `_audioSub`,
4. reset VAD buffers (drop any partial segment),
5. keep `_phase`, `_captureGateOpen`, `_config`, `_vadService`.

Route changes arrive in bursts (a Bluetooth transition emits several);
debounce (~300 ms) so one transition triggers one restart. If
`startStream()` fails, emit `EngineError` so the controller surfaces
`HandsFreeSessionError` — a visible error beats a silent dead mic.

### Layer 4 — Silent-mic watchdog (defense-in-depth)

A periodic check (~2 s) in the orchestrator: when `_phase != idle` and
`_captureGateOpen`, if zero audio chunks have arrived since the last
check, the mic is dead → `_restartCapture()`. PCM chunks arrive
continuously whenever the mic is live (independent of speech), so
"no chunk for 2 s" is a reliable dead-mic signal. This catches
silent-mic causes beyond route changes (interruptions, OS audio glitches
— the broader "mic-silent regression").

## Risks

- **Audio gap during restart** (tens of ms). Acceptable; a route change
  already interrupts audio.
- **Restart loop on a flapping route** — mitigated by debounce.
- **iOS rejecting `startStream()` re-acquisition** (lock-screen context,
  ADR-AUDIO-011) — handled: a failed restart emits `EngineError`.
- **Watchdog false positive** — avoided because chunks stream
  continuously while the mic is live; "no chunk" unambiguously means a
  dead mic, not silence.

## Relationship to P041 — recommend revert

P041 (#320, #321) was built on the hypothesis that audio-session /
route-change-induced `AVAudioSession.outputVolume` shifts, misread as
volume-button presses, caused the session to disengage. The `[HFDIAG]`
diagnostics **disproved** this: every disengage traced to `_onTap`
(real screen taps), `stopSession()` (real nav-bar tab switches), or
`_disengageOneShot()` (a VAD segment — by design). The volume-button
suspend path (`branch=suspend`) never fired in any capture.

P041 therefore does not fix any observed bug. Its standalone concern —
route changes producing phantom *volume* events (which can cause a
spurious *engage*) is real but minor, and P041's implementation is
incomplete: device logs still show route-change-induced `volume up`
events reaching Dart. It also adds 0.25 s latency to genuine presses.

**Recommendation: revert P041 (#320, #321).** The phantom-volume-event
concern, if worth addressing, is far simpler and more reliable to fix on
top of this proposal's `AudioRouteService`: a Dart-side rule in
`VolumeButtonService` — "drop volume events within N ms of a route
change" — using one reliable signal instead of P041's fragile native
timing windows. Tracked as Future work below, not bundled here.

## Tasks

- [x] T1 — `AudioSessionBridge.swift`: route-change `EventChannel`.
- [x] T2 — `core/audio/`: `AudioRouteService` port + platform adapter +
      provider.
- [x] T3 — `HandsFreeOrchestrator`: subscribe to route changes,
      `_restartCapture()` with debounce; failed restart → `EngineError`.
- [x] T4 — `HandsFreeOrchestrator`: silent-mic watchdog.
- [x] T5 — Revert P041 (#320, #321) — merged in #323.
- [x] T6 — Manual test plan `docs/manual-tests/p042-route-change-recovery.md`.

## Acceptance criteria

1. With a session engaged, removing the active audio device (AirPod out,
   headphones unplugged) → voice capture continues on the built-in mic
   within ~1 s; speaking still produces segments/transcripts.
2. Re-adding a device → capture continues.
3. The app never sits in `HandsFreeListening` with a dead mic; the iOS
   recording indicator matches the app state.
4. If capture genuinely cannot be re-acquired, the controller reaches
   `HandsFreeSessionError` (visible, with Retry) — not fake-listening.
5. The watchdog recovers a dead mic within ~3 s for any cause.

## Test impact

- **Unit-testable**: `_restartCapture()` re-invokes `startStream()`
  (mock `AudioRecorder` + mock `AudioRouteService`); debounce collapses
  bursts; watchdog fires after the chunk-gap threshold (fake clock);
  failed restart emits `EngineError`.
- **Device-only**: actual route-change recovery on hardware → manual
  test plan `docs/manual-tests/p042-route-change-recovery.md` (AirPods
  remove/insert, wired headphone un/plug, Bluetooth speaker drop).

## Future work

- Re-address P041's phantom-volume-event concern on top of
  `AudioRouteService` (Dart-side suppression in `VolumeButtonService`).
