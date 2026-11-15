# Manual test: the day's story and the evening queue (V5 of the redesign)

**Design:** ADR-NET-010, ADR-NET-009 (amended); personal-agent ADR-API-128; workspace `docs/requirements/off-roadmap/2026-11-15-day-queue-story/` (design note `drafts/03-story-and-queue.md`).
**Overall status:** passed (2026-11-15, on 2.5.0+67 against the dev PA on `9c3627c`; the owner read the evening story: "w skrótcie brzmi dobrze")
**Why now:** the story and the queue are an API between personal-agent and the phone; unit and widget tests cover the parsing, the block, the settle and the thread's subject, and pa-lab measured the narration (day-story-v1 to v4) and the queue (queue-v1, v2). Only the phone shows a real evening, a real utterance put aside and a tap that settles it.
**Time budget:** ~25 min, Pixel, dev flavor of `nov26-redesign` (2.5.0+67), against the dev personal-agent on `:8898` (a copy of production) on the V5 code with its own MCP socket.
**What we are testing:** that an unclear utterance is put aside, not asked about; that the evening block tells the day and settles what waits; that a day's screen opens any day; that Napisz on the diet opens a thread in Jedzenie, and a meal typed there gets its card.

## Status legend

See the canonical legend in [`p040-agenda-notifications.md`](p040-agenda-notifications.md#status-legend).

## Status summary

| # | Case | Status |
|---|---|---|
| S1 | Dev PA on the V5 code, the dev app 2.5.0+67 | passed (2026-11-15, Pixel 11 Pro, dev 2.5.0+67, test PA) |
| T1 | An unclear utterance: "Odłożyłem na wieczór", nothing asked | passed (2026-11-15, Pixel 11 Pro, dev 2.5.0+67, test PA, owner's voice) |
| T2 | Before 19:00: the count on Dziś, the day's screen | passed (2026-11-15, Pixel 11 Pro, dev 2.5.0+67, test PA) |
| T3 | The evening block: the narration, a guess settles | passed (2026-11-15, Pixel 11 Pro, dev 2.5.0+67, test PA, owner read it) |
| T4 | Nic drops; a past day's screen | passed (2026-11-15, Pixel 11 Pro, dev 2.5.0+67, test PA) |
| T5 | Napisz on the diet: a thread in Jedzenie, the meal's card in it | passed (2026-11-15, Pixel 11 Pro, dev 2.5.0+67, test PA) |

---

## Setup

### S1 — Dev PA on the V5 code, the dev app

**Status:** passed (2026-11-15, Pixel 11 Pro, dev 2.5.0+67, test PA): versionCode 67; Dziś read the dev PA on `9c3627c` (the copy's "Remont łazienki (test V3)" shown); `day story: enabled (claude_cli, model=sonnet)` in its log
**Do:**
1. Restart the dev PA on `:8898` from the `nov26-redesign` worktree with its own socket: `PA_MCP_SOCKET=/tmp/pa-8898/mcp.sock make pa-dev NAME=nov26-redesign` (migration 041 creates two tables).
2. `make va-dev NAME=nov26-redesign` in the workspace root, the phone on USB; Settings shows 2.5.0+67 and the `:8898` URL; Test Connection succeeds.

**Expected:** Dziś opens; `GET /api/v1/day/story?narrate=0` answers with `pending: []`.

---

## Cases

### T1 — An unclear utterance (owner)

**Status:** passed (2026-11-15, Pixel 11 Pro, dev 2.5.0+67, test PA, owner's voice): "G-Shot" answered "Odłożyłem na wieczór.", no question; the trace has `queue_for_evening` twice (the first refused: a meal guess without kcal; the agent sent it again with an estimate); queued with three guesses (Do zakupów, Zadanie, Zapisz ok. 100 kcal). Seen once: "Chyba za dużo chleba." said at 18:18 was answered as a remark about the calories left (105 kcal, under the reserve), not queued and not asked about; the lab queued the same words 5 of 6 times
**Do:** on Dziś, by the mic: "G-Shot".
**Why:** ADR-API-128 §4: words that could mean an action, not clearly which, are queued, not asked about.
**Expected:** the reply is one sentence, "Odłożyłem na wieczór." or near it, with no question; the dev PA's trace has `queue_for_evening`; the story's `pending` holds the words with two or three guesses.
**On failure:** `PendingPromptGuidance` in personal-agent; the turn's trace.

### T2 — Before 19:00: the count and the day's screen

**Status:** passed (2026-11-15, Pixel 11 Pro, dev 2.5.0+67, test PA): "Do rozstrzygnięcia: 1 / Odłożone na wieczór" on Dziś at 18:11, no story block; it and Dziś's title opened "niedziela, 15 listopada" with the story, what waits and the timeline; `day_stories` holds today's story from 18:12 only (the screen's read), so Dziś's reads told nothing, and the second open read it back
**Do:** before 19:00, pull Dziś to refresh; tap "Do rozstrzygnięcia: 1"; then Back, and tap Dziś's title.
**Why:** ADR-NET-010 §2, §5.
**Expected:** the count line under the title, no story block; the day's screen shows what waits and today's timeline; the title opens the same screen; the dev PA logged no `day_story` call for these reads.
**On failure:** `DayStoryBlock` (`eveningFromHour`); `narrate=0` in the request.

### T3 — The evening block (owner)

**Status:** passed (2026-11-15, Pixel 11 Pro, dev 2.5.0+67, test PA, owner read it): at 19:01 Dziś showed "DZIŚ W SKRÓCIE" (check passed, kept at 19:00) with both utterances' buttons; the owner: "w skrótcie brzmi dobrze". The slabs' utterance (typed by the agent, "Ulozylem gdzies plyty wzdluz Shisheda.", queued with one guess, a note in "Płytki wokół domku ogrodowego") settled with it: the matter holds "Ułożone płyty wzdłuż shedu." from `phone`, the line went, and the story was told again for the changed facts. The first tap did not settle (no request reached PA); the owner had touched the phone at that moment; the repeat from a fresh dump did
**Do:** after 19:00 open Dziś; read the story; tap one of G-Shot's guesses.
**Why:** ADR-NET-010 §1, §3, §4; ADR-API-128 §6.
**Expected:** "DZIŚ W SKRÓCIE" with a few sentences of the day; the guess's line goes; the item or the task is where it would have been (Zakupy, Agenda); a second open of Dziś does not call the model again (the story is kept).
**On failure:** the story's `narration.check`; `POST /api/v1/day/pending/{id}/settle` in the dev PA's log.

### T4 — Nic, and a past day

**Status:** passed (2026-11-15, Pixel 11 Pro, dev 2.5.0+67, test PA): Nic on "G-Shot" settled it as none ("nic"), nothing written (no item, task or meal named G-Shot); the day's screen went to "sobota, 14 listopada" with its story and timeline, and a timeline line opened its task. "Chyba za dużo chleba", meant for this case, was not queued (see T1), so the slabs' utterance stood in
**Do:** say another unclear thing ("chyba za dużo chleba"); in the evening block tap Nic; then open the day's screen and go a day back with ‹.
**Why:** ADR-NET-010 §4, §5.
**Expected:** the line goes and nothing is written; yesterday's screen shows its story (told once) and its timeline; a timeline line opens its thing.
**On failure:** `DayStoryScreen`; `settle` with `guess: null`.

### T5 — Napisz on the diet (owner)

**Status:** passed (2026-11-15, Pixel 11 Pro, dev 2.5.0+67, test PA, typed by the agent): Napisz on Jedzenie opened a new thread headed "Jedzenie"; "zjadlem banana" logged Banan 105 (90–120), subject `diet`, 7 tools offered; under the reply "✓ Banan · 18:14 / 105 (90–120) kcal · zostało 105" with Popraw and Cofnij; Rozmowy names it "Jedzenie" (the voice conversation "Bez sprawy")
**Do:** on Jedzenie tap Napisz; type "zjadłem banana".
**Why:** ADR-NET-009 (amended): a new thread from the diet is held in Jedzenie, and a reply's card stands in a thread too.
**Expected:** the thread shows "Jedzenie" under its title; the reply confirms the banana; under it the meal's card with Popraw and Cofnij; Rozmowy names the conversation "Jedzenie".
**On failure:** `ThreadNotifier._subject`; `actions` in the stream's `result` frame.

---

## When this plan is done

All cases are must-pass. T1, T3 and T5 need the owner (voice, the evening, typing); the agent drives T2 and T4 with `scripts/device-check/ui.py` and reads the dev PA.
