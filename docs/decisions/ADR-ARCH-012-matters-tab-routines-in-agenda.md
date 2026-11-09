# ADR-ARCH-012: Sprawy take the Routines tab; routines are managed inside the Agenda

Status: Accepted

Amends: ADR-ARCH-002 (the fourth branch of the shell is Matters, not
Routines).

## Context

Since R1 of personal-agent's master plan v2 every commitment is a routine
(ADR-CORE-116 of personal-agent), and the Agenda shows the routines due on a
day. The Routines tab then held only the management of routines: the list of
all of them, a new one, a routine's page. R3 added matters (ADR-CORE-118 of
personal-agent), reached from the Record and Chat app bars. After using
1.27.0 the owner decided (2026-11-09, workspace
`docs/requirements/off-roadmap/2026-11-09-phone-after-r3/source/2026-11-09-owner-request.md`):
"skoro agenda już teraz prezentuje tylko routines, to zarządzanie routines
usuńmy z dolnej belki i wrzućmy jako rozwijaną sekcję w agenda. Zamiast
routines dajmy sprawy do dolnej belki".

## Decision

1. **Branch 3 of the shell is Matters**: `/matters`, `/matters/new`,
   `/matters/:id`, the tab labelled "Sprawy". The matters' buttons on the
   Record and Chat app bars go: a route inside the shell cannot be pushed
   from another branch without building a second shell (the reason
   `/conversation/:id` exists). Choosing the tab reads the list again, as the
   push of its page did.
2. **Routines are managed in a folded section at the end of the Agenda**,
   on every day: the count of live routines in its title, "New routine", the
   groups the Routines tab had, and "Done and ended" folded inside it. Opening
   it reads the routines again; whether it is open is kept in a provider, so a
   change of day or a reload does not fold it. It shows in every state of the
   day, a failed or loading one included: routines are a separate endpoint
   and may answer when the agenda does not.
5. **The Agenda and the section tell each other of a change**, as two
   counters in `core/` (ADR-ARCH-008): the section bumps one after a new,
   paused or resumed routine or a return from its pages, and the Agenda reads
   the day again; the Agenda bumps the other after a tick, an undo or a pull,
   and the section reads the routines again.
3. **A routine's pages are children of the Agenda branch**:
   `/agenda/routines/new`, `/agenda/routines/:id`,
   `/agenda/routines/:id/edit`, so the bar stays visible as before.
   `/routines` redirects to `/agenda`, `/routines/:id` to
   `/agenda/routines/:id` and `/routines/:id/edit` to its form, for any old
   link.
4. **The features stay apart (ADR-ARCH-003).** `AgendaScreen` takes a
   `footer`, and the router passes `RoutinesSection` from the routines
   feature. The agenda feature imports nothing of routines.
   `RoutinesScreen` is removed.

## Consequences

- Matters are one tap away from anywhere, and the Record app bar has one
  icon fewer. Pins stay on the Record and Chat app bars.
- Managing routines takes one more tap (open the section), and the section
  sits below the day, so on a long day it is reached by scrolling.
- A matter's page is read again each time it is opened, as Sprawy are now
  opened more often; a pin's page likewise (its state is disposed with it).
- A test or a manual plan that names the Routines tab or `/routines` needs the
  new place; the plans of `docs/manual-tests/` written before this ADR keep
  the old wording as history.
