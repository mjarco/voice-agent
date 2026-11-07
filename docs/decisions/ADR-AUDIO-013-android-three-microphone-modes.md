# ADR-AUDIO-013: Three microphone modes on Android (Off, Listening, Standby)

Status: Accepted
Decided in: PR #405 (epic 2026-11-mic-modes/01-mic-modes, task 2)
Supersedes: [ADR-AUDIO-011](./ADR-AUDIO-011-always-on-capture-with-engagement-gate.md) **on Android only**. iOS keeps ADR-AUDIO-011 unchanged.
Extended by: [ADR-AUDIO-014](./ADR-AUDIO-014-android-own-transient-audio-focus.md) (the app's own audio focus), [ADR-AUDIO-015](./ADR-AUDIO-015-android-notification-and-headset-follow-the-mode.md) (the notification and the headset button per mode).
Design note: the workspace docs, `research/2026-11-voice-agent-mic-states/reviewed/04-simplified-model.md` (accepted by the owner on 2026-11-07), with the device probe in `requirements/roadmaps/2026-11-mic-modes/epics/01-mic-modes/source/2026-11-07-probe-run.md`.

## Context

ADR-AUDIO-011 keeps the recorder running for the whole app session and
ignores its audio behind a capture gate, because iOS refuses to start a
recorder from a locked-screen button press. On Android the same model left
the user without a real "off": with the gate closed the app still held the
microphone, the audio focus (a paused video stayed paused) and the
foreground service. Moving between tabs started and stopped listening;
every utterance closed the gate and a reply reopened it, over a hidden
state with about 20 transitions.

Android has a different rule. A microphone foreground service cannot be
*created* from the background, but one started from the visible app keeps
running when the app leaves the screen. Whether the app may *start the
recorder again* from the background while that service runs is not
documented. A device probe answered it on 2026-11-07 (Pixel 11 Pro,
Android 17, locked, deep Doze): a new `AudioRecord` started from a
media-button press after 60 s and after 10 min of rest, recorded real sound,
and Android logged it `not silenced`. The process kept the microphone
capability (`--MNFUATI`) while locked, and each press carried a temporary
while-in-use allowlist (`[WIU] [FGS]`).

## Decision

On Android, `HandsFreeController` runs three modes, `MicMode` in
`lib/core/session_control/mic_mode.dart`:

| | Off | Listening | Standby |
|---|---|---|---|
| Recorder | stopped | running | **stopped: the mic is released** |
| Foreground service | stopped | running | running |
| Job queue, session flag | drained, false | kept, true | kept, true |
| Replies | spoken | spoken; the gate closes while one is spoken | not spoken |

1. **Eight transitions, one table.** Every mode change goes through
   `nextMicMode` (`lib/features/recording/domain/mic_mode_machine.dart`):
   start (Off → Listening, from the app only), pause, an interruption and an
   engine error (Listening → Standby), resume (Standby → Listening), stop,
   a farewell and the task swiped away (→ Off). Anything else is ignored.
2. **Standby releases the microphone** (plan A of the design note).
   Resume is a cold recorder start with no start-up guards. Starts and
   stops of the one long-lived orchestrator never overlap: a resume waits
   for every stop still running and only the latest resume starts; the
   orchestrator's own stop after a stream error is awaited by a caller's
   stop; a start during a Stop's drain waits for it.
3. **No gate per utterance.** Listening is meant to continue. The capture
   gate survives only to ignore the mic while a reply is spoken, so the
   agent does not hear itself.
4. **Tabs do not touch the microphone.** The shell no longer stops and
   starts the session on tab changes (this removes the path of #380).
5. **The Record screen follows the mode.** A tap starts, pauses or resumes;
   a separate Stop button is shown whenever the mode is not Off. The
   headset button toggles Listening ↔ Standby; in Off it only stops a
   reply being spoken and never starts a session.
   Push-to-talk puts Listening into Standby for the recording and returns
   to Listening only if the app is still in the foreground.
6. **A reply in Standby is not spoken**: the sync worker's TTS switch also
   checks the mode. Pause means quiet; a pause also stops a reply being
   spoken.
7. **An engine error after the start means Standby with its message.** The
   service stays, so the session can resume from anywhere.

## Consequences

- The green dot and the recorder follow Listening only; Standby leaves the
  mic, and the focus taken by the `record` plugin, to other apps.
- iOS and Android now run two paths in one controller, switched by
  `micModesEnabledProvider` (`Platform.isAndroid`). Retiring iOS would
  remove the ADR-AUDIO-011 path.
- Not decided here, and left to later tasks of the epic: an audio focus of
  our own (transient, with the plugin set to take none) and a call meaning
  Standby; the notification text and buttons per mode, the media-button
  claim only on entering Listening, and Off on a task swipe
  (`stopWithTask`); the processing sound.
- Not proven on a device: a recorder restart with no user action behind it
  (the watchdog in the background). In this model only Listening restarts
  by itself, and the process kept the microphone capability with no press,
  so it is probably allowed.
- A farewell reaches the controller as a Stop (the session-control
  dispatcher calls `stopSession`), so a farewell transcribed from a job
  still in flight after a pause ends Standby too. The table keeps its
  `farewell` row for the model; nothing sends it yet.
- STT and network errors keep today's behaviour (a failed job, Listening
  goes on); only an engine error moves to Standby.
