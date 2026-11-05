# Manual test: the arrival list

**Design:** [ADR-PLATFORM-010](../decisions/ADR-PLATFORM-010-geofences-of-places.md), [ADR-PLATFORM-009](../decisions/ADR-PLATFORM-009-native-location-pipeline.md), [ADR-NET-005](../decisions/ADR-NET-005-location-log-background-upload.md); workspace epic `2026-11-places/01-arrival-list` and its trigger contract `compilations/notification-triggers/reviewed/04-trigger-contract.md`; PR #395 (task 3).
**Overall status:** **pending**.
**Why now:** geofences, the "always" permission, boot, update, force stop and location turned off exist only on a device.
**When:** once, at the end of the epic, with the cases of tasks 4–6; nothing goes on the Pixel before then (owner's decision of 2026-11-05).
**Time budget:** ~45 min for task 3's cases (agent, dev flavor over USB adb), then real arrivals (owner, stable on production).
**What we are testing:** task 3: every place gets a geofence, registration survives everything the location log's subscription survives, and enter, dwell and exit become status rows of the log. Nothing is shown. Tasks 4–6 add their cases below.

## Status legend

See the canonical legend in [`p040-agenda-notifications.md`](p040-agenda-notifications.md#status-legend).

## Status summary

| # | Case | Status |
|---|---|---|
| S1 | Test personal-agent on `:8898` with places | pending |
| S2 | The dev build, debuggable, pointed at it | pending |
| S3 | Reading the queue and the geofence state | pending |
| T1 | After install the switch is off and nothing is written | pending |
| T2 | Turning it on asks for permissions and registers every place | pending |
| T3 | Rows follow "Alerty w sklepach" alone, with the log paused | pending |
| T4 | Without "always": `geofences_failed`, then registered once granted | pending |
| T5 | Adding, deleting and renaming a place | pending |
| T6 | Reboot, update and force stop each register again | pending |
| T7 | Location off, then on: degraded, then the retry job registers | pending |
| T8 | Turning it off removes the geofences, and then nothing is written | pending |
| T9 | Mock transitions: enter, dwell and exit rows | pending |
| T10 | A hands-free session runs alongside | pending |
| T11 | Real arrivals on stable, in PA's Location view | pending |

---

## Setup

### S1. Test personal-agent on `:8898` with places

**Status:** pending

**Do:** set up the test PA as `ws-device-check` describes (never `:8888`). Put three places in it with `PUT /api/v1/places/<uuid>`: one where the phone lies (home), two elsewhere.

### S2. The dev build, debuggable, pointed at it

**Status:** pending

**Do:**
1. `flutter build apk --flavor dev --debug --dart-define-from-file=$SP/env.mobile`, with the test PA's env file. A debug build, because `run-as` (S3) works only on a debuggable app.
2. `adb -s <usb serial> install -r build/app/outputs/flutter-apk/app-dev-debug.apk`, then `pm clear com.voiceagent.voice_agent.dev`.
3. Open Settings, read the URL, Test Connection. Open Miejsca: the three places load.
4. Settings shows 1.16.0.

Kotlin cannot post to an `http://` PA (ADR-PLATFORM-009, item 8), so on dev the rows stay in the phone's queue and are read there (S3), not in PA. "Ostatni błąd wysyłki" showing a cleartext error is expected.

### S3. Reading the queue and the geofence state

**Status:** pending

```bash
P=com.voiceagent.voice_agent.dev
for f in location_log.db location_log.db-wal; do adb -s <serial> exec-out run-as $P cat databases/$f > $SP/$f; done
sqlite3 $SP/location_log.db "SELECT seq, id, payload FROM location_queue ORDER BY seq"
adb -s <serial> exec-out run-as $P cat shared_prefs/geofences.xml
```

The screen (Settings → Dziennik lokalizacji) shows "obszary: N", "Zarejestrowane: <time>" and "W kolejce: N". Every new row's `id` is a UUIDv7: the 13th hex digit is `7`.

---

## Cases

### T1. After install the switch is off and nothing is written

**Status:** pending
**Do:**
1. After S2, open Dziennik lokalizacji.
2. `am force-stop`, open the app again, read the queue.

**Why:** ADR-PLATFORM-010 item 5: off by default, and nothing is written while it is off.
**Expected:** "Alerty w sklepach" off, "obszary: 0", no time; no `geofences_*` or `place.*` row in the queue; `geofences.xml` has no `registered_hash`.
**On failure:** `GeofenceConfig.alertsEnabled` default; `GeofenceRegistry.removeAll` writes `geofences_removed` only for reason `switch` or a past registration.

### T2. Turning it on asks for permissions and registers every place

**Status:** pending
**Do:**
1. With location permission not yet granted, turn "Alerty w sklepach" on.
2. Grant while-in-use, notifications, then "all the time" on the settings page; come back.
3. Read the screen and the queue.

**Why:** the switch is the consent and asks for background location and notifications (epic §3.6, owner's decision 3 of 2026-11-05); every place gets a geofence.
**Expected:** the three dialogs in that order; "obszary: 3" with a time; a `geofences_registered` row, detail `{"count":3,"reason":"switch"}` (or `"retry"` if "always" came only after the first try, see T4).
**On failure:** `_setAlertsEnabled` in `location_log_screen.dart`; `GeofenceRegistry.reconcile`; `geofences_failed` with its `code` says why (1004: permission; 1000: location off).

### T3. Rows follow "Alerty w sklepach" alone, with the log paused

**Status:** pending
**Do:**
1. Turn "Zbieraj lokalizację" off, leave the alerts on.
2. `am force-stop`, open the app, read the queue.

**Why:** owner's decision 2 of 2026-11-05: geofence rows follow this switch alone.
**Expected:** a new `geofences_registered` with `"reason":"app_start"`; no reading rows.
**On failure:** `LocationBridge` `reconcile` must call `GeofenceRegistry.reconcile` whatever the log's switch.

### T4. Without "always": `geofences_failed`, then registered once granted

**Status:** pending
**Do:**
1. `adb shell pm revoke com.voiceagent.voice_agent.dev android.permission.ACCESS_BACKGROUND_LOCATION` (it kills the process).
2. Open the app, read the screen and the queue.
3. Wait 3 minutes and read the queue again.
4. Tap "Nadaj", grant "all the time", come back to the app; read the screen and the queue.

**Why:** ADR-PLATFORM-010 item 4: a missing permission is not retried; a return to the app with the permission changed registers.
**Expected:** after 2: `geofences_failed` `{"code":1004,"reason":"app_start",…}`, "obszary: 0", "Nadaj" shown. After 3: no new row (no retry job for 1004). After 4: `geofences_registered` with `"reason":"permission_changed"` within seconds, and "obszary: 3".
**On failure:** the code in the row; `locationLogResumeProvider` (did Dart call `appResumed`?) and `GeofenceRegistry.permissionMayHaveChanged` (`last_permission` in `geofences.xml`).

### T5. Adding, deleting and renaming a place

**Status:** pending
**Do:**
1. Name a fourth place in Miejsca.
2. Delete it.
3. Rename one of the others.

**Why:** the set's hash: a change of places registers again, a new name alone does not.
**Expected:** 1: `geofences_registered` `{"count":4,"reason":"places_changed"}`, "obszary: 4". 2: the same with 3. 3: no new row; `geofences.xml` holds the new name.
**On failure:** `placeGeofencesSyncProvider` (did Dart send?) and `PlaceGeofencesBridge` (hash compare).

### T6. Reboot, update and force stop each register again

**Status:** pending
**Do:**
1. `adb reboot`; unlock; wait 2 minutes without opening the app; read the queue.
2. `adb install -r` the same APK; read the queue.
3. `am force-stop`, confirm no pid, open the app; read the queue.

**Why:** ADR-PLATFORM-010 item 4: geofences are lost at each of these.
**Expected:** a `geofences_registered` row for each, with `"reason"` `reboot`, `app_updated`, and `app_start` (and `restart_after_stop` if the system sends the boot broadcast after the stop); "obszary: 3" and the time moves each time.
**On failure:** `LocationBootReceiver` (one receiver for both pipelines).

### T7. Location off, then on: degraded, then the retry job registers

**Status:** pending
**Do:**
1. `adb shell cmd location set-location-enabled false`; wait 2 minutes; read the queue.
2. `adb shell cmd location set-location-enabled true`; wait up to 10 minutes, reading the queue each minute.

**Why:** 03, S5, and ADR-PLATFORM-010 item 4: the system drops every geofence when location goes off.
**Expected:** 1: `app.location_degraded` `{"cause":"geofence_not_available"}`, "obszary: 0". 2: `geofences_registered` `"reason":"retry"`, then `app.location_restored`. A failed try in between leaves "obszary: 0" and the next one removes every geofence of the app before adding (no stale geofence). Play services may not send the event at once; if no degraded row comes, record that and whether the next app start registers.
**On failure:** `GeofenceReceiver` error branch; the job's backoff (30 s, doubling).

### T8. Turning it off removes the geofences, and then nothing is written

**Status:** pending
**Do:**
1. Turn "Alerty w sklepach" off.
2. `am force-stop`, open the app; read the queue.

**Why:** the switch off is the end of consent.
**Expected:** 1: `geofences_removed` `{"reason":"switch"}`, "obszary: 0". 2: no new geofence row.
**On failure:** `GeofenceRegistry.removeAll`.

### T9. Mock transitions: enter, dwell and exit rows

**Status:** pending
**Do:**
1. Alerts on. `adb shell appops set com.android.shell android:mock_location allow`.
2. Put the test provider at a place far from home: `adb shell cmd location providers add-test-provider gps` and `adb shell cmd location providers set-test-provider-location gps --location <lat>,<lon>`; repeat every 10 s for 2 minutes.
3. Move it 1 km away; repeat for 2 minutes.
4. Remove the test provider; read the queue.

**Why:** S1.1 of the epic: each enter, dwell and exit becomes a status row with the phone's time and 03's event type.
**Expected:** `place.entered` with `"transition":"enter"`, then `"dwell"` about 60 s later, then `place.left` with `"exit"`; detail has `place`, `name`, `radius_m`, `fix_at`, `accuracy_m`; `recorded_at` after `fix_at`. If Play services' geofencing ignores the test provider, record "skipped (mock ignored)": T11 covers it.
**On failure:** `GeofenceReceiver.record`; whether the fused provider took the mock (`adb shell dumpsys location`).

### T10. A hands-free session runs alongside

**Status:** pending
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

---

## When this plan is done

Task 3: T1–T8 and T10 are must-pass. T9 is conditional on Play services taking a test provider; if it does not, T11 alone proves the rows. T11 is read with the epic's ten visits. The plan runs at the epic's end, so it is not a gate of task 3's merge. Tasks 4–6 add their cases and their own must-pass list.
