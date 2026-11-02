# Manual test: places

**Design:** [ADR-NET-006](../decisions/ADR-NET-006-places-local-copy-and-queue.md), personal-agent ADR-API-112.
**Overall status:** **pending**.
**Why now:** the permission dialog, a real position and a lost network exist only on a device.
**Time budget:** ~30 min, Pixel, stable flavor.
**What we are testing:** that a place is named in two taps, reaches personal-agent once with a poor link, can be corrected on both sides, and is never saved with a position from before.

## Status legend

See the canonical legend in [`p040-agenda-notifications.md`](p040-agenda-notifications.md#status-legend).

## Status summary

| # | Case | Status |
|---|---|---|
| S1 | Personal-agent with places runs on production | pending |
| S2 | The stable build is on the Pixel | pending |
| T1 | The screen opens from Shopping and from Record | pending |
| T2 | With the log off, the screen shows a position and its accuracy | pending |
| T3 | With permission refused, it says so and opens the settings | pending |
| T4 | A name, a tap: the place is in PA and in the web UI | pending |
| T5 | With no network: saved, marked as waiting, sent once after the network returns | pending |
| T6 | With no network and the app closed: sent on the next opening | pending |
| T7 | Rename, move here, store types and delete on the phone reach the web UI | pending |
| T8 | A correction in the web UI reaches the phone on opening the screen | pending |
| T9 | The location log keeps writing, in its mode, and hands-free still works | pending |
| T10 | Coming back to the app takes a new reading before saving | pending |

---

## Setup

### S1. Personal-agent with places runs on production

**Status:** pending

The shipped build has no cleartext door to a dev personal-agent, so this plan runs against production, after its deploy (the same order as the location log). Check with `curl -H "Authorization: Bearer $API_TOKEN" https://agent.jarco.casa/api/v1/places`: `200` and a `places` list.

### S2. The stable build is on the Pixel

**Status:** pending

Copy `.env.mobile` into the worktree, then `make install-android`. Settings shows 1.12.0. Note the location log's mode beforehand: the cases must leave it as it was.

## Cases

### T1. The screen opens from Shopping and from Record

**Status:** pending
**Do:**
1. Open Shopping, tap the pin icon, go back.
2. Open Record, tap the pin icon, go back.

**Why:** criterion 1 of the readiness document: one tap from both app bars.
**Expected:** the Miejsca screen opens both ways, and back returns to the tab.
**On failure:** the `/places` route in `lib/app/router.dart`, and `context.push` in the two app bars.

### T2. With the log off, the screen shows a position and its accuracy

**Status:** pending
**Do:**
1. Turn the log off in Settings.
2. Open Miejsca and wait.
3. Turn the log back on to its earlier mode.

**Why:** the reading is its own channel, and does not depend on the log.
**Expected:** coordinates and `±N m` within 20 s.
**On failure:** `PlaceReadingBridge.kt`: `adb logcat` for the `com.voiceagent/place_reading` call; "Nie ma odczytu" means no fix came within 20 s.

### T3. With permission refused, it says so and opens the settings

**Status:** pending
**Do:**
1. Refuse location in the system settings.
2. Open Miejsca, type a name.
3. Tap Otwórz ustawienia, grant location, come back.

**Why:** criterion 2: it says plainly that there is no reading. Coming back must not need the read button.
**Expected:** "Brak zgody na lokalizację", Zapisz tutaj is off, the settings open, and after coming back a position appears on its own.
**On failure:** the permission branch of the port, then the resume listener of `PlacesScreen`.

### T4. A name, a tap: the place is in PA and in the web UI

**Status:** pending
**Do:**
1. Type a name, choose a suggested tag.
2. Tap Zapisz tutaj.
3. Read `GET /api/v1/places`, and open the web UI's Places view.

**Why:** criteria 3 and 5.
**Expected:** the place heads the list with no waiting icon, one row in PA, and the web UI shows it.
**On failure:** the line under the button says what PA refused; else the sync loop of `PlacesNotifier`.

### T5. With no network: saved, marked as waiting, sent once

**Status:** pending
**Do:**
1. Airplane mode on. Save a place.
2. Airplane mode off.
3. Read `GET /api/v1/places`.

**Why:** criterion 6, while the app stays open.
**Expected:** at once the waiting icon and "Czeka na wysłanie: 1"; the icon goes within a minute of the link's return; PA holds one row for it.
**On failure:** `places_sync.dart`, the link event. Two rows would break ADR-NET-006: compare the ids.

### T6. With no network and the app closed: sent on the next opening

**Status:** pending
**Do:**
1. Airplane mode on, save a place.
2. Close the app from recents, airplane mode off.
3. Open the app.

**Why:** criterion 6 across a closed process: the queue is written before the send.
**Expected:** one row in PA.
**On failure:** the `places_snapshot_v1` key: was the queue written, and did the start of `places_sync.dart` run after the config loaded?

### T7. Rename, move here, store types and delete on the phone reach the web UI

**Status:** pending
**Do:**
1. Tap a place: rename it, tap Przenieś tutaj, choose a store type, save.
2. Check the web UI.
3. Delete the place on the phone, check the web UI.

**Why:** criteria 4 and 7, on the phone.
**Expected:** the web UI shows all three changes, then the place is gone from both.
**On failure:** no store types means the catalogue did not arrive; a change that does not land means the stored copy was newer, so check the two clocks.

### T8. A correction in the web UI reaches the phone on opening the screen

**Status:** pending
**Do:**
1. Rename a place in the web UI.
2. Open Miejsca, or pull to refresh.

**Why:** criterion 7, the other way.
**Expected:** the new name shows.
**On failure:** `PUT` from the web UI has no time, so it lands; if PA shows the new name and the phone does not, look at the fetch in `PlacesNotifier` against what is pending.

### T9. The location log keeps writing, and hands-free still works

**Status:** pending
**Do:**
1. Run the whole plan with the log in its usual mode.
2. Read the web UI's Location view.
3. Start and stop a hands-free session.

**Why:** the brief leaves the running measuring week and the microphone alone.
**Expected:** the Location view keeps gaining rows during the run, and hands-free starts and stops as before.
**On failure:** a gap in rows at the time of T2 or T3 is expected only if the log was off.

### T10. Coming back to the app takes a new reading before saving

**Status:** pending
**Do:**
1. Open Miejsca at one spot, wait for the position, type a name.
2. Leave the app, walk at least 200 m, come back.
3. Note the coordinates and tap Zapisz tutaj as soon as the button allows it.

**Why:** a position from before must never be saved as "here" (criterion 2, the current reading).
**Expected:** a spinner and Zapisz tutaj off until the new reading arrives; the saved place has the new position.
**On failure:** the resume listener of `PlacesScreen`, and `canSave`.

## When this plan is done

Every case is must-pass: any failure blocks merging the app. None is OEM-conditional, as the Pixel is the only device in use.
