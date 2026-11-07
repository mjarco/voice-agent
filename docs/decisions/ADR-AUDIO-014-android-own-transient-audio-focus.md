# ADR-AUDIO-014: The app's own transient audio focus on Android

Status: Accepted
Decided in: PR #406 (epic 2026-11-mic-modes/01-mic-modes, task 3)
Adds to: [ADR-AUDIO-013](./ADR-AUDIO-013-android-three-microphone-modes.md), which left the audio focus to a later task. Supersedes nothing. iOS is unchanged.
Design note: the workspace docs, `research/2026-11-voice-agent-mic-states/reviewed/04-simplified-model.md` (the focus row and decision 2).

## Context

The `record` plugin (record_android 1.5.1) requests a permanent
`AUDIOFOCUS_GAIN` with `USAGE_MEDIA` on every recorder start, and pauses
the recorder on any loss of it. Under ADR-AUDIO-013 that had three effects:

- every start of Listening stopped a video for good, since a permanent
  loss tells the other app not to resume;
- a notification chime, or any app taking the focus, silently paused the
  recorder; after 3 s the watchdog restarted it, which took the focus back
  (a tug of war);
- a call left the app deaf with no sign, in Listening.

## Decision

On Android:

1. **The plugin takes no focus.** Both recorders (hands-free and
   push-to-talk) pass `audioInterruption: none`. iOS keeps `pause`, the
   plugin's handling of AVAudioSession interruptions.
2. **The app holds its own transient focus in Listening only.**
   `AudioFocusBridge.kt` requests `AUDIOFOCUS_GAIN_TRANSIENT`
   (`USAGE_MEDIA`, speech, no delayed gain, "may duck" losses delivered
   rather than ducked by the system) and abandons it; the Dart side
   is `AudioFocusPort` in `lib/core/audio_focus/`. `HandsFreeController`
   requests it on entering Listening, before the recorder starts, and
   abandons it at once on entering Standby or Off, so a later request
   always reaches the platform after the abandon. The controller gives
   back only a focus it holds (or is asking for): the platform keeps one
   focus per app, shared with push-to-talk.
3. **A loss means Standby.** A permanent loss (another app plays) and a
   transient one (a call, an assistant) send `interrupted`: Listening
   becomes Standby and the recorder stops. A "may duck" loss (a chime, a
   navigation prompt) is ignored. A regained focus does not resume: the
   user resumes, as with a video app.
4. **A refused focus means Standby with a message.** Android refuses the
   request during a call; the mode becomes Standby with "The microphone is
   busy (a call).", and no recorder starts.
5. **Push-to-talk holds the same transient focus** while the button is
   held, requested before its recorder starts and given back when it
   stops, is cancelled or fails. A refusal does not stop an explicit
   press, and a loss does not stop it either: before, the plugin paused a
   push-to-talk recording on any loss; now it records on (a call gives it
   silence) until the button is released.

## Consequences

- A video paused by Listening resumes on Pause and on Stop; a call or a
  video started elsewhere moves Listening to Standby, as a video app would
  pause.
- The silent-mic watchdog runs only in Listening (ADR-AUDIO-013's Standby
  stops the engine), and a focus loss no longer stops the chunks behind
  its back.
- The replies are spoken by Android's TTS engine with no focus request
  (`flutter_tts` `focus: false`). If an engine took focus itself, a reply
  would move Listening to Standby; the device check of the manual plan
  (T11) covers it.
- One focus per app means one known gap: a resume of Listening while a
  push-to-talk is held (only reachable from the error strip's Retry) is
  followed by push-to-talk's abandon, leaving Listening without focus
  until the next pause and resume.
- The processing sound already takes no focus (`audioplayers`,
  `AndroidAudioFocus.none`).
