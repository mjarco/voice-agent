# ADR-NET-010: the day's story on Dziś, and the evening queue settled there

Status: Accepted

## Context

personal-agent ADR-API-128 tells a day's story from its facts (a narration by
the `day_story` model, its numbers checked, kept per facts) and keeps what the
agent could not act on in a queue, with up to three guesses each, settled by
`POST /api/v1/day/pending/{id}/settle`. The owner read six of his days told
that way and asked for it as a daily ritual, "gdyby opisy były mniej suche"
(workspace off-roadmap task `2026-11-15-day-queue-story`, V5-2, V5-3; design
note `drafts/03-story-and-queue.md`).

## Decision

1. **On Dziś from 19:00** a block above the food: "DZIŚ W SKRÓCIE", the
   narration, "DO ROZSTRZYGNIĘCIA · n" with a button per guess (its
   `label`) and Nic, and "Oś dnia ›". The story is read with the narration
   (`GET /api/v1/day/story?day=`).
2. **Before 19:00** the story is read without the narration (`narrate=0`, no
   model call) and Dziś shows only "Do rozstrzygnięcia: n" when anything
   waits, opening the day.
3. **A narration is shown only when its check passed**; otherwise the block
   holds what waits and the way to the timeline.
4. **Settling.** A guess's button settles with its index, Nic with `null`.
   The line goes at once; a failure brings it back with a message. A guess
   that ran tells the app a turn changed the day (`agentTurnsProvider`), so
   Dziś and the diet read again.
5. **A day's screen** `/day/:date` (outside the shell): the narration, what
   waits, and the whole timeline, each line opening its thing (a meal the
   diet, a matter, a conversation, a task); arrows go a day back and forth.
   It opens from Dziś's title and from the block.
6. The story is read again after every answered turn, which may have queued
   an utterance.

## Consequences

- Nothing is pushed: the evening is when the owner opens Dziś.
- The words of the buttons are personal-agent's; the phone draws them.
- The story of today in the evening costs a model call only when the day
  changed since it was last told.
