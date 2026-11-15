# Manual test: a matter to act from (V3 of the redesign)

**Design:** ADR-NET-008; personal-agent ADR-API-126; workspace `docs/requirements/off-roadmap/2026-11-15-va-matter-subject/` (design note `drafts/01-subject-contract.md`).
**Overall status:** pending
**Why now:** what is said on a matter's screen reaches personal-agent with the matter as its subject, and personal-agent then answers with another prompt and other tools. Unit, widget and HTTP tests cover the rule of the subject, the split of the voice session and the screens; only the phone shows a real utterance on a matter, a lock in the middle of a session and the model's answer.
**Time budget:** ~30 min, Pixel, dev flavor of the `nov26-redesign` branch (2.2.0+62), against the dev personal-agent on `:8898` (a copy of production), restarted on the V3 code.
**What we are testing:** that an entry, a task and what the matter waits for, said on a matter, land in it and are only confirmed; that what is not about the matter is handed over; that the matter's agenda adds, ticks off and removes tasks; that Back from a conversation returns to the matter; that a session paused on the matter and resumed with the phone locked talks as Dzień; that the matter's activity moves.

## Status legend

See the canonical legend in [`p040-agenda-notifications.md`](p040-agenda-notifications.md#status-legend).

## Status summary

| # | Case | Status |
|---|---|---|
| S1 | Dev PA on the V3 code, the dev app 2.2.0+62, a matter to test on | pending |
| T1 | The matter's screen tells the matter | pending |
| T2 | The matter's agenda: add, tick off, remove, each undone | pending |
| T3 | Said on the matter: an entry, a task, what it waits for, only confirmed | pending |
| T4 | Not about the matter: handed over to Dzień | pending |
| T5 | Napisz on the matter, and Back to it | pending |
| T6 | Paused on the matter, resumed with the phone locked: Dzień | pending |
| T7 | Rozmowy: the matter and the channel; the header opens the matter | pending |
| T8 | The matter's activity moves with its conversation | pending |

---

## Setup

### S1 — Dev PA on the V3 code, the dev app, a matter to test on

**Status:** pending

**Do:**
1. Restart the dev PA on `:8898` from the `nov26-redesign` worktree (`make pa-dev NAME=nov26-redesign`); its log shows the migration of `conversations.subject` once.
2. `make va-dev NAME=nov26-redesign` in the workspace root, the phone on USB; Settings shows 2.2.0+62 and the `:8898` URL.
3. In Sprawy open (or create) a matter for the test, e.g. "Remont łazienki", active.

**Expected:** the matter opens with the field at the bottom reading "Powiedz albo napisz w tej sprawie…".

---

## Cases

### T1 — The matter's screen

**Status:** pending
**Do:** open the matter from Sprawy, then from Dziś's matters.
**Why:** 04 §2 of the discussion; the owner's M6.
**Expected:** the state is a sentence ("W toku · ostatnio …"), then Następny krok and Czeka na, the agenda of the matter's tasks, one history of entries, ticks and conversations, the pins, and the field. Back from the matter opened over Dziś lands on Dziś.
**On failure:** `MatterDetailScreen`; `GET /api/v1/matters/{id}` and `GET /api/v1/routines?matter_id=` on the dev PA.

### T2 — The matter's agenda

**Status:** pending
**Do:** Dodaj zadanie "Kupić silikon", Jutro; swipe it right (Zrobione), Cofnij; swipe it left (Usuń), Cofnij; tap it.
**Why:** the owner's M6 ("móc dodać nowe zadanie lub usunąć stare"); ADR-API-126 §8.
**Expected:** the task shows with "jutro"; the dev PA holds a routine joined to the matter (`GET /api/v1/routines?matter_id=`); done and removed each leave the list with a Cofnij that brings it back; the tap opens the task and Back returns to the matter.
**On failure:** `MatterTasksNotifier`; `POST /api/v1/routines` with `matter_id` in the dev PA's log.

### T3 — Said on the matter (owner)

**Status:** pending
**Do:** on the matter, by the field's mic: "Kasia przysłała wycenę, dwanaście tysięcy"; "w poniedziałek zadzwonić do hydraulika"; "czekam na odpowiedź od hydraulika".
**Why:** ADR-API-126 §4: in Sprawa the agent acts at once and only confirms.
**Expected:** each reply is one sentence saying what was written, with no question; the history shows the entry and "Czeka na: …", the agenda shows the task on Monday; the dev PA's trace of each turn offers ten tools, not every tool.
**On failure:** the transcript's `subject` (`adb logcat`, the dev PA's log); `chattools.ToolsFor`; the turn trace (`chat_turn_traces`).

### T4 — Not about the matter (owner)

**Status:** pending
**Do:** on the matter, by the mic: "dopisz mleko do zakupów".
**Why:** ADR-API-126 §5: the hand-over.
**Expected:** the reply says it was added to the shopping list; Zakupy shows "mleko"; the dev PA's log has "handed over to day" for that turn; the matter has no new entry.
**On failure:** `ExecHandOver`, `mergeHandOver`; the trace shows `hand_over` then `add_shopping_item`.

### T5 — Napisz, and Back

**Status:** pending
**Do:** on the matter tap the field's keyboard, write "co jeszcze zostało do zrobienia?", send; Back. Then after a spoken reply tap "Otwórz rozmowę ›", Back.
**Why:** 04 §3 and §5; ADR-NET-008 §3.
**Expected:** the thread reads "Nowa rozmowa w tej sprawie", the answer comes from the matter's state (its tasks); after the send the header reads "Sprawa: …"; Back lands on the matter both times.
**On failure:** `ThreadScreen.matterId`, the `subject` of `POST /chat/stream` in the dev PA's log.

### T6 — Paused on the matter, the phone locked (owner)

**Status:** pending
**Do:** on the matter start listening, say one sentence about the matter; tap off (standby); lock the phone; resume from the notification (or the headset) and say "co mam jutro w kalendarzu?".
**Why:** the owner's M8 and M13 (10, item 2 (a)): with the phone locked an utterance is Dzień.
**Expected:** the answer is about tomorrow; Rozmowy shows two conversations: the matter's and a "Bez sprawy" one with the second sentence.
**On failure:** `utteranceSubjectReaderProvider` in `app.dart` (the lifecycle), `VoiceService.splitOnSubject` in the dev PA's log ("new session on a change of subject").

### T7 — Rozmowy and the header

**Status:** pending
**Do:** open Rozmowy; open the matter's conversation; tap its header.
**Why:** 07 §2; ADR-API-126 §7.
**Expected:** rows show the matter (or "Bez sprawy") and a mic or keyboard; the thread's header "Sprawa: …" opens the matter.
**On failure:** `GET /api/v1/conversations` (`subject`, `matter`, `channel`).

### T8 — The matter's activity

**Status:** pending
**Do:** with a matter whose last entry is older than 7 days, open it and say a question about it ("na czym stoimy?"), which writes nothing; go back to Sprawy and Dziś.
**Why:** ADR-API-126 §6 (C3).
**Expected:** the matter reads "W toku · ostatnio dziś" and counts among Dziś's matters in progress.
**On failure:** `matter.Service.lastTurn`, `matterTargets.ConversationLast`.

---

## When this plan is done

All cases are must-pass. T3, T4 and T6 need the owner's voice; the agent drives the rest with `scripts/device-check/ui.py` and reads the dev PA.
