# Manual test plan: sampling by motion

Design: [ADR-PLATFORM-014](../decisions/ADR-PLATFORM-014-sampling-by-motion.md); workspace off-roadmap task `2026-11-11-motion-sampling`.

**Overall status:** pending

**Why now:** the mode switches the location log by activity transitions of Play services and starts
a foreground service from the background; neither can be checked off the device.

**Time budget:** setup 10 minutes; T1–T3 at the desk 10 minutes; T4–T6 need a walk and a drive
(ordinary trips, read afterwards from the log).

**What we are testing:** the permission flow, the registration, the switch to frequent readings on a
start of motion, the switch back after `still`, the fallback, and the state after a reboot.

Status legend: as in [`p040-agenda-notifications.md`](p040-agenda-notifications.md).

## Status summary

| Case | What | Status |
|---|---|---|
| T1 | Choosing "Według ruchu" asks for physical activity | pending |
| T2 | A refused permission keeps background readings and offers "Nadaj" | pending |
| T3 | The registration is written and renewed at app start | pending |
| T4 | A walk switches to readings every 30 s, with the notification | pending |
| T5 | A drive switches to 10 s; a stop at lights does not switch back | pending |
| T6 | Standing 3 minutes switches back to the background | pending |
| T7 | After a reboot the mode starts in the background and registers again | pending |
| T8 | A stop the API missed ends the frequent readings after 10 minutes | pending |

## Setup

### S1. The build

**Status:** pending

Stable 1.30.0+50 on the Pixel (`make install-android`). The location log on, "Alerty w sklepach"
as they were. Note: installing before 2026-11-18 changes what field check FC-17 measures.

### S2. Reading the log

**Status:** pending

The rows reach personal-agent; read them there, or on the phone with `adb shell run-as` on the
location store. The rows to look for: `activity`, `subscribed` (detail starting `motion, `),
`motion_settled`, `motion_permission`, `motion_subscribe_failed`, and readings with
`requested_mode` and `requested_interval_s`.

## Test cases

### T1. Choosing "Według ruchu" asks for physical activity

**Status:** pending

**Do:**
1. Settings → Dziennik lokalizacji → "Według ruchu".
2. Allow "Physical activity".

**Why:** ADR-PLATFORM-014 item 1.

**Expected:** the system dialog for physical activity; then the line "Ruch: jeszcze nie rozpoznany",
"Odczyty w tle"; rows `motion_permission granted` and `subscribed` with `motion, background, mode changed`.

**On failure:** no dialog: the manifest's `ACTIVITY_RECOGNITION` or `Permission.activityRecognition`;
no rows: `LocationBridge.setMode`, `LocationPipeline.reconcile`.

### T2. A refused permission keeps background readings

**Status:** pending

**Do:**
1. In system settings revoke "Physical activity" of the app; return to the screen.
2. Tap "Nadaj".

**Why:** item 1 (without it the mode keeps background readings).

**Expected:** "Brak uprawnienia: aktywność fizyczna" with "Nadaj"; readings still come every few
minutes with `requested_mode` `background`; a `motion_permission denied` row at the next reconcile;
"Nadaj" shows the dialog or the app's settings page.

**On failure:** `MotionTransitions.permissionGranted`, `recordChanges`.

### T3. The registration is written and renewed

**Status:** pending

**Do:**
1. Force-stop the app, open it again.
2. `adb shell dumpsys activity_recognition` (or Play services' `dumpsys` of its activity recognition), if it lists the app.

**Why:** item 2.

**Expected:** a `subscribed` row `motion, background, app_start`; no `motion_subscribe_failed`.

**On failure:** the `motion_subscribe_failed` detail; Play services' version.

### T4. A walk switches to 30 s

**Status:** pending

**Do:** walk outside for 5 minutes with the phone in a pocket.

**Why:** item 3.

**Expected:** an `activity` row `walking`; within its delay a `subscribed` row
`motion, foreground every 30 s, motion: walking`; the notification "W ruchu: odczyt co 30 s";
readings about every 30 s with `requested_mode` `foreground`. Note the delay from the start of the
walk to the `activity` row's `at`, and from `at` to the first frequent reading.

**On failure:** no `activity` row: the registration (T3), the receiver; an `activity` row but
`subscribe_failed` and background readings: the start of the service was refused (the exemption).

### T5. A drive switches to 10 s; lights do not switch back

**Status:** pending

**Do:** an ordinary drive with stops at lights.

**Why:** items 3 and 4.

**Expected:** `activity` `in_vehicle`, then readings every 10 s; `activity` `still` at lights followed
by `in_vehicle` without a `motion_settled` between them when the stop was under 3 minutes.

**On failure:** `Motion.onTransition`, `MotionReceiver` (interval change).

### T6. Standing 3 minutes switches back

**Status:** pending

**Do:** after T4 or T5, stand or put the phone down for 5 minutes.

**Why:** item 4.

**Expected:** `activity` `still`; about 3 minutes after its `at`, `motion_settled` and `subscribed`
`motion, background, still`; the notification gone.

**On failure:** no reading during the stop (no settle until the watch): the gap between `still` and
`motion_settled` shows it.

### T7. After a reboot

**Status:** pending

**Do:** reboot the phone during a frequent stretch (after T4 starts).

**Why:** item 5.

**Expected:** after the boot `reboot`, then `subscribed` `motion, background, reboot`; no notification
until the next motion.

**On failure:** `LocationBootReceiver` (motion state reset).

### T8. A stop the API missed

**Status:** pending

**Do:** after a drive, leave the phone in the parked car or on a desk without moving it; read the
log 15 minutes later.

**Why:** item 4 (the stationary settle).

**Expected:** either `motion_settled` `still since …` about 3 minutes after an `activity` `still`, or,
with no `still` row, `motion_settled` `stationary since …` about 10 minutes after the last reading
more than 100 m away.

**On failure:** `Motion.onReading`, `LocationPipeline.recordReadings` (the anchor).

## Before a downgrade

Switch the mode to "Tylko w tle" before installing an older build over this one: an older build
would send `requested_mode` `motion`, which personal-agent refuses.

## When this plan is done

Must-pass: T1, T3, T4, T6, T7, T8. T2 and T5 are must-pass for the logic; the API's delays and
classification in T4–T5 are recorded, not judged (a slow or wrong classification is a limitation of
the device's recognition, not a failure of the app).
