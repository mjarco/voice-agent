# ADR-AUDIO-007: iOS ambient audio session category for playback

Status: Accepted
Proposed in: P016

## Context

iOS manages audio through AVAudioSession categories that control how the app interacts with other audio sources and the hardware silent switch. Key options:

- **playback** — takes exclusive audio session, ignores silent switch, interrupts other apps.
- **ambient** — mixes with other audio, respects silent switch, does not interrupt.
- **playAndRecord** — used during active recording, supports simultaneous input/output.

Audio feedback (jingles, loops) and TTS play while the app may also be capturing audio for VAD.

## Decision

Use `ambient` category for audio feedback playback. This respects the hardware silent switch and mixes with other audio sources including the active microphone session.

Guard pattern for playback: always stop the current loop before conditionally playing a new sound. `playSuccess()`/`playError()` stop the loop first regardless of the enabled state, then conditionally play the jingle.

## Rationale

`playback` category would override the user's silent switch preference and potentially interrupt the microphone session. `ambient` is the least intrusive option — audio feedback is supplementary, not primary content. The guard pattern prevents overlapping audio from stale callbacks.

## Consequences

- Audio feedback is silent when the hardware silent switch is on — by design.
- No AVAudioSession conflicts with simultaneous recording.
- Generation counter pattern prevents stale playback callbacks from triggering audio after a new operation starts.
- TTS interruption must be coordinated at three points: VAD speech start, tap-to-record, and press-and-hold — to avoid AVAudioSession conflicts on iOS.
