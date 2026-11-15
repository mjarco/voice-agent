# Manual test: action first in Jedzenie (V4 of the redesign)

**Design:** ADR-NET-009; personal-agent ADR-API-127; workspace `docs/requirements/off-roadmap/2026-11-15-diet-action-first/` (design note `drafts/01-action-contract.md`).
**Overall status:** pending
**Why now:** a meal said on the diet's screens reaches personal-agent with the subject Jedzenie, is logged at once, and the reply carries the meal for a card with Popraw and Cofnij. Unit, widget and HTTP tests cover the subject, the `actions` field and the card; the lab measured the prompt on the owner's real words (pa-lab `diet-subject-v1`). Only the phone shows a real utterance, the card under it, the undo against personal-agent and the hand-over by voice.
**Time budget:** ~25 min, Pixel, dev flavor of the `nov26-redesign` branch (2.3.0+64), against the dev personal-agent on `:8898` (a copy of production), restarted on the V4 code with its own MCP socket.
**What we are testing:** that a meal said on the diet's day is logged and only confirmed, with a card that names it; that Popraw corrects it and Cofnij removes it; that words about shopping said on the diet are handed over and done; that with the phone locked an utterance is Dzień and has no card.

## Status legend

See the canonical legend in [`p040-agenda-notifications.md`](p040-agenda-notifications.md#status-legend).

## Status summary

| # | Case | Status |
|---|---|---|
| S1 | Dev PA on the V4 code, the dev app 2.3.0+64, a target on the diet | pending |
| T1 | A meal said on the diet's day: logged, confirmed, the card | pending |
| T2 | Popraw on the card: the meal corrected | pending |
| T3 | Cofnij on the card: the meal removed | pending |
| T4 | Shopping said on the diet: handed over, on the list, no meal | pending |
| T5 | Nothing eaten, said on the diet: answered, nothing logged | pending |
| T6 | With the phone locked: Dzień, no card | pending |

---

## Setup

### S1 — Dev PA on the V4 code, the dev app, a target

**Status:** pending

**Do:**
1. Restart the dev PA on `:8898` from the `nov26-redesign` worktree with its own socket: `PA_MCP_SOCKET=/tmp/pa-8898/mcp.sock make pa-dev NAME=nov26-redesign`.
2. Check a first typed turn's `tool_calls` in `chat_turn_traces` of the dev PA's database (the tools are connected).
3. `make va-dev NAME=nov26-redesign` in the workspace root, the phone on USB; Settings shows 2.3.0+64 and the `:8898` URL; Test Connection succeeds.
4. The diet has a target (the copy's, or one set on Cel).

**Expected:** Jedzenie opens on today with "Zostało …" and the field at the bottom.

---

## Cases

### T1 — A meal said on the diet's day (owner)

**Status:** pending
**Do:** on Jedzenie (today), by the field's mic: "wypiłem kawę z mlekiem".
**Why:** ADR-API-127 §2 and §4; ADR-NET-009 §1–3.
**Expected:** the reply is one sentence naming the meal and the kcal, with no question; under it a card "✓ kawa z mlekiem · HH:MM", "N (low–high) kcal · zostało M", Popraw and Cofnij; the day shows the meal without a pull; the dev PA's log has the subject `diet` and the turn offered 6 tools.
**On failure:** the transcript's `subject` (`adb logcat`, the dev PA's log); `actions` in the voice response; `latestAgentActionsProvider`; `chattools.ToolsFor`.

### T2 — Popraw

**Status:** pending
**Do:** on T1's card tap Popraw, change kcal, Zapisz.
**Why:** 05 §2 of the discussion; ADR-NET-009 §3.
**Expected:** the sheet opens with the meal's estimate; after Zapisz the card goes, and the day shows the new kcal.
**On failure:** `MealActionCard._correct`; `PATCH /api/v1/diet/meals/{id}` in the dev PA's log.

### T3 — Cofnij (owner)

**Status:** pending
**Do:** say another meal ("zjadłem banana"); on its card tap Cofnij.
**Why:** 10 §4: undo is what makes acting without asking safe.
**Expected:** "Cofnięto: banan"; the card goes; the day no longer has the meal; the dev PA holds no such meal (`GET /api/v1/diet/day`).
**On failure:** `MealActionCard._undo`; `DELETE /api/v1/diet/meals/{id}`.

### T4 — Shopping said on the diet (owner)

**Status:** pending
**Do:** on Jedzenie, by the mic: "dopisz mleko do zakupów".
**Why:** ADR-API-127 §3: the hand-over, ended at once.
**Expected:** the reply says it was added to the shopping list; Zakupy shows "mleko"; no card, no meal; the dev PA's log has "handed over to day" and one `hand_over` in the turn's trace.
**On failure:** `ExecHandOver`, `TurnUse.MarkHandedOver`; the trace of the turn.

### T5 — Nothing eaten (owner)

**Status:** pending
**Do:** on Jedzenie, by the mic: "ile ma kalorii pizza margherita?".
**Why:** ADR-API-127 §2: what was not eaten is never logged.
**Expected:** an answer with a number; no card; the day unchanged.
**On failure:** the prompt of Jedzenie (`DietSubjectGuidance`).

### T6 — The phone locked (owner)

**Status:** pending
**Do:** on Jedzenie start listening; lock the phone; say "zjadłem jabłko"; unlock and open Jedzenie.
**Why:** ADR-NET-008: with the phone locked an utterance is Dzień; ADR-NET-009 §4.
**Expected:** the meal is logged (Dzień logs a meal said as eaten) and the spoken reply names it and the kcal; the conversation is "Bez sprawy" in Rozmowy; the day shows the meal.
**On failure:** `utteranceSubjectReaderProvider` in `app.dart`; the dev PA's log ("new session on a change of subject").

---

## When this plan is done

All cases are must-pass. T1, T3, T4, T5 and T6 need the owner's voice; the agent drives the rest with `scripts/device-check/ui.py` and reads the dev PA.
