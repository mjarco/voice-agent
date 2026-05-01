# ADR-AUDIO-010: iOS hardware media-button routing constraints in a hands-free voice assistant

Status: Accepted
Proposed in: P034 follow-up (TTS interrupt + headset button — investigation 2026-05-01)
Amends: ADR-AUDIO-007, ADR-AUDIO-009

## Context

P034 (AirPods / media button pause & resume) shipped with the assumption that registering targets on `MPRemoteCommandCenter.shared().togglePlayPauseCommand` (and `playCommand` / `pauseCommand`) plus setting `MPNowPlayingInfoCenter.default().nowPlayingInfo` is enough for AirPods short-click to reach the app. Production usage on 2026-05-01 showed it was not — short clicks during TTS or during hands-free listening produced the iOS hardware "rejection boop", and our targets never fired.

Investigation traced this to iOS audio-session semantics that ADR-AUDIO-007 / ADR-AUDIO-009 did not document fully. This ADR records what we learned, what we shipped, and the architectural limit we hit.

## Decision

We adopt the following invariants for iOS hardware media-button routing:

1. **Audio-session category drives whether iOS routes hardware media buttons to the app at all.**
   - `.playback` (no mic): media buttons route to the app's `MPRemoteCommandCenter` targets when the app holds the active media participant slot via `nowPlayingInfo`.
   - `.playAndRecord` (mic + output): iOS treats the session as "call/voice" and **rejects** hardware media-button presses with the audible `kAudioSessionIncompatibleCategory` rejection sound, regardless of what `nowPlayingInfo` claims. This is hard-wired by iOS for call protection — no mode (`.default`, `.spokenAudio`, `.measurement`, `.voiceChat`) lifts the rejection while a mic engine is engaged.
   - `.ambient` / `.record`: not relevant to this app.

2. **Switching from `.playAndRecord` to `.playback` requires deactivating the session first.**
   - Calling `session.setCategory(.playback, …)` while the mic engine is engaged fails with `OSStatus 561017449` (`kAudioSessionIncompatibleCategory`).
   - Correct sequence: `setActive(false, options: [.notifyOthersOnDeactivation])` → `setCategory(.playback, …)` → `setActive(true)`. This releases the I/O unit and lets the category change land. Symmetric on the way back.

3. **TTS playback uses `.playback`. Hands-free listening keeps `.playAndRecord`.**
   - On TTS start (`FlutterTtsService.speak`), the bridge acquires `.playback` via the deactivate-flip-reactivate sequence above. Hardware short-click during TTS routes to our `togglePlayPauseCommand` target → calls `ttsService.stop()`. **This is the only path along which hardware media buttons currently work.**
   - On TTS end (or stop / cancel / error), the bridge restores the previous category, returning to `.playAndRecord` for hands-free listening.

4. **`.playAndRecord` mode is `.spokenAudio` (not `.default`).** Even though this does not lift the iOS rejection during listening, it is the most accurate descriptor of the content (spoken-word audio assistant, not a phone call) and is the preferred mode under Apple's audio-session guidance.

5. **A silent-loop AVAudioPlayer is kept running while hands-free is in any active listening state.** This was tried as a fix to make iOS treat the app as actively producing audio output during listening, on the hope that the rejection rule was tied to "no audio output now". The hypothesis turned out to be wrong — iOS rejects based on `.playAndRecord` mic engagement, not on audio-output activity. The keepalive is retained because:
   - It does not regress anything.
   - It keeps the app's media-participant claim continuously valid (Now Playing widget stays bound to Voice Agent rather than competing apps).
   - It makes future experiments (e.g. AVRouteDetector route-change observation) cheaper to wire.

6. **Hardware control of hands-free listening is out of scope on iOS.** We accept that:
   - Short AirPods click during listening cannot stop or pause the recording on iOS.
   - The user must use the on-screen UI button for that path.
   - Long-press of AirPods is configurable in iOS Settings (Listening mode / Siri / Off) and is not a reliable cross-device gesture, so we do not target it.

## Rationale

`.playAndRecord` is the only audio-session category that lets a single iOS app simultaneously capture mic input and produce output. Hands-free voice assistants need both, continuously, by definition. iOS reserves hardware media-button routing for apps in pure-output sessions (`.playback`) so that pressing the button on a headset during a phone call doesn't accidentally pause/resume music. Voice assistants like ours fall on the "call" side of that line as far as iOS is concerned. The rejection is intentional, not a bug; we cannot opt out by choosing a different mode or setting different `nowPlayingInfo`.

The trade-offs we considered and rejected:

- **Heavyweight teardown + restart of the mic engine on every TTS / press detection.** Would let us flip to `.playback` and back across the entire user-interaction loop. Costs ~200–500 ms latency at each transition and complicates the recording lifecycle (P028 / ADR-AUDIO-009 invariants). The TTS-only fix achieves 90% of the user value at zero latency cost.
- **Custom HID listener over CoreBluetooth bypassing `MPRemoteCommandCenter`.** Possible in theory, requires Bluetooth-Sharing entitlement, parses raw HID events from AirPods. Disproportionate complexity for a single edge case and would not coexist cleanly with iOS's own media-button handling.
- **`SiriKit` integration.** Solves nothing because we are not asking Siri to act — we want raw button events.
- **Use `.duckOthers` / `.mixWithOthers` to coexist with Apple Music.** Re-introduces the original PR #266 problem (app no longer claims media focus, button routes elsewhere). Strictly worse.

## Consequences

- **TTS interrupt via AirPods short click works.** This is the primary user-visible behaviour — when the agent is speaking and the user clicks the headset, speech stops. Confirmed in production on 2026-05-01.
- **Listening interrupt via AirPods does not work and will not work without one of the rejected trade-offs above.** UI button is the documented path. The rejection sound is intentional iOS behaviour; users may need to know not to mash the button during hands-free listening.
- **Audio session lifecycle is now richer.** It transitions through `.playAndRecord` ↔ `.playback` for every TTS utterance via deactivate-flip-reactivate. The bridge logs each transition (`[AudioSessionDbg]`) so future debugging of the same surface area is direct.
- **The silent-loop keepalive runs whenever hands-free is listening but TTS is not.** Battery overhead is negligible (zero-volume PCM loop), no audible artefact.
- **Future alternatives (if the listening-interrupt limitation becomes painful):**
  - Engine teardown approach with lifecycle-aware UX guards (latency budget needs design).
  - AVRouteDetector / route-change notifications as a heuristic for AirPods press detection during listening.
  - Migrating the hands-free model to a "hold-to-listen" gesture instead of continuous capture, removing the need for `.playAndRecord` between utterances.

## Concrete code surface

- `ios/Runner/AudioSessionBridge.swift` — `setPlayback` / `restoreAudioSession` methods with deactivate-flip-reactivate; `.spokenAudio` mode for `.playAndRecord`.
- `lib/core/tts/flutter_tts_service.dart` — `_acquirePlaybackFocus()` / `_releasePlaybackFocus()` called around every TTS speak.
- `lib/core/audio/keep_alive_silent_player.dart` — silent-loop player.
- `lib/features/recording/presentation/recording_screen.dart` — wires the keepalive to hands-free state transitions.
- `assets/audio/silence_loop.wav` — 1 s mono PCM silence at 44.1 kHz.

## Origin

Production observation 2026-05-01 (conversation `019de30f-…`). User report: TTS interrupt and listening interrupt via AirPods short click did not work. Eight-iteration investigation through PRs #266, #267, #268, #269, #270 culminating in this ADR.
