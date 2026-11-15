# ADR-NET-008: an utterance carries the subject of the screen it was said on

Status: Accepted

## Context

personal-agent answers an utterance by its subject (its ADR-API-126): on a
matter, with the matter's state and only the tools of matters and tasks; as
Dzień, with everything. The owner chose that an utterance takes the subject
of the screen in front when it is said, Dzień with the app hidden or the
phone locked (workspace `docs/discussions/2026-11-va-meals-dashboard/`,
draft 10, item 2, answered (a)). The voice session outlives the screen it was
started on, and a transcript may be sent long after it was said (offline, a
restart), so the subject cannot be read when it is sent. The design note is
workspace
`docs/requirements/off-roadmap/2026-11-15-va-matter-subject/drafts/01-subject-contract.md`.

## Decision

1. **The subject is read when an utterance ends**: the end of a hands-free
   segment, before its transcription, and the release of a held press. It is
   the matter whose screen is on top (`/matters/<id>` or `/matter/<id>`) while
   the app is resumed; otherwise Dzień.
2. **It is kept with the transcript** in a nullable `subject` column (database
   version 3), and the sync worker sends it as `subject` with the transcript.
   A transcript without one is Dzień.
3. **A typed thread opened on a matter** sends the subject with each turn;
   personal-agent keeps the conversation's subject for later turns.
4. **The subject is read through a core port**
   (`utteranceSubjectReaderProvider`), which the app wires to the router's
   location and the app's lifecycle, so the recording feature imports no
   other feature.

## Consequences

- A segment said on a matter and transcribed after the owner left it still
  lands in the matter; one said after the phone locked does not.
- The migration only adds a nullable column; a downgrade reads the table as
  before.
