# Manual test: action first in Jedzenie (V4 of the redesign)

**Design:** ADR-NET-009; personal-agent ADR-API-127; workspace `docs/requirements/off-roadmap/2026-11-15-diet-action-first/` (design note `drafts/01-action-contract.md`).
**Overall status:** passed (2026-11-15, on 2.3.0+64; Rozmowy named a diet conversation "Bez sprawy", fixed in 2.3.1+65 and checked on the Pixel: two diet conversations read "Jedzenie", the locked-phone one "Bez sprawy")
**Why now:** a meal said on the diet's screens reaches personal-agent with the subject Jedzenie, is logged at once, and the reply carries the meal for a card with Popraw and Cofnij. Unit, widget and HTTP tests cover the subject, the `actions` field and the card; the lab measured the prompt on the owner's real words (pa-lab `diet-subject-v1`). Only the phone shows a real utterance, the card under it, the undo against personal-agent and the hand-over by voice.
**Time budget:** ~25 min, Pixel, dev flavor of the `nov26-redesign` branch (2.3.0+64), against the dev personal-agent on `:8898` (a copy of production), restarted on the V4 code with its own MCP socket.
**What we are testing:** that a meal said on the diet's day is logged and only confirmed, with a card that names it; that Popraw corrects it and Cofnij removes it; that words about shopping said on the diet are handed over and done; that with the phone locked an utterance is Dzień and has no card.

## Status legend

See the canonical legend in [`p040-agenda-notifications.md`](p040-agenda-notifications.md#status-legend).

## Status summary

| # | Case | Status |
|---|---|---|
| S1 | Dev PA on the V4 code, the dev app 2.3.0+64, a target on the diet | passed (2026-11-15, Pixel 11 Pro, dev 2.3.0+64, test PA) |
| T1 | A meal said on the diet's day: logged, confirmed, the card | passed (2026-11-15, Pixel 11 Pro, dev 2.3.0+64, test PA, owner's voice) |
| T2 | Popraw on the card: the meal corrected | passed (2026-11-15, Pixel 11 Pro, dev 2.3.0+64, test PA) |
| T3 | Cofnij on the card: the meal removed | passed (2026-11-15, Pixel 11 Pro, dev 2.3.0+64, test PA, owner's voice) |
| T4 | Shopping said on the diet: handed over, on the list, no meal | passed (2026-11-15, Pixel 11 Pro, dev 2.3.0+64, test PA, owner's voice) |
| T5 | Nothing eaten, said on the diet: answered, nothing logged | passed (2026-11-15, Pixel 11 Pro, dev 2.3.0+64, test PA, owner's voice) |
| T6 | With the phone locked: Dzień, logged, the meal named aloud | passed (2026-11-15, Pixel 11 Pro, dev 2.3.0+64, test PA, owner's voice; a first try with the phone not locked was answered in Jedzenie, as it should) |

---

## Setup

### S1 — Dev PA on the V4 code, the dev app, a target

**Status:** passed (2026-11-15, Pixel 11 Pro, dev 2.3.0+64, test PA): versionCode 64, Settings `http://192.168.0.139:8898/…`, "Connection successful"; a typed turn in Jedzenie on the dev PA offered 6 tools and called one

**Do:**
1. Restart the dev PA on `:8898` from the `nov26-redesign` worktree with its own socket: `PA_MCP_SOCKET=/tmp/pa-8898/mcp.sock make pa-dev NAME=nov26-redesign`.
2. Check a first typed turn's `tool_calls` in `chat_turn_traces` of the dev PA's database (the tools are connected).
3. `make va-dev NAME=nov26-redesign` in the workspace root, the phone on USB; Settings shows 2.3.0+64 and the `:8898` URL; Test Connection succeeds.
4. The diet has a target (the copy's, or one set on Cel).

**Expected:** Jedzenie opens on today with "Zostało …" and the field at the bottom.

---

## Cases

### T1 — A meal said on the diet's day (owner)

**Status:** passed (2026-11-15, Pixel 11 Pro, dev 2.3.0+64, test PA, owner's voice): Groq heard "Wpum cover z mlekiem."; logged "Kawa z mlekiem" 50 (20–100) with no question; subject `diet`, 6 tools, one call; the card "✓ Kawa z mlekiem · 16:28 / 50 (20–100) kcal · zostało 320" with Popraw and Cofnij; the day showed it without a pull
**Do:** on Jedzenie (today), by the field's mic: "wypiłem kawę z mlekiem".
**Why:** ADR-API-127 §2 and §4; ADR-NET-009 §1–3.
**Expected:** the reply is one sentence naming the meal and the kcal, with no question; under it a card "✓ kawa z mlekiem · HH:MM", "N (low–high) kcal · zostało M", Popraw and Cofnij; the day shows the meal without a pull; the dev PA's log has the subject `diet` and the turn offered 6 tools.
**On failure:** the transcript's `subject` (`adb logcat`, the dev PA's log); `actions` in the voice response; `latestAgentActionsProvider`; `chattools.ToolsFor`.

### T2 — Popraw

**Status:** passed (2026-11-15, Pixel 11 Pro, dev 2.3.0+64, test PA): the sheet opened with 50, 20, 100, 16:28; kcal 80 saved; the card went; the day and the dev PA show 80, "Zostało 290". Seen: correcting kcal alone made the range 80–80 (the sheet of V1)
**Do:** on T1's card tap Popraw, change kcal, Zapisz.
**Why:** 05 §2 of the discussion; ADR-NET-009 §3.
**Expected:** the sheet opens with the meal's estimate; after Zapisz the card goes, and the day shows the new kcal.
**On failure:** `MealActionCard._correct`; `PATCH /api/v1/diet/meals/{id}` in the dev PA's log.

### T3 — Cofnij (owner)

**Status:** passed (2026-11-15, Pixel 11 Pro, dev 2.3.0+64, test PA, owner's voice): "Zjadłem banana." logged Banan 105 (90–125) with its card; Cofnij removed it from the dev PA and the day ("Zostało 290") and took the card away; "Cofnięto: jabłko" was read on the screen on a later undo
**Do:** say another meal ("zjadłem banana"); on its card tap Cofnij.
**Why:** 10 §4: undo is what makes acting without asking safe.
**Expected:** "Cofnięto: banan"; the card goes; the day no longer has the meal; the dev PA holds no such meal (`GET /api/v1/diet/day`).
**On failure:** `MealActionCard._undo`; `DELETE /api/v1/diet/meals/{id}`.

### T4 — Shopping said on the diet (owner)

**Status:** passed (2026-11-15, Pixel 11 Pro, dev 2.3.0+64, test PA, owner's voice): "handed over to day" (subject diet) in the log, the trace `hand_over` once then `add_shopping_item`, 5.6 s; milk was already on the list from V3's check, and the reply said so; no card, no meal
**Do:** on Jedzenie, by the mic: "dopisz mleko do zakupów".
**Why:** ADR-API-127 §3: the hand-over, ended at once.
**Expected:** the reply says it was added to the shopping list; Zakupy shows "mleko"; no card, no meal; the dev PA's log has "handed over to day" and one `hand_over` in the turn's trace.
**On failure:** `ExecHandOver`, `TurnUse.MarkHandedOver`; the trace of the turn.

### T5 — Nothing eaten (owner)

**Status:** passed (2026-11-15, Pixel 11 Pro, dev 2.3.0+64, test PA, owner's voice): "800 do 1000 kcal … Niczego nie zapisałem, bo to tylko pytanie"; no tool call, no meal, no card
**Do:** on Jedzenie, by the mic: "ile ma kalorii pizza margherita?".
**Why:** ADR-API-127 §2: what was not eaten is never logged.
**Expected:** an answer with a number; no card; the day unchanged.
**On failure:** the prompt of Jedzenie (`DietSubjectGuidance`).

### T6 — The phone locked (owner)

**Status:** passed (2026-11-15, Pixel 11 Pro, dev 2.3.0+64, test PA, owner's voice): with the phone locked the turn went with no subject (36 tools), "new session on a change of subject \"diet\" -> \"\"" in the log, the apple logged and named aloud; Dzień saw the first try's apple and offered to remove the double. Back on the diet the meal's card stood under the reply: `actions` come with any meal logged
**Do:** on Jedzenie start listening; lock the phone; say "zjadłem jabłko"; unlock and open Jedzenie.
**Why:** ADR-NET-008: with the phone locked an utterance is Dzień; ADR-NET-009 §4.
**Expected:** the meal is logged (Dzień logs a meal said as eaten) and the spoken reply names it and the kcal; the conversation is "Bez sprawy" in Rozmowy; the day shows the meal, and its card once the diet is in front again.
**On failure:** `utteranceSubjectReaderProvider` in `app.dart`; the dev PA's log ("new session on a change of subject").

---

## When this plan is done

All cases are must-pass. T1, T3, T4, T5 and T6 need the owner's voice; the agent drives the rest with `scripts/device-check/ui.py` and reads the dev PA.
