# ADR-AUDIO-015: On Android the notification and the headset button follow the microphone mode

Status: Accepted
Decided in: PR #407 (epic 2026-11-mic-modes/01-mic-modes, task 4)
Amends: [ADR-AUDIO-012](./ADR-AUDIO-012-android-media-button-routing.md). Its claim with silence stays; when it runs and how long the session lives change (decision 3). Adds to [ADR-AUDIO-013](./ADR-AUDIO-013-android-three-microphone-modes.md). iOS is unchanged.
Design note: the workspace docs, `research/2026-11-voice-agent-mic-states/reviewed/04-simplified-model.md` (the mode table, the transitions, section 4 "Who gets the headset button").

## Context

After ADR-AUDIO-013 and ADR-AUDIO-014 the modes worked inside the app. Outside it, three things did not follow the mode:

- **The notification.** It always read "Recording session active" and had no buttons, so outside the app nothing said whether the app listened, and only the headset could pause.
- **The headset button.** The media session was active from the moment the Record screen first opened, in every mode. `MainActivity.onResume` claimed the button every time the app came back. After a visit to the app, a press went to voice-agent instead of a paused video, and after a Stop a press still went to voice-agent, which did nothing with it.
- **A swipe from recents.** It destroys the activity and its engine. Without `stopWithTask`, `flutter_foreground_task` 9.2.2 then sets an alarm that restarts its service after a second (`ForegroundService.onTaskRemoved`). The result is a notification with no session behind it.

The plugin can change the notification's text and buttons while the service runs (`updateService`). It hands a button press only to Dart code running in its own service engine. voice-agent runs none there: the service is a keepalive without a `TaskHandler`.

## Decision

On Android:

1. **The notification shows the mode.**
   - Listening: "Listening", with the buttons Pause and Stop.
   - Standby: "Standby", with Resume and Stop. When Standby was not asked for, the text adds why: the error's message, "The microphone is busy (a call).", or "Paused by another app or a call." after a loss of the focus.
   - Off: there is no service, so there is no notification.
   - `HandsFreeController` updates the notification on entering each mode. The updates are chained so they reach the plugin in order.
2. **A button press reaches the app through a receiver of our own.**
   - The plugin's button is a broadcast to this package, with the action `onNotificationButtonPressed` and the button id in the extra `intentData`.
   - `NotificationActionBridge.kt` registers a not-exported receiver for that action while the app's engine listens, and sends the id to Dart (`com.voiceagent/notification_actions/events`).
   - The controller maps `pause`, `resume` and `stop` to `pauseSession`, `resumeSession` and `stopSession`. A press that no longer fits the mode is ignored by the mode table. Resume is ignored while push-to-talk records, since the end of the recording returns to Listening by itself.
   - The alternative was a `TaskHandler` forwarding the press with `sendDataToMain`. It was not chosen: it runs a second Dart isolate, with every plugin attached, in the service next to the microphone.
3. **The media session lives outside Off only, and the claim runs on entering Listening.**
   - On entering Listening, after the focus is granted and before the recorder starts, the controller calls `claim`. The bridge activates the session if there is none, which claims, or claims again. This happens on a start and on every resume.
   - Standby keeps the session, so a headset press resumes, unless another app has played since.
   - Stop releases the session, so in Off a press goes to the last app that played.
   - `MainActivity.onResume` no longer claims. The Record screen activates the session itself only without the modes (iOS).
4. **A swipe from recents means Off.**
   - The plugin's `<service>` in `AndroidManifest.xml` carries `android:stopWithTask="true"`. The swipe stops the service, and the plugin, which reads the same flag, sets no restart alarm.
   - The plugin's own `stopWithTask` option is not used. Set, it stops the service whenever no activity is resumed (`TrackVisibilityUtils`, installed in `onStartCommand`): a locked screen or a press on Home would end listening. Each `updateService` without options also removes it again. A test checks that the option stays unset and that the manifest has the flag.
   - The engine's cleanup (`MainActivity.cleanUpFlutterEngine`) releases the media session, gives back the focus and stops listening for buttons. The `record` plugin stops its recorder when the engine detaches.
5. **A Stop waits for the notification updates already queued**, so none reaches the plugin after its stop and brings the service back. The wrapper turns the plugin's failure result into an error, so a failed update shows in the telemetry (`hf.notification_failed`).

## Consequences

- **The two plugin names.** The receiver depends on two internal names of `flutter_foreground_task`: `onNotificationButtonPressed` and `intentData`, both in `ForegroundService.kt` of 9.2.2. Check both when upgrading the plugin. If they change, the buttons do nothing, silently. The bridge logs every press it receives, so the symptom is a missing `NotificationActionBridge: button pressed` line.
- **The headset in Off.** In Off the headset no longer pauses a push-to-talk recording and no longer stops a spoken reply: the press goes to another app.
- **A press while a video is paused.** In Standby after another app has played, a press goes to that app, as with YouTube and Spotify. You resume voice-agent from the notification or the app.
- **A swipe loses work in flight.** Utterances not yet transcribed when the app is swiped away are lost. This was so before as well: the engine dies with the task.
- **A button on the locked screen** may first ask Android for the unlock. That depends on the lock-screen settings, not on the app.
- **The session state stays "paused".** The press stays a toggle (ADR-AUDIO-013). The lock screen shows no media controls and no artwork.
