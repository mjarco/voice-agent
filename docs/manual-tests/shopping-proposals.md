# Manual test: shopping proposals on the phone

**Design:** [voice-agent#372](https://github.com/mjarco/voice-agent/issues/372); personal-agent ADR-API-108.
**Overall status:** pending
**Why now:** the lab drives the server's chat stream, not the app, so nothing else exercises the card. The hands-free case is also the first device check of the voice rule ADR-API-108 expects: a purchase said aloud is asked about aloud, and no card follows it.
**Time budget:** ~15 min, Pixel, stable flavor, against production personal-agent.
**What we are testing:** that a purchase said in a conversation reaches the card, that the answer changes the list, that a reopened thread shows what became of it, and that a proposal made by voice waits on the Shopping tab.

## Status legend

See the canonical legend in [`p040-agenda-notifications.md`](p040-agenda-notifications.md#status-legend).

## Status summary

| # | Case | Status |
|---|---|---|
| S1 | Install 1.11.0+25 | pending |
| T1 | A purchase said in the chat shows a card | pending |
| T2 | Add puts the item on the list | pending |
| T3 | A reopened thread shows the state | pending |
| T4 | Skip leaves the list alone | pending |
| T5 | Tick off an item on the list | pending |
| T6 | Answered on the web first | pending |
| T7 | A purchase said hands-free waits on the tab | pending |
| T8 | Answering on the tab | pending |

---

## Setup

### S1 — Install

**Status:** pending

**Do:**
1. Connect the Pixel over adb. Copy `.env.mobile` into the worktree if it is missing.
2. `make install-android`.
3. Settings shows 1.11.0+25.

---

## Test cases

### T1 — A purchase said in the chat shows a card

**Status:** pending

**Do:**
1. Open a new chat.
2. Send a message mentioning a purchase without asking for it, as in "kończy mi się filtr do wody".

**Why:** ADR-API-108: a purchase in a conversation is proposed, not done. The card comes from the read by `conversation_id`, with the `result` frame as the fallback.

**Expected:** under the reply, "Add to shopping: filtr do wody" with Skip and Add. The item is not on the list yet.

**On failure:** if the agent said nothing about buying, the model made no proposal: open the thread on the web and see whether a card shows there. If it does, look at `GET /shopping/proposals?conversation_id=` in `ThreadNotifier._readProposals`, which fails silently by design.

### T2 — Add puts the item on the list

**Status:** pending

**Do:**
1. Tap Add on the card from T1.
2. Open the Shopping tab.

**Why:** the answer is a transaction on the server, and the tab stays alive without polling, so the chat has to tell it (`shoppingListChangesProvider`).

**Expected:** the card says "added", without buttons. The tab shows the item under To buy, tagged within seconds after a pull to refresh at the latest.

**On failure:** an item missing until a pull to refresh means the counter or `ref.listen` in `ShoppingScreen` did not fire.

### T3 — A reopened thread shows the state

**Status:** pending

**Do:**
1. Leave the thread and reopen it from the list.

**Why:** issue #372: a reopened thread shows the real state, not the buttons again.

**Expected:** the card under the same reply says "added".

**On failure:** a card missing altogether: look at `user_event_id` against the thread's events in `_proposalsByAnchor`.

### T4 — Skip leaves the list alone

**Status:** pending

**Do:**
1. Make another proposal as in T1.
2. Tap Skip.

**Why:** ADR-API-108: skip answers no and changes nothing.

**Expected:** the card says "skipped", the list is unchanged.

**On failure:** look at the state of the proposal on the web.

### T5 — Tick off an item on the list

**Status:** pending

**Do:**
1. Send "kupiłem filtr do wody", with the item from T2 on the list.
2. Tap Tick off.

**Why:** the `bought` kind, with its own wording.

**Expected:** "Tick off: filtr do wody" with Skip and Tick off; after the tap "ticked off", and the item moves to Bought with `via=chat`.

**On failure:** the proposal may have been an add, if the model did not match the item: read the card's first line.

### T6 — Answered on the web first

**Status:** pending

**Do:**
1. Make a proposal as in T1 and leave the thread open on the phone.
2. Answer it Skip on the web.
3. Tap Add on the phone.

**Why:** `409 proposal_not_waiting` carries the state, and the card shows what happened instead of an error.

**Expected:** the card says "skipped". The item is not added.

**On failure:** "Failed: …" on the card means `_conflict` in `ApiShoppingProposals` did not recognize the body.

### T7 — A purchase said hands-free waits on the tab

**Status:** pending

**Do:**
1. Start a hands-free session on the Record tab.
2. Say "kończy mi się mleko" and listen to the answer.
3. Open the Shopping tab.

**Why:** ADR-API-108: `/voice/transcript` carries no field, so there is no card to answer; the agent has to ask aloud and the proposal waits. This is its first run on a device.

**Expected:** the agent asks about it aloud. The card is at the top of To buy without a pull to refresh.

**On failure:** a spoken answer without a card means no proposal was made: judge the model's turn on the web. A card only after a pull to refresh means the refresh on opening the tab did not fire.

### T8 — Answering on the tab

**Status:** pending

**Do:**
1. Tap Add on the card from T7.

**Why:** the same card and the same answer on the other screen.

**Expected:** the card goes and the item is on the list.

**On failure:** look at `ShoppingNotifier.answerProposal`.

---

## When this plan is done

All cases are must-pass. A failure of T7 caused by what the model said, and not by the app, is recorded here and goes to the lab.
