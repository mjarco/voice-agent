# ADR-AUDIO-017: On Android a button held on glass-native listens until it is released

Status: Accepted
Decided in: assignment `2026-11-20-va-hold-to-talk` of the workspace (exploration `2026-11/20-flic-duo`)
Adds to: [ADR-AUDIO-016](./ADR-AUDIO-016-glasses-drive-the-microphone-mode.md) (the protocol it extends) and [ADR-AUDIO-013](./ADR-AUDIO-013-android-three-microphone-modes.md). iOS is unchanged.
Contract: glass-native's `docs/va-control-protocol.md`, v2.

## Context

glass-native holds a Flic Duo button. Held down, the owner talks; released, the utterance goes.
In the spikes the button drove the existing `listening` and `standby`, and voice-agent's silence
detection (VAD, 1.5 s of silence) ended an utterance while the button was still held. The owner:
"trzeba będzie to zmienić w docelowym rozwiązaniu", and later "wyłączamy wtedy VAD, polegamy tylko
na hold-release".

## Decision

1. **Two commands** on the ADR-AUDIO-016 way in: `hold` (the button went down) and `release` (it
   came up), answered like the others.
2. **`hold`** marks the controller held and the engine held (`HandsFreeEngine.hold`). From Standby
   it resumes, from Off it starts a session (refused by Android in the background, as `listening`
   is). A reply being spoken stops. A held engine opens a segment with the next frame, speech or
   not, the pre-roll included; silence (the hangover) and the 30 s cap do not end it.
3. **`release`** ends the hold (`releaseHold(close: true)`): after a 250 ms tail for the last
   syllable the segment closes and goes the usual way (WAV, transcription, personal-agent), or is
   dropped below the minimum speech, as VAD drops it. A hold that began in Standby or Off goes back
   to Standby; one that began in Listening stays there.
4. **`listening` during a hold** turns it into ordinary listening (`releaseHold(close: false)`):
   the segment goes on under the silence rules and listening stays on. glass-native uses it for a
   double click, which starts as a hold.
5. **A release that never comes** (glass-native killed, the button out of range) is replaced by a
   timeout of 5 minutes. A pause or a stop during a hold ends it, dropping the utterance in flight
   as a pause did before.
6. **No new mode.** A hold is Listening as far as the mode, the notification and glass-native's
   page are concerned; the mode report is unchanged.

## Consequences

- An utterance lasts as long as the button is held, pauses included, up to 5 minutes.
- Any app holding the MIC permission can now also hold the microphone open for 5 minutes, as it
  could already keep Listening on; nothing new is readable.
- glass-native v1 never sends the new commands; an older voice-agent answers them `refused`, so
  glass-native can tell.
- Device plan: [held-listening.md](../manual-tests/held-listening.md).
