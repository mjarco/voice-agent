# Manual test: three microphone modes on Android

**Design:** [ADR-AUDIO-013](../decisions/ADR-AUDIO-013-android-three-microphone-modes.md), [ADR-AUDIO-014](../decisions/ADR-AUDIO-014-android-own-transient-audio-focus.md); workspace epic `2026-11-mic-modes/01-mic-modes` and its design note `research/2026-11-voice-agent-mic-states/reviewed/04-simplified-model.md`; PR #405 (task 2), PR #406 (task 3).
**Overall status:** **pending**. Begun in task 2 with its cases; tasks 3–5 add theirs, and the whole plan runs once in task 6.
**Why now:** whether the microphone is really released in Standby, the locked phone, the headset and the green dot exist only on a device.
**When:** once, at the end of the epic (task 6). Task 2 gets only a smoke run of T1–T4 on a dev build.
**Time budget:** ~30 min for task 2's cases, ~15 min for task 3's (agent, dev flavor over USB adb); the headset cases need the owner.
**What we are testing:** task 2: the eight transitions of the model where task 2 implements them, tabs that do not touch the microphone, and Standby that releases the microphone on a locked phone and comes back from a headset press.

## Status legend

See the canonical legend in [`p040-agenda-notifications.md`](p040-agenda-notifications.md#status-legend).

## Status summary

| # | Case | Status |
|---|---|---|
| S1 | Dev build pointed at a test PA | pending |
| S2 | Reading the microphone state over adb | pending |
| T1 | Off → Listening from the mic button | pending |
| T2 | Listening → Standby from a tap releases the microphone | pending |
| T3 | Standby → Listening from a tap | pending |
| T4 | Stop from Listening and from Standby ends in Off | pending |
| T5 | An utterance and its reply keep Listening open | pending |
| T6 | Tabs do not touch the microphone | pending |
| T7 | Locked phone: the headset pauses and resumes | pending |
| T8 | A reply in Standby is not spoken | pending |
| T9 | Push-to-talk from Listening returns to Listening | pending |
| T10 | Farewell phrase ends in Off | pending |
| T11 | Focus held in Listening only, and a reply keeps it | pending |
| T12 | Another app's sound moves Listening to Standby | pending |
| T13 | A paused video resumes on Pause and on Stop | pending |
| T14 | A call means Standby; a start during a call is refused | pending |

---

## Setup

### S1. Dev build pointed at a test PA

**Status:** pending

**Do:** set up the dev build and the test PA as the workspace skill `ws-device-check` describes (never `.env.mobile`, never `:8888`; `pm clear` after install; read the URL in Settings and tap Test Connection). Grant the microphone and notifications.

### S2. Reading the microphone state over adb

**Status:** pending

**Do:** keep these at hand; T2–T7 read them after each step.

```bash
adb -s <serial> shell dumpsys audio | grep -A3 "RecordActivityMonitor"     # active recorders
adb -s <serial> shell dumpsys audio | sed -n '/Audio Focus stack/,/^$/p'      # who holds the focus
adb -s <serial> shell dumpsys activity services com.voiceagent.voice_agent.dev | grep -c ServiceRecord
```

The dev flavor also sends the telemetry events `hf.mic_mode` (from, to, event) and `hf.gate_changed` (open, reason) through the pipeline of [`observability.md`](../observability.md), when it runs; the cases do not depend on it.

---

## Cases

### T1. Off → Listening from the mic button

**Status:** pending

**Do:**
1. Open the app on Record. The label reads "Tap to start listening"; no Stop button.
2. Tap the mic.

**Why:** ADR-AUDIO-013, decision 1 (start only from the app) and 5 (Stop shown when not Off).
**Expected:** the label reads "Listening — tap to pause"; a "Stop" button appears under it; the green dot shows; `RecordActivityMonitor` lists one active recorder of the app; the service runs; with telemetry on, `hf.mic_mode` reads `off → listening, start`.
**On failure:** a "Groq API key not set" or "API URL not set" error means S1 was skipped. No recorder: the error strip under the screen shows the engine's message.

### T2. Listening → Standby from a tap releases the microphone

**Status:** pending

**Do:** in Listening, tap the mic. Wait 5 s and read S2.

**Why:** ADR-AUDIO-013, decision 2 (plan A: Standby releases the microphone).
**Expected:** the label reads "Standby — tap to resume"; Stop is still shown; the green dot goes out; no active recorder of the app; the service still runs; a video paused by Listening may resume (until task 3 the focus is the plugin's, given back when the recorder stops).
**On failure:** a recorder still listed means the engine was not stopped (`HandsFreeController._enterStandby`).

### T3. Standby → Listening from a tap

**Status:** pending

**Do:** in Standby, tap the mic. Say a short sentence.

**Why:** ADR-AUDIO-013, decision 2 (resume is a cold start).
**Expected:** the label reads "Listening — tap to pause"; the green dot shows; the sentence becomes a segment and reaches the test PA once.
**On failure:** no segment: the gate stayed closed after the cold start (`HandsFreeController._enterListening`; with telemetry on, `hf.gate_changed` `open: false` with no later `open: true`).

### T4. Stop from Listening and from Standby ends in Off

**Status:** pending

**Do:**
1. From Listening, tap Stop.
2. Tap the mic, then tap it again (Standby), then tap Stop.

**Why:** ADR-AUDIO-013, decision 1 (stop → Off from either mode); #380 (Standby with an empty queue still stops the service).
**Expected:** after each Stop: the label reads "Tap to start listening"; no Stop button; no recorder; no foreground service; no notification.
**On failure:** a service left running after step 2 is #380 coming back: `stopSession` returned early.

### T5. An utterance and its reply keep Listening open

**Status:** pending

**Do:** in Listening, ask a question that gets a spoken reply; then say a second sentence without touching anything.

**Why:** ADR-AUDIO-013, decision 3 (no gate per utterance; the gate closes only while a reply is spoken).
**Expected:** the label reads "Listening — tap to pause" through the whole turn; the reply is not transcribed as an utterance; the second sentence becomes a segment.
**On failure:** the reply comes back as an utterance: the gate did not close for TTS.

### T6. Tabs do not touch the microphone

**Status:** pending

**Do:**
1. In Listening, go to Agenda, then Chat, then back to Record. Read S2 on each tab.
2. Repeat from Standby and from Off.

**Why:** ADR-AUDIO-013, decision 4.
**Expected:** the recorder and the service are the same on every tab as before the switch, and the label on Record is unchanged.
**On failure:** a stop or a start on a tab change: the shell still drives the session (`app_shell_scaffold.dart`).

### T7. Locked phone: the headset pauses and resumes

**Status:** pending (owner: a real headset)

**Do:**
1. In Listening, lock the phone. Press the headset button once.
2. Wait a minute. Press it again and say a sentence.

**Why:** ADR-AUDIO-013, decisions 2 and 5; the probe of 2026-11-07 used `cmd media_session dispatch`, not a headset.
**Expected:** after step 1: no active recorder; the service runs. After step 2: a recorder again, `not silenced` in `dumpsys audio`, and the sentence reaches the test PA.
**On failure:** no press reaches the app: another app holds the media button (ADR-AUDIO-012; the claim on entering Listening comes in task 4). A recorder that records silence: `dumpsys audio` says `silenced`, and logcat names the while-in-use restriction.

### T8. A reply in Standby is not spoken

**Status:** pending

**Do:** in Listening, ask a question with a long answer and pause (tap) before the reply arrives.

**Why:** ADR-AUDIO-013, decision 6.
**Expected:** no speech; the reply is in Chat.
**On failure:** speech in Standby: `getTtsEnabled` ignores the mode (`sync_provider.dart`).

### T9. Push-to-talk from Listening returns to Listening

**Status:** pending

**Do:**
1. In Listening, hold the mic, speak, release.
2. In Listening, hold the mic, speak, and press Home before releasing (or release with the app in the background).

**Why:** ADR-AUDIO-013, decision 5 (push-to-talk puts Listening into Standby and returns only in the foreground).
**Expected:** step 1: Standby while held, Listening after the release, one recorder at a time; while held, the focus stack (S2) shows the app's `GAIN_TRANSIENT` and no `AUDIOFOCUS_GAIN` of the plugin (ADR-AUDIO-014, decision 5). Step 2: the session stays in Standby, with no focus entry of the app.
**On failure:** two recorders listed at once: the hands-free recorder was not stopped for push-to-talk.

### T10. Farewell phrase ends in Off

**Status:** pending

**Do:** in Listening, say "dobranoc".

**Why:** ADR-AUDIO-013, decision 1 (farewell → Off).
**Expected:** after the reply ends: Off, no recorder, no service, no notification.
**On failure:** the session-control signal did not reach `stopSession`; look for `[SessionControlDispatcher]` in `adb logcat -s flutter`.

### T11. Focus held in Listening only, and a reply keeps it

**Status:** pending

**Do:**
1. Off: read the focus stack (S2). Start Listening and read it again.
2. Ask a question that gets a spoken reply; read the stack while it is spoken and after.
3. Pause (tap) and read it; Stop and read it.

**Why:** ADR-AUDIO-014, decisions 1–2 (the plugin takes none; the app holds `AUDIOFOCUS_GAIN_TRANSIENT` in Listening only), and its consequence on the TTS engine.
**Expected:** step 1: no entry of the app in Off; in Listening one entry of `com.voiceagent.voice_agent.dev` with `GAIN_TRANSIENT`, and no `AUDIOFOCUS_GAIN` entry of the app (the plugin's). Step 2: the label stays "Listening — tap to pause" through the reply and the app's entry stays. Step 3: no entry of the app after Pause, nor after Stop.
**On failure:** an `AUDIOFOCUS_GAIN` entry: the plugin still takes focus (`audioInterruption` in `recording_providers.dart`). Standby during a reply: the TTS engine takes the focus itself (logcat `AudioFocusBridge: focus change`); ADR-AUDIO-014 names the fallback.

### T12. Another app's sound moves Listening to Standby

**Status:** pending

**Do:** in Listening, start a video or music in another app (the agent: `adb shell am start -a android.intent.action.VIEW -d <a video URL>`).

**Why:** ADR-AUDIO-014, decision 3 (a permanent or transient loss means Standby).
**Expected:** the label reads "Standby — tap to resume"; no active recorder of the app; the service runs; the other app plays. Tapping the mic resumes Listening and pauses the other app again.
**On failure:** Listening goes on: no loss reached Dart (logcat `AudioFocusBridge`), or the controller ignored it (`_onFocusLoss`).

### T13. A paused video resumes on Pause and on Stop

**Status:** pending (owner: a real video app)

**Do:**
1. Play a video, open voice-agent, start Listening.
2. Pause from the app. Then resume, and Stop.

**Why:** ADR-AUDIO-014, consequence 1 and the model's decision 2 (other apps' sound pauses in Listening and resumes on Pause or Stop).
**Expected:** step 1: the video pauses. Step 2: it resumes on Pause, pauses again on resume, and resumes on Stop.
**On failure:** the video stays paused for good: a permanent focus was taken (T11), or the video app does not resume after a transient loss (an app limitation, note which app).

### T14. A call means Standby; a start during a call is refused

**Status:** pending (owner: a real call)

**Do:**
1. In Listening, receive a call; answer it; hang up.
2. During a call, open the app in Off and tap the mic.

**Why:** ADR-AUDIO-014, decisions 3 and 4.
**Expected:** step 1: Standby when the call rings and after it ends (no resume by itself). Step 2: Standby with "The microphone is busy (a call)."; no recorder; tapping the mic after the call resumes Listening.
**On failure:** Listening during the call: the ringtone's loss did not reach the app. Listening in step 2: the request was granted during the call; note the Android version.

---

## When this plan is done

Must pass: T1–T6, T8–T12. T7, T13 and T14 need the owner (a headset, a video app, a call); its result decides whether task 4's media-button claim is enough. Tasks 3–5 add their cases here before task 6 runs the plan.
