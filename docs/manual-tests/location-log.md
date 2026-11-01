# Manual test: the location log

**Design:** [ADR-PLATFORM-009](../decisions/ADR-PLATFORM-009-native-location-pipeline.md), [ADR-NET-005](../decisions/ADR-NET-005-location-log-background-upload.md); personal-agent ADR-API-107.
**Overall status:** **in-progress**
**Why now:** subscriptions, permissions, wake-ups, reboots and network loss exist only on a device.
**Time budget:** ~30 min, Pixel, stable flavor, against a dev personal-agent.
**What we are testing:** that readings reach personal-agent, that a lost network loses nothing and duplicates nothing, and that collection survives a reboot.

## Status legend

See the canonical legend in [`p040-agenda-notifications.md`](p040-agenda-notifications.md#status-legend).

## Status summary

| # | Case | Status |
|---|---|---|
| S1 | Dev personal-agent on `:8898` | pending |
| S2 | Install and point the log at it | pending |
| T1 | Foreground mode: readings reach the log | pending |
| T2 | Background mode: readings reach the log with the app closed | pending |
| T3 | Network cut: rows queue, drain, no duplicates | pending |
| T4 | PA down: same, with the network up | pending |
| T5 | Reboot resumes collection | pending |
| T6 | Pause stops readings; the queue still drains | pending |
| T7 | Delete-all | pending |
| T8 | Hands-free session ending leaves foreground mode running | pending |
| T9 | Task Manager Stop is recorded on the next start | pending |

---

## Setup

### S1 — Dev personal-agent

**Status:** pending

**Do:** `make pa-dev NAME=location-log` from the workspace root, on a copy of a database. Never `:8888`.

### S2 — Install and point the log at it

**Status:** pending

**Do:**
1. `make install-android`.
2. In Settings → Dziennik lokalizacji, set the server to `http://laptop.lan:8898/api/v1` and confirm with the keyboard.
3. Grant location "all the time".

---

## Tests

Row counts: `curl -s localhost:8898/api/v1/location/entries?limit=1`, field `total`. `sqlite3 personal-agent.db "SELECT COUNT(*), COUNT(DISTINCT id) FROM location_log"` proves no duplicates.

### T1 — Foreground mode (~3 min)

**Status:** pending

**Do:** choose the foreground service, every 10 s, turn the switch on, walk to a window, wait 2 minutes.

**Why:** ADR-PLATFORM-009 items 1 and 3.

**Expected:** a permanent "Dziennik lokalizacji" notification; `total` grows about 6 a minute; a `start` and a `subscribed` row; the web UI's Location view shows them, with a delay under a few seconds.

**On failure:** `lastError` in Settings. `CLEARTEXT` means the URL's host is not `laptop.lan`; a `subscribe_failed` row holds the exception.

### T2 — Background mode (~30 min, mostly waiting)

**Status:** pending

**Do:** choose "Tylko w tle", leave the switch on, swipe the app away, wait.

**Why:** ADR-NET-005 item 1; the wake-up path with no Flutter.

**Expected:** the notification is gone; rows arrive at a few an hour, `requested_mode` `background`.

**On failure:** the permission must be "always"; `adb shell dumpsys location` lists the registration.

### T3 — Network cut (~5 min)

**Status:** pending

**Do:** in foreground mode, note `total`, cut the phone's network for 2 minutes, restore it.

**Why:** ADR-NET-005 items 1 to 3, and the brief's "written locally, sent later".

**Expected:** Settings shows the queue growing and a send error; after the network returns the queue reaches 0 within a minute or so; `COUNT(*)` equals `COUNT(DISTINCT id)`, and readings from the gap arrive with their own `recorded_at`.

**On failure:** `adb shell dumpsys jobscheduler | grep voice_agent` for the drain job.

### T4 — PA down (~4 min)

**Status:** pending

**Do:** stop the dev personal-agent for 2 minutes with the network up, start it again.

**Why:** ADR-NET-005 item 2: the worker's backoff, not the network constraint, brings it back.

**Expected:** as T3; a drain can take up to a few minutes of backoff, or the next reading.

### T5 — Reboot (~5 min, the owner unlocks)

**Status:** pending

**Do:** with the log on, reboot the phone, unlock it, do not open the app, wait 5 minutes.

**Why:** ADR-PLATFORM-009 item 4; `BOOT_COMPLETED` needs a first unlock.

**Expected:** `reboot` and `subscribed` rows with `reboot` in the detail, and readings after them, in both modes.

**On failure:** a `subscribe_failed` row; for the foreground mode check the "always" permission.

### T6 — Pause (~3 min)

**Status:** pending

**Do:** turn the switch off with rows queued.

**Why:** the brief's pause switch.

**Expected:** a `stop` row; the notification goes; no new readings; the queue still reaches 0.

### T7 — Delete-all (~1 min)

**Status:** pending

**Do:** press Delete all in the web UI and confirm.

**Why:** ADR-API-107 item 6.

**Expected:** `total` 0; the phone's next rows arrive normally.

### T8 — Hands-free session (~3 min)

**Status:** pending

**Do:** in foreground mode, start and stop a hands-free session.

**Why:** ADR-PLATFORM-009 item 3: the two services do not share a lifecycle.

**Expected:** readings continue with no gap; the location notification stays.

### T9 — Task Manager Stop (~3 min)

**Status:** pending

**Do:** stop the app from the Task Manager in the notification shade, then open it.

**Why:** ADR-PLATFORM-009 item 5.

**Expected:** a `process_exit` row with `user_requested`, then `subscribed` with `app_start`.

---

## When this plan is done

Must pass: T1 to T7. T8 and T9 are must-pass before the log runs for real. A subscription that delivers fewer readings than asked is a finding of the log, not a failure of this plan.
