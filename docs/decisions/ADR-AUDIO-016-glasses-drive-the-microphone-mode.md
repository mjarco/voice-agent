# ADR-AUDIO-016: On Android the G2 glasses drive the microphone mode through glass-native

Status: Accepted
Decided in: off-roadmap task `2026-11-11-glasses-start-conversation` of the workspace (D2, D4)
Adds to: [ADR-AUDIO-013](./ADR-AUDIO-013-android-three-microphone-modes.md) and [ADR-AUDIO-015](./ADR-AUDIO-015-android-notification-and-headset-follow-the-mode.md). iOS is unchanged.
Contract: glass-native's `docs/va-control-protocol.md`.

## Context

The owner wants to start a voice-agent conversation from the G2 glasses. glass-native, on the same
phone, holds the glasses and gets their touch. Its menu gets a page "Rozmowa" that shows
voice-agent's microphone mode and switches it: Włącz (Listening), Pauza (Standby), Wyłącz (Off,
also from Standby). The microphone stays the phone's; replies stay in voice-agent.

voice-agent could already be driven from outside the app by the headset button and the
notification's buttons (ADR-AUDIO-015). Both work only while the session's foreground service runs.
A microphone foreground service cannot be *created* from the background (ADR-AUDIO-013), so a start
from Off sent by another app may be refused by Android.

## Decision

1. **A way in.** `GlassesControlReceiver`, exported under the permission
   `<applicationId>.permission.MIC` (normal), takes `com.voiceagent.voice_agent.action.MIC` with
   `command` = listening | standby | off | status. A command goes to Dart through
   `GlassesControlBridge` (MethodChannel `com.voiceagent/glasses_control`, EventChannel
   `…/events`) while an engine runs; without one it is answered `blocked`. An ordered broadcast
   gets the answer and the mode back.
2. **The moves are the notification's.** `HandsFreeController` maps listening to Resume from
   Standby (not while push-to-talk records) and to `startSession` from Off, standby to Pause from
   Listening, off to Stop from Listening or Standby. A command that already holds, or does not fit
   the mode, changes nothing.
3. **A way back.** Every mode change goes through `_applyMicEvent`, which reports the mode to the
   bridge; the bridge sends `casa.jarco.glassnative.action.VA_MODE` to glass-native under the
   wake's permission. An engine that goes away reports Off.

## Consequences

- The glasses show the real mode: a change made in the app, by the headset or by the notification
  reaches the page too.
- Any installed app may request a `normal` permission. It could then switch the microphone off or
  into Standby, or start a session, exactly as the notification's buttons do; it cannot read
  anything. The same level as glass-native's wake permission.
- A start from Off while voice-agent is in the background depends on Android allowing the
  microphone service to start. The owner ran the page on the Pixel on 2026-11-11 and found it
  working, so glass-native offers Włącz in Off; the case is T5 of the manual plan
  [glasses-control.md](../manual-tests/glasses-control.md), and a refusal there switches the page
  to "Włącz w telefonie" (`VA_START_FROM_OFF` in glass-native) without changing this decision.
