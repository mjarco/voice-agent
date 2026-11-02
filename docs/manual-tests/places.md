# Manual test: places

**Design:** [ADR-NET-006](../decisions/ADR-NET-006-places-local-copy-and-queue.md), personal-agent ADR-API-111.
**Overall status:** **not run**.
**Why now:** the permission dialog, a real position and a lost network exist only on a device.
**Time budget:** ~20 min, Pixel, stable flavor.
**What we are testing:** that a place is named in two taps, reaches personal-agent once with a poor link, and can be corrected on both sides.

## Status legend

See the canonical legend in [`p040-agenda-notifications.md`](p040-agenda-notifications.md#status-legend).

## Status summary

| # | Case | Status |
|---|---|---|
| T1 | The screen opens from Shopping and from Record | not run |
| T2 | With the log off, the screen shows a position and its accuracy | not run |
| T3 | With permission refused, it says so and opens the settings | not run |
| T4 | A name, a tap: the place is in PA and in the web UI | not run |
| T5 | With no network: saved, marked as waiting, sent once after the network returns | not run |
| T6 | With no network and the app closed: sent on the next opening | not run |
| T7 | Rename, move here, store types and delete on the phone reach the web UI | not run |
| T8 | A correction in the web UI reaches the phone on opening the screen | not run |
| T9 | The location log keeps writing, in its mode, and hands-free still works | not run |

---

## Setup

A dev personal-agent on `:8898` from the `places` branch, or production after its deploy. `GET /api/v1/places` shows what PA holds.

## Cases

**T1.** Open Shopping, tap the pin icon; go back; do the same from Record. Pass: the Miejsca screen opens both ways, and back returns to the tab.

**T2.** Turn the log off in Settings. Open Miejsca. Pass: coordinates and `±N m` appear within 20 s. Turn the log back on to its earlier mode.

**T3.** Refuse location in the system settings, open Miejsca. Pass: "Brak zgody na lokalizację" and a button to the settings; saving is off. Restore the permission.

**T4.** Type a name, tap Zapisz tutaj. Pass: the place heads the list with no waiting icon, and one row is in `GET /api/v1/places`, with the web UI's Places view showing it.

**T5.** Airplane mode on. Save a place. Pass: it shows at once with the waiting icon and "Czeka na wysłanie: 1". Airplane mode off. Pass: the icon goes within a minute, and PA holds one row for it.

**T6.** Airplane mode on, save a place, close the app from recents, airplane mode off, open the app. Pass: one row in PA.

**T7.** Tap a place: rename it, tap Przenieś tutaj, choose a store type, save. Pass: the web UI shows all three. Delete it. Pass: gone from the list and the web UI.

**T8.** Rename a place in the web UI, then open Miejsca. Pass: the new name shows.

**T9.** Pass: the Location view keeps gaining rows during the run, and a hands-free session starts and stops as before.
