# Manual test: the arrival list

**Design:** [ADR-PLATFORM-010](../decisions/ADR-PLATFORM-010-geofences-of-places.md), [ADR-NET-007](../decisions/ADR-NET-007-armed-triggers-pulled-in-background.md), [ADR-NOTIF-003](../decisions/ADR-NOTIF-003-arrival-alerts-posted-natively.md), [ADR-PLATFORM-009](../decisions/ADR-PLATFORM-009-native-location-pipeline.md), [ADR-NET-005](../decisions/ADR-NET-005-location-log-background-upload.md); workspace epic `2026-11-places/01-arrival-list` and its trigger contract `compilations/notification-triggers/reviewed/04-trigger-contract.md`; PR #395 (task 3), PR #396 (task 4), PR #397 (task 5), PR #399 (task 6); [ADR-PLATFORM-008](../decisions/ADR-PLATFORM-008-two-channel-deep-link.md) for the tap.
**Overall status:** **in-progress**: run by the agent on 2026-11-06 (the run's report, workspace docs `requirements/roadmaps/2026-11-places/epics/01-arrival-list/drafts/06-device-run-report.md`); T4, T6 and T17 failed (defects D1–D3, to be fixed after stable 1.19.0 by the owner's decision); T10, T11 and T23 step 2 wait for the owner on stable; T13 skipped.
**Why now:** geofences, the "always" permission, boot, update, force stop and location turned off exist only on a device.
**When:** once, at the end of the epic, with the cases of tasks 4–6; nothing goes on the Pixel before then (owner's decision of 2026-11-05).
**Time budget:** ~45 min for task 3's cases (agent, dev flavor over USB adb), then real arrivals (owner, stable on production).
**What we are testing:** task 3: registration survives everything the location log's subscription survives, and enter, dwell and exit become status rows of the log. Task 4: the phone pulls the armed triggers, each trigger gets a geofence (a store with nothing to buy gets none), and an enter or dwell row says whether the trigger would fire. Task 5: the firing transition posts a notification at most once per visit, and its reports come back as rows (`trigger.fired`, `.shown`, `.ignored`). Task 6: a tap opens Shopping with every store type of the place, cold and warm, and writes `trigger.tapped` once.

## Status legend

See the canonical legend in [`p040-agenda-notifications.md`](p040-agenda-notifications.md#status-legend).

## Status summary

| # | Case | Status |
|---|---|---|
| S1 | Test personal-agent on `:8898` with places | done |
| S2 | The dev build, debuggable, pointed at it | done |
| S3 | Reading the queue and the geofence state | done |
| T1 | After install the switch is off and nothing is written | passed |
| T2 | Turning it on asks for permissions and registers every place | passed |
| T3 | Rows follow "Alerty w sklepach" alone, with the log paused | passed |
| T4 | Without "always": `geofences_failed`, then registered once granted | failed |
| T5 | Adding, deleting and renaming a place | passed |
| T6 | Reboot, update and force stop each register again | failed |
| T7 | Location off, then on: degraded, then the retry job registers | passed with a deviation |
| T8 | Turning it off removes the geofences, and then nothing is written | passed |
| T9 | Mock transitions: enter, dwell and exit rows | passed |
| T10 | A hands-free session runs alongside | pending |
| T11 | Real arrivals on stable, in PA's Location view | pending |
| T12 | The pull, and "unchanged" on the next start | passed |
| T13 | A change in the list reaches the phone | skipped |
| T14 | Turning it off clears the set and stops the hourly pull | passed |
| T15 | Offline: one `triggers_failed`, the set stands | passed |
| T16 | One notification per visit, with its reports | passed |
| T17 | No second one after a restart mid-visit | failed |
| T18 | A new list mid-visit gives none | passed |
| T19 | A swipe writes `trigger.ignored` | passed |
| T20 | Notifications off: `"shown":false` | passed |
| T21 | An expired trigger stays silent | passed |
| T22 | A tap with the app closed opens the place's list | passed |
| T23 | A tap with the app running, and over a hands-free session | in-progress |
| T24 | Recents and a second tap do not count again | passed |
| T25 | A tap after the switch is off | passed |

---

## Setup

### S1. Test personal-agent on `:8898` with places

**Status:** done (2026-11-06)

If `:8898` is taken, any free port does; give the test PA its own `PA_MCP_SOCKET`, or it takes the shared default socket of another dev PA. T12 and T14 need the PA's requests: run it behind a small logging proxy (method, path, `If-None-Match`, status).

**Do:** set up the test PA as `ws-device-check` describes (never `:8888`). Put three places in it with `PUT /api/v1/places/<uuid>`: one where the phone lies (home), two elsewhere, each with a store type (e.g. `diy`, `grocery`, `garden`). Put one shopping item under each of the first two types, none under the third. `GET /api/v1/triggers` then holds two triggers: geofences come from triggers since task 4, not from places.

### S2. The dev build, debuggable, pointed at it

**Status:** done (2026-11-06)

**Do:**
1. `flutter build apk --flavor dev --debug --dart-define-from-file=$SP/env.mobile`, with the test PA's env file. A debug build, because `run-as` (S3) works only on a debuggable app.
2. `adb -s <usb serial> install -r build/app/outputs/flutter-apk/app-dev-debug.apk`, then `pm clear com.voiceagent.voice_agent.dev`.
3. Open Settings, read the URL, Test Connection. Open Miejsca: the three places load.
4. Settings shows the version under test (1.19.0 at the 2026-11-06 run).

A release build's Kotlin cannot reach an `http://` PA (ADR-PLATFORM-009, item 8). Debug builds allow cleartext (`android/app/src/debug/AndroidManifest.xml`), so the trigger pull and the rows reach the test PA; read them there (`GET /api/v1/location/entries`) or in the queue (S3).

### S3. Reading the queue and the geofence state

**Status:** done (2026-11-06)

```bash
P=com.voiceagent.voice_agent.dev
for f in location_log.db location_log.db-wal; do adb -s <serial> exec-out run-as $P cat databases/$f > $SP/$f; done
sqlite3 $SP/location_log.db "SELECT seq, id, payload FROM location_queue ORDER BY seq"
adb -s <serial> exec-out run-as $P cat shared_prefs/geofences.xml
```

The screen (Settings → Dziennik lokalizacji) shows "wyzwalacze: N, sprawdzone <time>", "obszary: N", "Zarejestrowane: <time>" and "W kolejce: N". `geofences.xml` holds the set (`trigger_set`) and its `triggers_etag`. Every new row's `id` is a UUIDv7: the 13th hex digit is `7`.

---

## Cases

### T1. After install the switch is off and nothing is written

**Status:** passed (2026-11-06, Pixel 11 Pro, Android 17, dev 1.19.0+34, test PA)
**Do:**
1. After S2, open Dziennik lokalizacji.
2. `am force-stop`, open the app again, read the queue.

**Why:** ADR-PLATFORM-010 item 5: off by default, and nothing is written while it is off.
**Expected:** "Alerty w sklepach" off, "obszary: 0", no time; no `geofences_*` or `place.*` row in the queue; `geofences.xml` has no `registered_hash`.
**On failure:** `GeofenceConfig.alertsEnabled` default; `GeofenceRegistry.removeAll` writes `geofences_removed` only for reason `switch` or a past registration.

### T2. Turning it on asks for permissions and registers a geofence per trigger

**Status:** passed (2026-11-06, Pixel 11 Pro, Android 17, dev 1.19.0+34, test PA)
**Do:**
1. With location permission not yet granted, turn "Alerty w sklepach" on.
2. Grant while-in-use, notifications, then "all the time" on the settings page; come back.
3. Read the screen and the queue.

**Why:** the switch is the consent and asks for background location and notifications (epic §3.6, owner's decision 3 of 2026-11-05); each armed trigger gets a geofence (ADR-NET-007, item 5).
**Expected:** the three dialogs in that order; `geofences_registered` `{"count":0,"reason":"switch"}` (the set is empty until the pull), then `triggers_pulled` `{"count":2,"changed":true,"reason":"switch"}` and `geofences_registered` `{"count":2,"added":2,"reason":"triggers_changed"}`; "wyzwalacze: 2", "obszary: 2" with a time. The third place, with nothing to buy, has no geofence. If "always" came only after the first try, see T4.
**On failure:** `_setAlertsEnabled` in `location_log_screen.dart`; `GeofenceRegistry.reconcile`; `geofences_failed` with its `code` says why (1004: permission; 1000: location off).

### T3. Rows follow "Alerty w sklepach" alone, with the log paused

**Status:** passed (2026-11-06, Pixel 11 Pro, Android 17, dev 1.19.0+34, test PA); the row's reason was `restart_after_stop`, the boot broadcast after the stop
**Do:**
1. Turn "Zbieraj lokalizację" off, leave the alerts on.
2. `am force-stop`, open the app, read the queue.

**Why:** owner's decision 2 of 2026-11-05: geofence rows follow this switch alone.
**Expected:** a new `geofences_registered` with `"reason":"app_start"`; no reading rows.
**On failure:** `LocationBridge` `reconcile` must call `GeofenceRegistry.reconcile` whatever the log's switch.

### T4. Without "always": `geofences_failed`, then registered once granted

**Status:** failed (2026-11-06, Pixel 11 Pro, Android 17, dev 1.19.0+34, test PA): step 2 wrote no `geofences_failed` and kept "obszary: 2" (D3 in the run's report, workspace docs `requirements/roadmaps/2026-11-places/epics/01-arrival-list/drafts/06-device-run-report.md`); step 4 passed
**Do:**
1. `adb shell pm revoke com.voiceagent.voice_agent.dev android.permission.ACCESS_BACKGROUND_LOCATION` (it kills the process).
2. Open the app, read the screen and the queue.
3. Wait 3 minutes and read the queue again.
4. Tap "Nadaj", grant "all the time", come back to the app; read the screen and the queue.

**Why:** ADR-PLATFORM-010 item 4: a missing permission is not retried; a return to the app with the permission changed registers.
**Expected:** after 2: `geofences_failed` `{"code":1004,"reason":"app_start",…}`, "obszary: 0", "Nadaj" shown. After 3: no new row (no retry job for 1004). After 4: `geofences_registered` with `"reason":"permission_changed"` within seconds, and "obszary" back to the number of triggers. "Nadaj" opens App info in system settings; a driver that does not tap there grants with `pm grant`, which takes the same return path.
**On failure:** the code in the row; `locationLogResumeProvider` (did Dart call `appResumed`?) and `GeofenceRegistry.permissionMayHaveChanged` (`last_permission` in `geofences.xml`).

### T5. Adding, deleting and renaming a place

**Status:** passed (2026-11-06, Pixel 11 Pro, Android 17, dev 1.19.0+34, test PA); places changed through the test PA's API
**Do:**
1. Name a fourth place in Miejsca, with the first place's store type; bring the app back to front after 5 minutes (or restart it).
2. Delete it; the same.
3. Rename one of the others; the same.

**Why:** since task 4 places reach the geofences only through personal-agent's triggers; the geofence's key leaves out the text (ADR-NET-007, item 5).
**Expected:** 1: `triggers_pulled` `{"count":3,…}`, `geofences_registered` `{"count":3,"added":1,"reason":"triggers_changed"}`. 2: count 2, added 0. 3: `triggers_pulled` (the title changed) and no `geofences_registered` row (nothing to add or remove).
**On failure:** `TriggerPuller` (was the return within 5 minutes of the last try?), `GeofenceRegistry.adoptAndWait` and `Triggers.geofenceKey`.

### T6. Reboot, update and force stop each register again

**Status:** failed (2026-11-06, Pixel 11 Pro, Android 17, dev 1.19.0+34, test PA): steps 1–3 passed; step 4 re-registered everything, `restart_after_stop` after a plain kill (D2)
**Do:**
1. `adb reboot`; unlock; wait 2 minutes without opening the app; read the queue.
2. `adb install -r` the same APK; read the queue.
3. `am force-stop`, confirm no pid, open the app; read the queue.
4. Close the app from recents (no force stop), open it again; read the queue.

**Why:** ADR-PLATFORM-010 item 4: geofences are lost at each of these. Step 4 is item 3: an app start that finds the registration standing adds nothing, so a visit in progress keeps its state.
**Expected:** a `geofences_registered` row for each, with `"reason"` `reboot`, `app_updated`, and `app_start` (and `restart_after_stop` if the system sends the boot broadcast after the stop); "obszary" equal to the number of triggers and the time moves each time. After step 4 no new row, and the time stays.
**On failure:** `LocationBootReceiver` (one receiver for both pipelines).

### T7. Location off, then on: degraded, then the retry job registers

**Status:** passed with a deviation (2026-11-06, Pixel 11 Pro, Android 17): location off for 2 and 5 minutes sent no `GEOFENCE_NOT_AVAILABLE` and no degraded row; the geofences survived (T9 entered right after)
**Do:**
1. `adb shell cmd location set-location-enabled false`; wait 2 minutes; read the queue.
2. `adb shell cmd location set-location-enabled true`; wait up to 10 minutes, reading the queue each minute.

**Why:** 03, S5, and ADR-PLATFORM-010 item 4: the system drops every geofence when location goes off.
**Expected:** 1: `app.location_degraded` `{"cause":"geofence_not_available"}`, "obszary: 0". 2: `geofences_registered` `"reason":"retry"`, then `app.location_restored`. A failed try in between leaves "obszary: 0" and the next one removes every geofence of the app before adding (no stale geofence). Play services may not send the event at once; if no degraded row comes, record that and whether the next app start registers.
**On failure:** `GeofenceReceiver` error branch; the job's backoff (30 s, doubling).

### T8. Turning it off removes the geofences, and then nothing is written

**Status:** passed (2026-11-06, Pixel 11 Pro, Android 17, dev 1.19.0+34, test PA)
**Do:**
1. Turn "Alerty w sklepach" off.
2. `am force-stop`, open the app; read the queue.

**Why:** the switch off is the end of consent.
**Expected:** 1: `geofences_removed` `{"reason":"switch"}`, "obszary: 0". 2: no new geofence row.
**On failure:** `GeofenceRegistry.removeAll`.

### T9. Mock transitions: enter, dwell and exit rows

**Status:** passed (2026-11-06, Pixel 11 Pro, Android 17, dev 1.19.0+34, test PA)
**Do:**
1. Alerts on. `adb shell appops set com.android.shell android:mock_location allow`.
2. Put the test provider at a place far from home: `adb shell cmd location providers add-test-provider gps` and `adb shell cmd location providers set-test-provider-location gps --location <lat>,<lon>`; repeat every 10 s for 2 minutes.
3. Move it 1 km away; repeat for 2 minutes.
4. Remove the test provider; read the queue.

**Why:** S1.1 of the epic: each enter, dwell and exit becomes a status row with the phone's time and 03's event type.
**Expected:** `place.entered` with `"transition":"enter"`, then `"dwell"` about 60 s later, followed by `trigger.fired` and `trigger.shown` (T16), then `place.left` with `"exit"`; detail has `place` (`place:<id>`), `trigger`, `v`, `name` (the trigger's title), `radius_m`, `fix_at`, `accuracy_m`; `recorded_at` after `fix_at`. Use a place with something to buy: the third has no geofence. If Play services' geofencing ignores the test provider, record "skipped (mock ignored)": T11 covers it.
**On failure:** `GeofenceReceiver.record`; whether the fused provider took the mock (`adb shell dumpsys location`).

### T10. A hands-free session runs alongside

**Status:** pending (owner, on stable during T11: the dev build has no Groq key)
**Do:** with alerts on, start a hands-free session, toggle alerts off and on, end the session.

**Why:** registration waits on Play services on its own thread (ADR-PLATFORM-010 item 4); the pipeline's thread and the session must never wait behind it.
**Expected:** the session listens and ends normally; T2's row appears; readings keep arriving while it registers.
**On failure:** something waiting on Play services on `LocationPipeline.executor` instead of `GeofenceRegistry.executor` (each Play services call waits at most 15 s there).

### T11. Real arrivals on stable, in PA's Location view

**Status:** pending (owner)
**Do:** at the epic's end, install the stable build, turn the alerts on, live your ordinary visits.

**Why:** only real visits show the geofence delay, which tunes the trigger's `dwell_s` and radius in PA.
**Expected:** `place.entered` and `place.left` rows at home and in stores in the Location view; `fix_at` against `recorded_at` and the log's readings give the delay; read with the epic's ten visits.
**On failure:** `geofences_failed` and `app.location_degraded` rows in the same view.

### T12. The pull, and "unchanged" on the next start

**Status:** passed (2026-11-06, Pixel 11 Pro, Android 17, dev 1.19.0+34, test PA)
**Do:**
1. Alerts on, after T2. Note "sprawdzone <time>".
2. Force stop the app (`am force-stop`, confirm no pid), wait a minute, open it.
3. Read the screen, the queue, and the test PA's log of requests.

**Why:** the set's version is its `ETag`; an unchanged set is a `304` (04, section 2; ADR-NET-007, item 2).
**Expected:** PA logs `GET /api/v1/triggers` with `If-None-Match` and answers 304; "sprawdzone" moves to the new time; no new `triggers_pulled` row.
**On failure:** `triggers_etag` in `geofences.xml`; PA's ETag match (ADR-API-114, weak).

### T13. A change in the list reaches the phone

**Status:** skipped (2026-11-06, owner's decision: over an hour of waiting)
**Do:**
1. Add an item under the third place's store type in the test PA.
2. Leave the phone alone, screen off, for up to 75 minutes (the hourly job), then read the queue.
3. Tick the item off and repeat.

**Why:** criterion 1 of the epic: a change in places or the list re-arms within about an hour, with the app closed (ADR-NET-007, item 1).
**Expected:** 2: `triggers_pulled` `{"count":3,"changed":true,"reason":"hourly"}` and `geofences_registered` with `"added":1`. 3: count 2 and the third geofence removed.
**On failure:** `adb shell dumpsys jobscheduler | grep -A5 voice_agent.dev` (the job and its network constraint); Doze can delay it: note how long.

### T14. Turning it off clears the set and stops the hourly pull

**Status:** passed (2026-11-06, Pixel 11 Pro, Android 17, dev 1.19.0+34, test PA), except the hour without a pull (skipped with T13)
**Do:** turn "Alerty w sklepach" off; read `geofences.xml`, the job list and, after an hour, PA's log.

**Why:** the switch is the consent; with it off nothing is pulled (ADR-NET-007, items 1 and 3).
**Expected:** `geofences.xml` has no `trigger_set` and no `triggers_etag`; the job is gone from `dumpsys jobscheduler`; PA logs no `GET /triggers` from the phone. Turning it on again pulls at once (T2's rows).
**On failure:** `LocationBridge` `setAlertsEnabled` and `TriggerPuller.cancel`.

### T15. Offline: one `triggers_failed`, the set stands

**Status:** passed (2026-11-06, Pixel 11 Pro, Android 17, dev 1.19.0+34, test PA)
**Do:** under `trap '… airplane-mode disable' EXIT`, airplane mode on; force stop and open the app twice, 6 minutes apart; airplane mode off; open the app after 5 minutes.

**Why:** a failed pull keeps the set last pulled, and the phone fires from it offline (criterion 5; ADR-NET-007, item 2).
**Expected:** one `triggers_failed` row for both tries; "wyzwalacze: 2" and "obszary: 2" stay; after the network returns, `triggers_pulled` `{"changed":false,…}`.
**On failure:** `triggers_failing` in `geofences.xml`.

### T16. One notification per visit, with its reports

**Status:** passed (2026-11-06, Pixel 11 Pro, Android 17, dev 1.19.0+34, test PA)
**Do:**
1. As T9, steps 1–2, at a place with something to buy; watch the screen.
2. Stay 3 more minutes; then move away as T9, step 3; read the queue.

**Why:** task 5 of the epic and 04, sections 5 and 7: the trigger's transition fires once per visit, and each step is a row naming its cause (ADR-NOTIF-003).
**Expected:** about 60 s in, one heads-up notification with sound in the channel "Alerty w sklepach", the trigger's title and body as PA wrote them. The queue: `place.entered` (`dwell`) with id A; `trigger.fired` `{"trigger":…,"v":…,"surface":"phone","caused_by":[A],"shown":true}` with id B; `trigger.shown` `{"caused_by":[B]}`. No second notification and no second `trigger.fired` before the exit. `geofences.xml` holds `visits` with the trigger's id and `"fired":true`, gone after the exit. A tap opens the app's start screen and writes no row (task 6).
**On failure:** `Visits.step`; `ArrivalNotifier.blocked`; the channel in Settings → Apps → Notifications.

### T17. No second one after a restart mid-visit

**Status:** failed (2026-11-06, Pixel 11 Pro, Android 17, dev 1.19.0+34, test PA): after a force stop mid-visit a second alert ~65 s later, twice (D1); the reboot part is inconclusive, since a reboot drops the test provider
**Do:** in T16's visit, after the notification: `am force-stop`, confirm no pid, open the app; then reboot the phone; keep the mock location 3 more minutes each time.

**Why:** the visit state is on disk, so a restart of the app or the phone does not fire twice (04, section 5).
**Expected:** no new notification and no `trigger.fired`. After the force stop and after the reboot the geofence is added afresh, so its visit leaves `visits` in `geofences.xml`, and no `place.entered` follows while you stay (initial trigger 0); the exit still writes `place.left`. This case is what makes forgetting a re-added geofence's visit safe (ADR-NOTIF-003, item 4).
**On failure:** a `place.entered` right after the registration means Play services reported a geofence added while inside: forgetting the visit at `GeofenceRegistry.forgetVisits` then fires twice.

### T18. A new list mid-visit gives none

**Status:** passed (2026-11-06, Pixel 11 Pro, Android 17, dev 1.19.0+34, test PA)
**Do:** in a visit that has fired, add an item to that store's list in the test PA; return to the app after 5 minutes (a pull) and stay 3 more minutes.

**Why:** once per visit is keyed by the trigger's id, not its version (04, section 5).
**Expected:** `triggers_pulled` `{"changed":true}`, no `geofences_registered` with `"added"` > 0 for that trigger (its key is unchanged), no new `trigger.fired`.
**On failure:** `Triggers.geofenceKey` (an added geofence resets its enter); `Visits.step`.

A withdrawn trigger's visit is forgotten with its geofence: tick off the last item while inside, leave, add an item, come back within 6 h, and the dwell fires (`GeofenceRegistry.forgetVisits`). Run it with T18 when time allows.

### T19. A swipe writes `trigger.ignored`

**Status:** passed (2026-11-06, Pixel 11 Pro, Android 17, dev 1.19.0+34, test PA)
**Do:** in a new visit (exit, then enter again), swipe the notification away; read the queue.

**Why:** 04, section 7: you swiped it away, reported against the shown row.
**Expected:** `trigger.ignored` `{"trigger":…,"v":…,"caused_by":[<the trigger.shown id>]}`. A tap instead of a swipe writes nothing.
**On failure:** `ArrivalDismissReceiver` in the manifest; the delete intent's extras.

### T20. Notifications off: `"shown":false`

**Status:** passed (2026-11-06, Pixel 11 Pro, Android 17, dev 1.19.0+34, test PA)
**Do:**
1. Turn off the channel "Alerty w sklepach" in system settings (it exists once the switch is on); make a new visit.
2. Turn the channel on; `adb shell pm revoke <package> android.permission.POST_NOTIFICATIONS`; make a new visit.
3. Grant it again.

**Why:** owner's decision with Gate 2 of task 5 (point 4): the log shows that the alert would have come, and why it did not.
**Expected:** 1: `trigger.fired` with `"shown":false,"why":"channel_off"`, no `trigger.shown`, no notification. 2: the same with `"why":"notifications_off"`. A second dwell in the same visit writes no second `trigger.fired`.
**On failure:** `ArrivalNotifier.blocked`.

### T21. An expired trigger stays silent

**Status:** passed (2026-11-06, Pixel 11 Pro, Android 17, dev 1.19.0+34, test PA), with the stored set's `expires_at` moved to yesterday on the phone
**Do:** with the phone's clock moved past the trigger's `expires_at` (or a test PA that compiled it 3 days ago), make a visit.

**Why:** expired triggers never fire, by the phone's clock (04, section 3).
**Expected:** `place.entered` with `"expired":true`, no `trigger.fired`, no notification.
**On failure:** `Triggers.expired`; the stored set's `expires_at`.

### T22. A tap with the app closed opens the place's list

**Status:** passed (2026-11-06, Pixel 11 Pro, Android 17, dev 1.19.0+34, test PA), by step 4 (step 2 cannot work, see Do)
**Do:**
1. Make a visit as T16 at a place with two store types (in the test PA, e.g. `diy` and `garden`, an item under each).
2. ~~Before the alert comes, `am force-stop` the app~~: a force stop cancels the geofences' intent, so no alert would come. Use step 4 for the cold path.
3. Tap the alert; read the screen and the queue.
4. A new visit; this time leave the app in Recents and kill only its process (`adb shell am kill <package>`, confirm no pid), then tap the alert. Android recreates the activity and delivers the tap through `onNewIntent`.

**Why:** 04, section 6 (the route), amended so that `open` names every store type of the place; ADR-PLATFORM-008's cold path; `trigger.tapped` of 04, section 7.
**Expected:** the app starts on Shopping, To buy, with both type chips selected and "All" not; both items show, nothing under other types. The queue: `trigger.tapped` `{"trigger":…,"v":…,"caused_by":[<the trigger.shown id>]}`. The alert is gone from the shade. Step 4 gives the same, with one `trigger.tapped`.
**On failure:** `ArrivalTapBridge.accept` (the intent's action and extras); `ArrivalTapChannel.takeInitialRoute` and `arrivalRoute`; `last_shown` in `geofences.xml`.

### T23. A tap with the app running, and over a hands-free session

**Status:** in-progress: steps 1 and 3 passed (2026-11-06, Pixel 11 Pro, Android 17, dev 1.19.0+34, test PA); step 2 pending (owner, on stable during T11)
**Do:**
1. A new visit, the app open on Record. Tap the alert.
2. A new visit with a hands-free session listening. Tap the alert, then return to Record.
3. On a later visit, after changing the chips by hand (e.g. "All"), tap the alert again.

**Why:** ADR-PLATFORM-008's warm path: `onNewIntent` reaches the running app (singleTask), and `go` keeps the shell.
**Expected:** 1: Shopping opens with the place's chips; `trigger.tapped` once. 2: the same, and the session is still listening when you return to Record. 3: the place's chips are selected again (each tap is a new navigation, `DeepLinkTap`).
**On failure:** `MainActivity.onNewIntent`; `App`'s listener on `notificationTapStreamProvider`; `ShoppingScreen.didUpdateWidget` when Shopping was already open.

### T24. Recents and a second tap do not count again

**Status:** passed (2026-11-06, Pixel 11 Pro, Android 17, dev 1.19.0+34, test PA)
**Do:** after T22, leave the app with Back, open it again from Recents; then fire `adb shell am start -n <package>/.MainActivity -a com.voiceagent.voice_agent.ARRIVAL_TAPPED --es trigger <id> --es v <v> --es shown <the same shown id> --es open /settings --activity-clear-task` (without `--activity-clear-task` the running task is only brought to front and the intent is not delivered).

**Why:** one tap counts once: a redelivered or repeated intent writes no row, and a route a trigger may not open opens the start screen (04, section 6).
**Expected:** Recents opens the app as it was, with no new `trigger.tapped`. The `am start` writes no row and opens the start screen (Record), not `/settings` (04, section 6: anything else opens the start screen).
**On failure:** `FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY` in `ArrivalTapBridge.accept`; `Visits.takeShown`; `arrivalRoute`.

### T25. A tap after the switch is off

**Status:** passed (2026-11-06, Pixel 11 Pro, Android 17, dev 1.19.0+34, test PA)
**Do:** with an alert in the shade, turn "Alerty w sklepach" off; tap the alert.

**Why:** owner's decision with Gate 2 of task 6 (point 4): the list still opens; with the switch off nothing is written.
**Expected:** Shopping opens with the place's chips; no `trigger.tapped` row.
**On failure:** `ArrivalNotifier.tapped` (its switch check).

A rejected trigger (`trigger.rejected`) cannot be made by personal-agent today, which compiles only what goal 2 builds; the JVM tests in `android/app/src/test/` cover it.

---

## When this plan is done

Task 3: T1–T8 and T10 are must-pass. T9 is conditional on Play services taking a test provider; if it does not, T11 alone proves the rows. T11 is read with the epic's ten visits. The plan runs at the epic's end, so it is not a gate of task 3's merge. Task 4: T12, T14 and T15 are must-pass, with T2, T5 and T9 as they read since task 4; T13 is must-pass with its delay noted, since Doze may hold the job. Task 5: T16, T17, T19, T20 and T21 are must-pass, conditional on the mock location as T9 is (T11's real visits then prove T16 and T19); T18 is must-pass. Task 6: T22–T25 are must-pass, T22 and T23 with T16's visit (or a real one, T11).

For the whole epic: the plan is done when every must-pass case above is `passed`, run once on the Pixel with the one stable build of the epic's end (agent: dev flavor on a test PA for what it can, `ws-device-check`; owner: real arrivals, T11). Until then the epic's work is "device verification pending".
