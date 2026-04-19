# Proposal 022 — Routines Screen

## Status: Stub

## Prerequisites
- P020 (Navigation Restructure) — provides /routines route placeholder
- personal-agent routine endpoints — must be deployed

## Scope
- Tasks: ~5
- Layers: features/routines (new), core/models, core/network
- Risk: Low — additive feature, no changes to existing features

---

## Problem Statement

Routines (recurring tasks with action item templates) are a core personal-agent feature, but voice-agent has zero visibility into them. Users cannot see active routines, approve AI-generated routine proposals, trigger manual occurrences, or track occurrence status from the mobile app.

## Design Direction

### Routines list screen (`/routines`)

```
[App Bar: "Routines"  | gear]

[Section: Proposals]  (if any — prominent card style)
  "Weekly meal planning"        suggested from conversation
  [Approve]  [Reject]  [View context]

[Tab bar: Active | Draft | Paused | Archived]

[Active tab:]
  Morning routine               daily @ 08:00     [next: tomorrow]
    - Meditate 10 min
    - Review daily plan
    [Trigger now]  [Pause]

  Weekly review                 weekly Mon @ 18:00 [next: Mon Apr 20]
    - Review completed items
    - Plan next week
    [Trigger now]  [Pause]
```

### Routine detail screen (`/routines/:id`)

```
[App Bar: "Morning routine"  | edit | archive]

[Status badge: Active]
[Schedule: daily @ 08:00]
[Next occurrence: tomorrow, Apr 19]

[Section: Action Item Templates]
  1. Meditate 10 min
  2. Review daily plan
  3. Check calendar

[Section: Recent Occurrences]
  Apr 18  done     ✓
  Apr 17  done     ✓
  Apr 16  skipped  —
  Apr 15  done     ✓
```

### API endpoints consumed
- `GET /api/v1/routines?status=active|draft|paused|archived` — list routines
- `GET /api/v1/routines/{id}` — routine detail with templates
- `GET /api/v1/routines/{id}/occurrences` — occurrence history
- `POST /api/v1/routines/{id}/activate|pause|archive` — status changes
- `POST /api/v1/routines/{id}/trigger` — manual trigger
- `PATCH /api/v1/routines/{id}/occurrences/{occ_id}` — update occurrence status
- `GET /api/v1/routine-proposals` — AI-proposed routines
- `POST /api/v1/records/{id}/approve-as-routine|reject` — approve/reject proposals

### Key interactions
- Proposals section at top when pending proposals exist
- Tab bar filters by routine status
- Tap routine → detail with occurrence history
- Swipe to pause/archive
- "Trigger now" creates ad-hoc occurrence
- Approve proposal → routine created, moves to Active tab

## Tasks (rough)
1. Core models: Routine, RoutineTemplate, RoutineOccurrence, RoutineProposal
2. API client: add routine endpoint methods
3. Routines list feature: domain, data (repository), presentation (controller + screen)
4. Routine detail screen with occurrences
5. Proposal approval flow (approve/reject with confirmation)
