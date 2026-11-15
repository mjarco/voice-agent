# Manual test: the home-screen widget (V2 of the redesign)

**Design:** ADR-PLATFORM-015; personal-agent ADR-API-124 (the today view); workspace `docs/requirements/off-roadmap/2026-11-15-va-widget/`.
**Overall status:** pending
**Why now:** the widget is drawn by the launcher from what the app hands it, and a WorkManager task reads the day with the app closed. Unit and widget tests cover the numbers, the taps' routes and the read; only the phone shows the launcher, the background schedule and the microphone started from a tap.
**Time budget:** ~30 min, plus up to 15 min of waiting in T3, Pixel, dev flavor of the `nov26-redesign` branch, against the dev personal-agent on `:8898` (a copy of production).
**What we are testing:** that the widget's numbers are Dziś's, that what is done in the app reaches it at once and what is done elsewhere within the refresh, that each tap opens its screen with Dziś under it, and that the mic starts listening.

## Status legend

See the canonical legend in [`p040-agenda-notifications.md`](p040-agenda-notifications.md#status-legend).

## Status summary

| # | Case | Status |
|---|---|---|
| S1 | Dev PA, the dev app, the widget placed | pending |
| T1 | The numbers are Dziś's | pending |
| T2 | A meal corrected in the app moves the widget on leaving it | pending |
| T3 | A task resolved outside the app shows within the refresh | pending |
| T4 | Each tap opens its screen; Back lands on Dziś | pending |
| T5 | The mic opens Dziś listening, warm and cold | pending |
| T6 | Recents does not repeat a tap | pending |
| T7 | The next morning: today's numbers or dashes, never yesterday's | pending |

---

## Setup

### S1 — Dev PA, the dev app, the widget placed

**Status:** pending

**Do:**
1. The dev PA on `:8898` (`make pa-dev NAME=nov26-redesign`, after `make pa-dev-import` for a copy of production).
2. `make va-dev NAME=nov26-redesign` in the workspace root, the phone on USB; in the app's Settings read the `:8898` URL.
3. Settings → "Dodaj widżet Dziś"; accept the system dialog.

**Expected:** Settings shows 2.1.0+61; the widget sits on the home screen, 4 × 2, with numbers after the app's first read.

---

## Cases

### T1 — The numbers are Dziś's

**Status:** pending
**Do:** open Dziś, then go to the home screen; compare the widget with `GET /api/v1/today?v=1` on the dev PA.
**Why:** ADR-PLATFORM-015 §1, §3; the owner's three numbers (M3 of the discussion).
**Expected:** "N kcal" with "zostało" (amber number and "mniej niż zapas" under the reserve), "N zadania/zadań" with the overdue count or "na dziś", "N sprawy w toku"; the read's time in the corner.
**On failure:** `HomeWidgetNumbers.of`; the `HomeWidgetPreferences` file of the app (`run-as … cat shared_prefs/HomeWidgetPreferences.xml`).

### T2 — A meal corrected in the app

**Status:** pending
**Do:** Jedzenie → a meal → correct its kcal; leave the app with Home.
**Why:** ADR-PLATFORM-015 §4: leaving the app reads the day once more.
**Expected:** the widget's kcal changes by the correction when the home screen shows, without opening the app again.
**On failure:** the shell's `paused` branch in `app_shell_scaffold.dart`; whether the read reached the dev PA (its log).

### T3 — A task resolved outside the app

**Status:** pending
**Do:** with the app in the background, resolve one of today's tasks through the dev PA's API (as the web UI does); wait, reading the widget every minute.
**Why:** ADR-PLATFORM-015 §5: the WorkManager task every 15 minutes.
**Expected:** the tasks' count drops within 15 minutes (Android may defer it longer in Doze; note the delay seen).
**On failure:** `adb shell dumpsys jobscheduler | grep -A5 voice_agent.dev` for the `widget-refresh` job; the dev PA's log for `/api/v1/today` with the app closed.

### T4 — The taps

**Status:** pending
**Do:** from the home screen tap the calories, Back; the tasks; the matters, Back. Once with the app running, once after `am force-stop`.
**Why:** ADR-PLATFORM-015 §6; 06 §4 ("all open over Dziś, so Back lands there").
**Expected:** the calories open the diet's day, Back shows Dziś; the tasks open Dziś; the matters open Sprawy, Back shows Dziś. The same from a cold start.
**On failure:** `WidgetTapBridge` (`adb logcat`), `_openWidgetTap` in `app.dart`.

### T5 — The mic

**Status:** pending
**Do:** tap the widget's mic with the app in the background; then after `am force-stop`.
**Why:** ADR-PLATFORM-015 §6; the task's D1 (listening with the app closed is not built).
**Expected:** the app opens on Dziś, the field reads "Słucham…", the strip at the top is orange and the session's notification shows; speech is heard and answered (owner).
**On failure:** `HandsFreeController.listen`; `BFGS denied` or `allowWiu` in `adb logcat` means the session started before the activity was in front.

### T6 — Recents

**Status:** pending
**Do:** start the app from the widget's mic, end the session (Zakończ), press Home, reopen the app from Recents.
**Why:** Recents redelivers the intent that started the task (`FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY`); `WidgetTapBridge` drops it.
**Expected:** the app opens where it was, not listening.
**On failure:** `WidgetTapBridge.accept`.

### T7 — The next morning

**Status:** pending (a field check: it needs a night)
**Do:** leave the phone overnight with the app closed; look at the widget before opening the app.
**Why:** ADR-PLATFORM-015 §2: numbers of another day are not drawn.
**Expected:** today's numbers (the background task read them) or dashes with "czekam na dzisiejszy dzień"; never yesterday's calories.
**On failure:** the `day` key against the phone's date in `TodayWidgetProvider.render`.

---

## When this plan is done

All cases are must-pass except T3's delay, which is Android's: a count that drops at all with the app closed passes, the delay is recorded. T7 is read as a field check in the workspace register.
