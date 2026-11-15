# Manual test: Dziś, the diet and the tabs (V1 of the redesign)

**Design:** ADR-ARCH-013; personal-agent ADR-API-124; workspace `docs/requirements/off-roadmap/2026-11-15-va-today/`.
**Overall status:** **in progress** (agent's run 2026-11-15; T6, T7 with the owner)
**Why now:** the start screen, the tabs and the mic's place changed together, and the voice inputs moved from Record to the shell. Widget tests cover the screens; only the phone shows the headset, the lock screen and a notification's tap.
**Time budget:** ~30 min, Pixel, dev flavor of the `nov26-redesign` branch, against the dev personal-agent on `:8898` (a copy of production).
**What we are testing:** that Dziś tells the day through the day, that a task is done and skipped by a swipe and undone, that Back lands on Dziś, that the field's mic follows the owner's rule, and that the diet's screens correct and plan.

## Status legend

See the canonical legend in [`p040-agenda-notifications.md`](p040-agenda-notifications.md#status-legend).

## Status summary

| # | Case | Status |
|---|---|---|
| S1 | Dev PA and the dev app | passed (2026-11-15, Pixel, dev 2.0.0+60, dev PA) |
| T1 | Dziś at noon, in the evening, in the morning | partly: before 18:00 passed (2026-11-15, Pixel, dev 2.0.0+60, dev PA); after 18:00 pending |
| T2 | The warning under the reserve, on Dziś and on the glasses | passed (2026-11-15, Pixel, dev 2.0.0+60 with D10, dev PA); glasses: the dev PA's view only |
| T3 | A task swiped done, one skipped, Cofnij | passed (2026-11-15, Pixel, dev 2.0.0+60, dev PA) |
| T4 | A tap opens the task and the matter; Back to Dziś | passed (2026-11-15, Pixel, dev 2.0.0+60, dev PA) |
| T5 | Back on another tab, and a notification's tap | partly: Back passed (2026-11-15, Pixel, dev 2.0.0+60, dev PA); a notification's tap pending |
| T6 | The field's mic: tap on and off, long press, the reply in place | passed (2026-11-15, Pixel, dev 2.0.0+60, dev PA, owner); the finger hides the button while held |
| T7 | The headset and the volume keys with Record gone | passed (2026-11-15, Pixel, dev 2.0.0+60, dev PA, owner) |
| T8 | A meal corrected, a planned meal eaten, a menu set | passed (2026-11-15, Pixel, dev 2.0.0+60, dev PA) |
| T9 | The target with a new reserve | passed (2026-11-15, Pixel, dev 2.0.0+60, dev PA) |

---

## Setup

### S1 — Dev PA and the dev app

**Status:** pending

**Do:**
1. `make pa-dev-import NAME=nov26-redesign`, then `API_TOKEN=dev-check-token make pa-dev NAME=nov26-redesign` (`:8898`).
2. Build the dev flavor from the worktree with an env file holding `API_URL=http://<lan ip>:8898/api/v1/voice/transcript` and `API_TOKEN=dev-check-token` (never `.env.mobile`), install it over adb, `pm clear` it, and read the URL in Settings; Test Connection.

**Expected:** Settings shows 2.0.0+60 and the `:8898` URL; Test Connection passes.

---

## Cases

### T1 — Dziś through the day

**Status:** pending
**Do:** open the app at noon; change the dev PA's clock is not possible, so read Dziś before 18:00 and again after.
**Why:** ADR-API-124 §2 (the nudge turns at 18:00); 03 §3 of the discussion.
**Expected:** the app opens on Dziś with the date as its title. Before 18:00 without today's menu: "Nie masz jadłospisu na dziś. Ułożymy?"; from 18:00 without tomorrow's: "Na jutro nic nie zaplanowane. Ułożymy?". "Otwórz jadłospis" opens the menu, Back returns.
**On failure:** `GET /api/v1/today?v=1` on the dev PA; `TodayNotifier.refresh`.

### T2 — The warning

**Status:** pending
**Do:** log meals by voice until less than 600 kcal is left.
**Why:** ADR-API-124 §4–5.
**Expected:** Dziś's food block turns to the warning colour with "Zostało N kcal — mniej niż zapas"; the diet's day says the same with "mniej niż zapas 600"; the glasses' KCAL reads "Poniżej zapasu" (glass-native against the dev PA).
**On failure:** `warning` in `GET /api/v1/diet/day`; the target's `reserve_kcal`.

### T3 — Swipes

**Status:** pending
**Do:** swipe a task right; tap Cofnij; swipe it left.
**Why:** 03 §4 (right done, left skip, undo the snackbar's).
**Expected:** "Zrobione: …" then the task is back after Cofnij; "Pominięte: …" after the left swipe. The Agenda tab shows the same.
**On failure:** the task's `done`/`skip`/`undo` calls; `agendaChangesProvider`.

### T4 — Opening from Dziś

**Status:** pending
**Do:** tap a task; Back. Tap a matter in progress; Back.
**Expected:** the routine's and the matter's pages open over Dziś; Back returns to Dziś, not to another tab.

### T5 — Back and notifications

**Status:** pending
**Do:** open Agenda, press Back. Tap an agenda notification, press Back.
**Why:** ADR-ARCH-013 §2.
**Expected:** both Backs land on Dziś; a second Back leaves the app.

### T6 — The field's mic

**Status:** pending
**Do:** tap the mic, say something, tap it again. Hold it, speak, release. Tap "Otwórz rozmowę ›".
**Why:** the owner's rule (06 §3 of the discussion): a tap switches listening on and off, a long press records while held.
**Expected:** "Słucham…" after the first tap, "Wstrzymane — stuknij, by słuchać" after the second; a held press records and sends on release; the reply appears above the field; "Otwórz rozmowę ›" opens that conversation and Back returns to Dziś. "Zakończ" ends the session.
**On failure:** `MicButton`, `micModeProvider`.

### T7 — Headset and volume keys

**Status:** pending
**Do:** with the session listening, press the headset's button; lock the phone and press it again.
**Why:** ADR-ARCH-013 §4 (the inputs moved to `VoiceInputsHost`).
**Expected:** listening ↔ standby as before the redesign, locked too.
**On failure:** `VoiceInputsHost` not built (it wraps the shell's body).

### T8 — The diet's screens

**Status:** pending
**Do:** on the diet's day tap a meal, change its kcal and its hour, Zapisz; tap Zjedzone on a planned meal; in Jadłospis add an own meal to tomorrow's dinner, then take it off.
**Expected:** each change shows at once and on the web UI; tomorrow's nudge on Dziś disappears once tomorrow has a menu.

### T9 — The target

**Status:** pending
**Do:** Cel → Zmień cel, reserve 400.
**Expected:** "ostrzegaj poniżej 400 kcal"; the earlier target under "WCZEŚNIEJ"; Dziś's warning follows the new reserve.

---

## When this plan is done

All cases are must-pass for the redesign's merge, except T2's glasses part, which needs glass-native pointed at the dev PA (OEM-independent but optional for V1). The owner's real cases run in the smoke tests before the stable release.
