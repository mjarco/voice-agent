# ADR-AUDIO-012: Android media-button routing — claim with a burst of silence, one session per engine

Status: Accepted
Decided in: #358, PR #361
Related: [ADR-AUDIO-010](./ADR-AUDIO-010-ios-media-button-routing-constraints.md) (the iOS counterpart)

## Context

On the Pixel 11 Pro (Android 17) the headset play/pause button never reached the app: case T2 of
`docs/manual-tests/android-pixel-baseline.md`, 0 of 3, on 2026-10-21. `MediaButtonBridge` had an
active `MediaSessionCompat` in `STATE_PAUSED`, but `dumpsys media_session` reported
`Media button session is null` and handed the press to the last `MediaButtonReceiver` (YouTube).

Two causes, found on the device:

1. Android gives the media button to the session of the app whose UID most recently **played
   audio** (`dumpsys media_session`, "Audio playback (lastly played comes first)"). The app never
   plays audio under its own UID: TTS replies are played by the TTS engine
   (`com.google.android.tts`), and the silent keep-alive loops of ADR-AUDIO-010 are disabled
   (they took over the iOS audio session and killed the mic).
2. The app could hold two sessions: one left behind by an earlier `MainActivity` instance whose
   engine was destroyed while the process stayed alive (destroy and relaunch; `configChanges`
   covers almost every recreation, and the foreground-service engine never runs
   `configureFlutterEngine`). That session held the routing, and its event sink led nowhere, so
   presses reached `onPlay` natively but never Dart.

## Decision

1. `MediaButtonBridge.claimMediaButtonRouting()` plays 300 ms of PCM zeros through a native
   `AudioTrack` (`USAGE_MEDIA`, static mode, released right after) when the session activates
   and when `MainActivity` resumes. The samples are silent; the player is not muted, because a
   muted player may not count as playback. Starting a media stream can still wake an idle
   Bluetooth (A2DP) link, which some headsets mark with a click. No audio focus is requested, so other apps'
   playback is not interrupted, and the recorder is not touched.
2. `MainActivity.cleanUpFlutterEngine` releases the bridge's session, so there is at most one
   `VoiceAgentMediaSession` per live engine.

Android only; iOS keeps ADR-AUDIO-010.

## Rationale

The selection rule only looks at which UID played last, so the smallest thing that satisfies it is
a short playback under the app's UID. Doing it natively avoids `audioplayers`, whose session
handling is the reason the iOS loops are off. The TTS engine's UID has no media session, so a TTS
reply does not take the routing away; another media app's playback does, hence the claim on resume.

## Consequences

- Verified on the Pixel 11 Pro, Android 17, on 2026-10-21: after the change `dumpsys
  media_session` reports `Media button session is …/VoiceAgentMediaSession`; T2 (start hands-free
  from idle) and T3 (interrupt TTS) pass 3 of 3; with music playing in another app the button
  pauses that app, and after returning to Voice Agent it engages hands-free again.
- Returning to the app makes it the media-button target even if music keeps playing in the
  background: a press then goes to Voice Agent, not to the music app.
- A press while hands-free is listening is delivered on Android (on iOS it is blocked) and hits the
  `listening-noop` branch in `recording_screen.dart`; what it should do there is a product
  decision outside this ADR.
- The claim on resume also runs while hands-free is listening (e.g. after unlocking the screen).
  No click was reported with the owner's Bluetooth headset; if one appears, gate the claim on the
  capture state.
- If Android changes the selection rule (e.g. ignores silent playback), the claim stops working;
  the symptom is `Media button session is null` again.
