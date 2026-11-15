# ADR-ARCH-013: The app opens on Dziś; Record leaves the shell and the mic lives in a field

Status: Accepted

Amends: ADR-ARCH-002 and ADR-ARCH-012 (the branches of the shell).

## Context

The owner found every interface of the system "techniczne": they do not tell
the day (workspace `docs/discussions/2026-11-va-meals-dashboard/`, source
M6). The discussion proposed a start screen that does, Dziś, and a layout in
which the microphone is a field on the screens rather than a tab of its own
(drafts 03 and 06 there); V1 of its cut builds them
(`docs/requirements/off-roadmap/2026-11-15-va-today/`). The day is composed
by personal-agent (`GET /api/v1/today`, ADR-API-124 of personal-agent).

Record held more than the button: the headset's and the volume keys'
gestures were wired in its state, and on iOS the tabs started and stopped the
session when Record was entered or left.

## Decision

1. **Five branches, in Polish**: Dziś `/today` (the start, and the initial
   location), Agenda `/agenda`, Sprawy `/matters`, Zakupy `/shopping`,
   Rozmowy `/chat`.
2. **Back on a tab's own screen goes to Dziś**, not out of the app. A
   notification's target, opened with `go` as before, thus has Dziś under it.
   The arrival alert's fallback route is `/today`.
3. **Record leaves the shell**: `/record` and its history are top-level,
   reached from Settings ("Nagrywanie i historia") as the diagnostics of the
   voice session and the phone's transcript queue.
4. **The voice inputs live in the shell** (`VoiceInputsHost`): the headset's
   and the volume keys' gestures and the listeners the mic needs, once for
   the app, not per screen.
5. **The mic is one widget** (`MicButton`) with the owner's rule: a tap
   switches listening on and off, a long press records while held. The
   conversation field (`ConversationField`) puts it at the bottom of Dziś and
   of the diet's day, with one line of state, the reply in place and "Otwórz
   rozmowę". Typing opens the conversation.
6. **The tabs never touch the microphone**, on iOS too (ADR-AUDIO-013 held it
   for Android): with Record no longer a tab, nothing starts a session but
   the mic, the headset, the glasses and the notification.
7. **A task and a matter opened from Dziś** are top-level routes
   (`/routine/:id`, `/matter/:id`), for the reason of `/conversation/:id`: a
   route inside the shell cannot be pushed from another branch. The diet's
   screens are top-level too (`/diet`, `/diet/menu`, `/diet/own-meals`,
   `/diet/target`); the top bar's first icon is Jedzenie.

## Consequences

- The app opens on the day, not on the mic. A session is started from the
  field; on iOS entering a tab no longer starts one.
- A task swiped on Dziś tells the Agenda through `agendaChangesProvider`
  (ADR-ARCH-008), as Shopping is told of a proposal.
- Rozmowy does not yet hold the transcript history; it stays with Record's
  diagnostics until the conversation list carries its channel (C4 of the
  discussion's 08, V3).
