# Manual test: the day's story and the evening queue (V5 of the redesign)

**Design:** ADR-NET-010, ADR-NET-009 (amended); personal-agent ADR-API-128; workspace `docs/requirements/off-roadmap/2026-11-15-day-queue-story/` (design note `drafts/03-story-and-queue.md`).
**Overall status:** pending
**Why now:** the story and the queue are an API between personal-agent and the phone; unit and widget tests cover the parsing, the block, the settle and the thread's subject, and pa-lab measured the narration (day-story-v1 to v4) and the queue (queue-v1, v2). Only the phone shows a real evening, a real utterance put aside and a tap that settles it.
**Time budget:** ~25 min, Pixel, dev flavor of `nov26-redesign` (2.5.0+67), against the dev personal-agent on `:8898` (a copy of production) on the V5 code with its own MCP socket.
**What we are testing:** that an unclear utterance is put aside, not asked about; that the evening block tells the day and settles what waits; that a day's screen opens any day; that Napisz on the diet opens a thread in Jedzenie, and a meal typed there gets its card.

## Status legend

See the canonical legend in [`p040-agenda-notifications.md`](p040-agenda-notifications.md#status-legend).

## Status summary

| # | Case | Status |
|---|---|---|
| S1 | Dev PA on the V5 code, the dev app 2.5.0+67 | pending |
| T1 | An unclear utterance: "Odłożyłem na wieczór", nothing asked | pending |
| T2 | Before 19:00: the count on Dziś, the day's screen | pending |
| T3 | The evening block: the narration, a guess settles | pending |
| T4 | Nic drops; a past day's screen | pending |
| T5 | Napisz on the diet: a thread in Jedzenie, the meal's card in it | pending |

---

## Setup

### S1 — Dev PA on the V5 code, the dev app

**Status:** pending
**Do:**
1. Restart the dev PA on `:8898` from the `nov26-redesign` worktree with its own socket: `PA_MCP_SOCKET=/tmp/pa-8898/mcp.sock make pa-dev NAME=nov26-redesign` (migration 041 creates two tables).
2. `make va-dev NAME=nov26-redesign` in the workspace root, the phone on USB; Settings shows 2.5.0+67 and the `:8898` URL; Test Connection succeeds.

**Expected:** Dziś opens; `GET /api/v1/day/story?narrate=0` answers with `pending: []`.

---

## Cases

### T1 — An unclear utterance (owner)

**Status:** pending
**Do:** on Dziś, by the mic: "G-Shot".
**Why:** ADR-API-128 §4: words that could mean an action, not clearly which, are queued, not asked about.
**Expected:** the reply is one sentence, "Odłożyłem na wieczór." or near it, with no question; the dev PA's trace has `queue_for_evening`; the story's `pending` holds the words with two or three guesses.
**On failure:** `PendingPromptGuidance` in personal-agent; the turn's trace.

### T2 — Before 19:00: the count and the day's screen

**Status:** pending
**Do:** before 19:00, pull Dziś to refresh; tap "Do rozstrzygnięcia: 1"; then Back, and tap Dziś's title.
**Why:** ADR-NET-010 §2, §5.
**Expected:** the count line under the title, no story block; the day's screen shows what waits and today's timeline; the title opens the same screen; the dev PA logged no `day_story` call for these reads.
**On failure:** `DayStoryBlock` (`eveningFromHour`); `narrate=0` in the request.

### T3 — The evening block (owner)

**Status:** pending
**Do:** after 19:00 open Dziś; read the story; tap one of G-Shot's guesses.
**Why:** ADR-NET-010 §1, §3, §4; ADR-API-128 §6.
**Expected:** "DZIŚ W SKRÓCIE" with a few sentences of the day; the guess's line goes; the item or the task is where it would have been (Zakupy, Agenda); a second open of Dziś does not call the model again (the story is kept).
**On failure:** the story's `narration.check`; `POST /api/v1/day/pending/{id}/settle` in the dev PA's log.

### T4 — Nic, and a past day

**Status:** pending
**Do:** say another unclear thing ("chyba za dużo chleba"); in the evening block tap Nic; then open the day's screen and go a day back with ‹.
**Why:** ADR-NET-010 §4, §5.
**Expected:** the line goes and nothing is written; yesterday's screen shows its story (told once) and its timeline; a timeline line opens its thing.
**On failure:** `DayStoryScreen`; `settle` with `guess: null`.

### T5 — Napisz on the diet (owner)

**Status:** pending
**Do:** on Jedzenie tap Napisz; type "zjadłem banana".
**Why:** ADR-NET-009 (amended): a new thread from the diet is held in Jedzenie, and a reply's card stands in a thread too.
**Expected:** the thread shows "Jedzenie" under its title; the reply confirms the banana; under it the meal's card with Popraw and Cofnij; Rozmowy names the conversation "Jedzenie".
**On failure:** `ThreadNotifier._subject`; `actions` in the stream's `result` frame.

---

## When this plan is done

All cases are must-pass. T1, T3 and T5 need the owner (voice, the evening, typing); the agent drives T2 and T4 with `scripts/device-check/ui.py` and reads the dev PA.
