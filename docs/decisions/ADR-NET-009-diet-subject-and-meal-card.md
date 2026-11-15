# ADR-NET-009: the diet's screens are Jedzenie; a meal a reply logged stands as a card with Popraw and Cofnij

Status: Accepted

## Context

personal-agent answers an utterance said on the diet in the subject Jedzenie
(its ADR-API-127): the day in the prompt, the diet's tools, a meal said as
eaten logged at once and only confirmed. It also carries on the reply what
the turn did (`actions`), so the phone can show it. The owner asked for the
screen to show the action, not only the words, with a correction and an undo
(workspace `docs/discussions/2026-11-va-meals-dashboard/`, source M7; draft
10 §4: "Undo is what makes acting without asking safe"). The design note is
the workspace's off-roadmap task `2026-11-15-diet-action-first`,
`drafts/01-action-contract.md`.

## Decision

1. **The diet's screens are Jedzenie.** `/diet` and its children (the menu,
   the own meals, the target) give the subject `diet`, read when an utterance
   ends as ADR-NET-008 reads a matter's; with the app hidden or the phone
   locked it is Dzień. A transcript keeps it as `diet`.
2. **What a reply did is kept beside it.** The sync worker reads the voice
   response's `actions` into `latestAgentActionsProvider` (core), set with
   each spoken reply, `[]` when the reply did nothing with a card. Only the
   kinds the app knows are read (`meal_logged`); the rest are skipped.
3. **The card.** The conversation field shows a card per action under the
   reply on a screen that gives it a card builder: the diet's day. A meal's
   card says what was logged, its estimate and what is left (red with the
   day's warning), with **Popraw** (the correction sheet of the day) and
   **Cofnij** (the meal removed). Either takes the card away and has the day
   read itself again; the day also reads itself after every agent turn.
4. **Elsewhere, no card.** On Dziś, a matter or with no screen, the reply's
   words say what was logged (both of personal-agent's prompts name the meal
   and the number); the meal is undone by voice or on the diet's day.

## Consequences

- A meal said on the diet is logged and undone without typing.
- Napisz on the diet's screens opens a new thread in Jedzenie
  (`/conversation/new?subject=diet`), as a matter's opens one on the matter,
  and a typed turn in a conversation held in Jedzenie carries the subject
  `diet` (V5 of the redesign; in V4 Napisz opened the current conversation
  and its typed turns carried no subject, so they went as Dzień).
- The cards stand under a reply in a typed thread too: the stream's `result`
  frame carries `actions` (personal-agent ADR-API-127), the thread keeps them
  by the reply's event id for the session, and the app hands the thread the
  same card builder as the field. A reloaded thread shows no card; the day
  shows the meal.
- An older personal-agent answers the subject `diet` with 400: the
  transcript fails at once with the error spoken (a permanent failure), as a
  matter's does. personal-agent and the app go out together, at the
  redesign's one merge.
