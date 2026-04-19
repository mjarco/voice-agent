# Proposal 023 — Plan Screen

## Status: Stub

## Prerequisites
- P020 (Navigation Restructure) — provides /plan route placeholder
- personal-agent `GET /api/v1/plan` endpoint — must be deployed

## Scope
- Tasks: ~4
- Layers: features/plan (new), core/models, core/network
- Risk: Low — additive feature, no changes to existing features

---

## Problem Statement

The personal-agent global plan view shows all action items, standing rules, and completed items organized by topic. Voice-agent users have no access to this overview and must use the web UI to review, confirm, or dismiss knowledge records extracted from conversations.

## Design Direction

### Screen layout

```
[App Bar: "Plan"  | filter icon | gear]

[Section: Active Items]  (collapsible, default open)
  [Topic: "Health"]
    [ ] Schedule dentist appointment     [action_item]  [swipe: dismiss]
    [ ] Start running 3x/week           [suggestion]   [swipe: promote]
  [Topic: "Work"]
    [ ] Prepare Q2 presentation          [confirmed]    [swipe: done]

[Section: Standing Rules]  (collapsible)
  No meetings before 10am               [constraint]
  Prefer async communication             [preference]

[Section: Completed]  (collapsible, default collapsed)
  [x] Book flights for May trip          done 2d ago
```

### API endpoints consumed
- `GET /api/v1/plan` — full plan (active items, standing rules, completed)
- `POST /api/v1/records/{id}/done` — mark complete
- `POST /api/v1/records/{id}/dismiss` — dismiss
- `POST /api/v1/records/{id}/confirm` — confirm as committed
- `POST /api/v1/records/{id}/promote` — promote suggestion → action item
- `POST /api/v1/records/{id}/endorse` — toggle endorsement
- `POST /api/v1/records/{id}/postpone` — reschedule to future date
- `POST /api/v1/records/{id}/derive` — derive action item from decision

### Key interactions
- Swipe left/right for quick actions (done, dismiss)
- Long press → full action menu (confirm, promote, derive, postpone, endorse)
- Tap item → detail view with source conversation context
- Tap topic header → navigate to topic detail
- Filter by topic, record type
- Pull to refresh
- Record type badges with colors (action_item, suggestion, decision, constraint, preference)

### Offline behavior
- Cache plan data locally
- Queue record actions, sync when online

## Tasks (rough)
1. Core models: PlanResponse, KnowledgeRecord (shared with other features)
2. API client: add plan + record action endpoint methods
3. Plan feature: domain, data (repository), presentation (controller + screen)
4. Record action widgets (shared component for done/dismiss/promote/etc.)
