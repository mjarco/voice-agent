# Manual test: Android baseline on the Pixel

**Issue:** [#352](https://github.com/mjarco/voice-agent/issues/352), the last task of the workspace epic `voice-agent-on-pixel` (after [#349](https://github.com/mjarco/voice-agent/issues/349) build, [#350](https://github.com/mjarco/voice-agent/issues/350) manifest, [#351](https://github.com/mjarco/voice-agent/issues/351) Polish TTS).
**Overall status:** **passed** (2026-10-21, Pixel 11 Pro, Android 17): T1, T4, T6 passed on the first run (1.4.3 (11)); T5 after [#357](https://github.com/mjarco/voice-agent/issues/357) (1.4.4 (12)); T2 and T3 after [#358](https://github.com/mjarco/voice-agent/issues/358) (1.4.5 (13)).
**Why now:** voice-agent has been built for Android only since v1.4.1. The voice loop, the headset button, scheduled reminders and WorkManager are device-only contracts, and none of them has a recorded pass on Android.
**Time budget:** ~30 min active, plus waiting for T5 (a reminder 3 minutes ahead).
**What we are testing:** that the Pixel can replace the iPhone for talking to personal-agent: hands-free turns in Polish, the headset play/pause button, routine reminders and the background agenda refresh. Unit tests (`make verify`) cover the logic; this plan covers only what they cannot.

## Status legend

See the canonical legend in [`p040-agenda-notifications.md`](p040-agenda-notifications.md#status-legend).

## Status summary

| # | Case | Status |
|---|---|---|
| S1 | Install on the Pixel | passed (2026-10-21, Pixel 11 Pro, Android 17, 1.4.3 (11)) |
| S2 | Backend state | passed (2026-10-21, Pixel 11 Pro, Android 17, 1.4.3 (11)) |
| S3 | Log capture | passed (2026-10-21, Pixel 11 Pro, Android 17, 1.4.3 (11)) |
| T1 | Five hands-free turns in one session | passed (2026-10-21, Pixel 11 Pro, Android 17, 1.4.3 (11)) |
| T2 | Headset button starts hands-free from idle, 3 of 3 | passed (2026-10-21, Pixel 11 Pro, Android 17, 1.4.5 (13)) |
| T3 | Headset button interrupts TTS, 3 of 3 | passed (2026-10-21, Pixel 11 Pro, Android 17, 1.4.5 (13)) |
| T4 | Hands-free with the screen off | passed (2026-10-21, Pixel 11 Pro, Android 17, 1.4.3 (11)) |
| T5 | Routine reminder fires at `start_time` (p040 T5) | passed (2026-10-21, Pixel 11 Pro, Android 17, 1.4.4 (12)) |
| T6 | WorkManager agenda refresh registered (p040 T9) | passed (2026-10-21, Pixel 11 Pro, Android 17, 1.4.3 (11)) |

---

## Setup

### S1 — Install on the Pixel

**Status:** passed (2026-10-21, Pixel 11 Pro, Android 17, 1.4.3 (11))

**Do:** on laptop.lan, with the Pixel connected over USB or wireless debugging:

```bash
make install-android-dev    # or make install-android for the stable flavour
```

Record the installed build in every status line: Settings shows it (e.g. `1.4.3 (11)`), or
`adb shell dumpsys package com.voiceagent.voice_agent.dev | grep versionName`.

**Why:** `adb install -r` keeps the app data, so the API URL, token and Groq key stay configured.

### S2 — Backend state

**Status:** passed (2026-10-21, Pixel 11 Pro, Android 17, 1.4.3 (11))

**Do:** in the personal-agent web UI, create a routine with an occurrence today whose `start_time` is about 5 minutes ahead (for T5). Note the routine's name.

**Why:** T5 needs an occurrence with `start_time`; occurrences without it produce no per-occurrence reminder (P040 §Time Resolution).

### S3 — Log capture

**Status:** passed (2026-10-21, Pixel 11 Pro, Android 17, 1.4.3 (11))

**Do:** on laptop.lan, before each test session:

```bash
~/Android/Sdk/platform-tools/adb logcat -c
~/Android/Sdk/platform-tools/adb logcat -v time flutter:V AndroidRuntime:E '*:S'
```

**Why:** the `Expected` lines below quote `[MediaButtonDbg]`, `[TtsDbg]` and `[HFO]` log lines; they are printed in release builds too.

---

## Tests

### T1 — Five hands-free turns in one session (~5 min)

**Status:** passed (2026-10-21, Pixel 11 Pro, Android 17, 1.4.3 (11)): owner confirmed five Polish replies and the task added then removed; log shows `[TtsDbg] language=pl … voice=pl-pl-x-oda-local`, four spoken replies 20:34–20:36 in one process, no errors; `kupić mleko` absent from the agenda afterwards

**Do:**
1. Open the Record tab and tap the mic to engage hands-free ("Listening").
2. Say, one at a time, waiting for each spoken reply:
   1. "dodaj zadanie na jutro: kupić mleko"
   2. "jaka jest moja agenda na jutro"
   3. "przenieś kupić mleko na pojutrze"
   4. "co mam dziś do zrobienia"
   5. "usuń zadanie kupić mleko"
3. Re-engage with a tap only if the session ends on its own; do not restart the app.

**Why:** epic criteria 2 and 4: a Polish turn ends with a spoken reply and the change in the agenda; five consecutive turns without a restart.

**Expected:** five replies spoken in a Polish voice (`[TtsDbg] language=pl … voice=pl-pl-…`); after turn 1 the task is under tomorrow in the Agenda tab, after turn 5 it is gone. No `AndroidRuntime` errors.

**On failure:**
- English voice: `[TtsDbg]` shows `language=en`, i.e. both the reply and the transcript lack a language; see #351 and thought-agent#551.
- No reply after a turn: check the History list for the transcript's sync status, then personal-agent's log.
- Session stuck in "Listening" with no reaction: VAD did not load; look for `Unable to load asset` (the model is missing from the APK, run `make vad-model`).

### T2 — Headset button starts hands-free from idle, 3 of 3 (~3 min)

**Status:** passed (2026-10-21, Pixel 11 Pro, Android 17, 1.4.5 (13)): re-run after [#358](https://github.com/mjarco/voice-agent/issues/358) (PR #361), 3 of 3 (owner); log `[MediaButtonDbg] branch=engage`. First run failed on 1.4.3 (11): no `[MediaButtonDbg]` event, `Media button session is null`

**Do:**
1. Connect a Bluetooth headset. Open the app on the Record tab, hands-free idle.
2. Press play/pause on the headset once. Say a short sentence and wait for the reply.
3. Let the session end (or tap the mic to stop). Repeat steps 2–3 twice more.

**Why:** epic criterion 3, the start half: `MediaButtonBridge.kt` turns a media-session play/pause into `togglePlayPause`, and from `HandsFreeIdle` the app engages (P037 v2).

**Expected:** each press shows the "Listening" toast with a haptic tick; log: `[MediaButtonDbg] _onMediaButtonEvent event=MediaButtonEvent.togglePlayPause … hfState=HandsFreeIdle` then `[MediaButtonDbg] branch=engage`. 3 of 3.

**On failure:**
- No `[MediaButtonDbg]` line at all: another app owns the media session (a music player); stop it and retry. Check `[MediaButtonDbg] Dart→native activate() returned` at start-up.
- `branch=noop`: the app was not idle (e.g. still processing); wait for idle.

### T3 — Headset button interrupts TTS, 3 of 3 (~3 min)

**Status:** passed (2026-10-21, Pixel 11 Pro, Android 17, 1.4.5 (13)): re-run after [#358](https://github.com/mjarco/voice-agent/issues/358) (PR #361), 3 of 3 (owner); log `[MediaButtonDbg] branch=stopTts` (2 of the 3 presses captured). First run failed on 1.4.3 (11): no `[MediaButtonDbg]` event, `Media button session is null`

**Do:**
1. Ask something with a long answer ("opowiedz mi o moich zadaniach na ten tydzień").
2. While the reply is being spoken, press play/pause on the headset.
3. Repeat twice more.

**Why:** epic criterion 3, the interrupt half: with TTS playing, play/pause stops it.

**Expected:** speech stops within about a second of each press; log: `[MediaButtonDbg] … ttsPlayingProvider=true …` then `[MediaButtonDbg] branch=stopTts`. 3 of 3.

**On failure:** `ttsPlayingProvider=false` while speech is audible means the TTS state did not reach the provider; look at `[TtsDbg]` lines around the press.

### T4 — Hands-free with the screen off (~2 min)

**Status:** passed (2026-10-21, Pixel 11 Pro, Android 17, 1.4.3 (11)): reply spoken with the screen off (owner); `dumpsys activity services` shows `ForegroundService` `isForeground=true types=0x00000082`; no foreground-service exception in logcat

**Do:**
1. Engage hands-free. Check the notification shade for the "Voice Agent" foreground notification.
2. Turn the screen off with the power button.
3. Ask "jaka jest moja agenda na jutro" and wait.

**Why:** #350: the foreground service (`microphone|mediaPlayback`) keeps capture and TTS alive with the screen off.

**Expected:** the notification is shown; the reply is spoken with the screen off. No `ForegroundServiceStartNotAllowedException` or `MissingForegroundServiceTypeException` in `adb logcat -d`.

**On failure:** check that the merged manifest still declares the service: `~/Android/Sdk/cmdline-tools/latest/bin/apkanalyzer manifest print build/app/outputs/flutter-apk/app-dev-release.apk | grep -A2 flutter_foreground_task`.

### T5 — Routine reminder fires at `start_time` (p040 T5, ~5 min wait)

**Status:** passed (2026-10-21, Pixel 11 Pro, Android 17, 1.4.4 (12)): re-run after [#357](https://github.com/mjarco/voice-agent/issues/357) (PR #360): exact alarm at 21:40 for an occurrence with `occurrence_id: null`, reminder shown, tap opened Agenda (owner). First run failed on 1.4.3 (11): no alarm

**Do:**
1. With the occurrence from S2 ahead, open the Agenda tab (this reconciles the schedule).
2. Lock the Pixel and wait for `start_time`.
3. Tap the notification.

**Why:** [p040 T5](p040-agenda-notifications.md#t5--routine-occurrence-reminder-fires-at-start_time-ios--android-time-of-day-dependent) on Android: exact alarms (`USE_EXACT_ALARM`) and the `ScheduledNotificationReceiver` added in #350.

**Expected:** the notification fires within ±60 s of `start_time`; title = the routine's name, body = `start_time` (HH:MM); the tap opens `/agenda`.

**On failure:**
- Nothing fires: `adb shell dumpsys alarm | grep -B2 -A6 voice_agent` should list an alarm for the time; if absent, the reconcile did not schedule it.
- Alarm listed but no notification: the receiver is missing from the merged manifest (see T4's `apkanalyzer` check, `grep ScheduledNotification`), or notifications are off for the app in Android settings.

### T6 — WorkManager agenda refresh registered (p040 T9, ~2 min)

**Status:** passed (2026-10-21, Pixel 11 Pro, Android 17, 1.4.3 (11)): job `#BackgroundWorker#` for `SystemJobService` present, network constraint, past runs at gaps of 2–5 h (standby bucket 20, working set).

**Do:**
1. Open the app once after install.
2. On laptop.lan: `~/Android/Sdk/platform-tools/adb shell dumpsys jobscheduler | grep -A12 "com.voiceagent.voice_agent.dev/androidx.work"`

**Why:** [p040 T9](p040-agenda-notifications.md#t9--workmanager-bg-task-registers-on-android-android-only-3-min) after the `workmanager` 0.10 upgrade in #349: `registerAgendaRefresh()` enqueues the periodic task.

**Expected:** one `JOB androidx.work.systemjobscheduler:…` entry for `com.voiceagent.voice_agent.dev/androidx.work.impl.background.systemjob.SystemJobService` (tag `#BackgroundWorker#`), with `Network type` set (the `NetworkType.connected` constraint). WorkManager hands JobScheduler one run at a time, so the 1 h period does not appear as such; the job's run history (`grep 10467/com.voiceagent` in the same dump) shows past runs. Android stretches the gaps by the app's standby bucket (`adb shell am get-standby-bucket com.voiceagent.voice_agent.dev`); gaps of a few hours are expected, not a failure.

**On failure:** `lib/app/background/register_agenda_refresh.dart` was not reached; look for `[agendaRefreshDispatcher]` lines and Dart exceptions at start-up.

---

## When this plan is done

- Must pass: T1, T2, T3, T4, T6. Together with T5 they are the epic's acceptance criteria 2–6.
- T5 should pass on the Pixel; a failure caused by an Android battery or alarm setting is recorded here as a device limitation, not a bug.
- Every status line names the date, the device (`Pixel 11 Pro, Android <version>`) and the build.

Once every must-pass case is `passed`, the owner assesses the epic's criteria 1–7.
