# Proposal 022 — Routines Screen

## Status: Implemented

## Prerequisites
- P020 (Navigation Restructure) — provides `/routines` route and shell branch 3
- P025 (Shared API Layer) — provides `apiClientProvider` and core model conventions
- personal-agent routine endpoints deployed (routines, occurrences, proposals)

## Scope
- Tasks: ~4
- Layers: features/routines (new), app/router
- Risk: Low — additive feature replacing a placeholder, no changes to existing features

---

## Problem Statement

Routines (recurring tasks with action item templates) are a core personal-agent
feature, but voice-agent has zero visibility into them. Users cannot see their
active routines, review AI-generated routine proposals, trigger manual
occurrences, or track occurrence history from the mobile app. The only way to
interact with routines is through the personal-agent web UI or API directly.

The `/routines` tab currently shows a "Coming soon" placeholder, which is a dead
end in the navigation.

---

## Are We Solving the Right Problem?

**Root cause:** The voice-agent has no feature module for routines. The route
exists (P020) and the core models exist (P025), but there is no domain layer,
data layer, or presentation layer connecting them.

**Alternatives dismissed:**
- *Deep-link to personal-agent web UI:* Would work but breaks the native app
  experience and requires the user to context-switch. The whole point of
  voice-agent is a self-contained mobile interface.
- *Read-only list without actions:* Simpler, but routine management (pause,
  trigger, approve proposals) is the core value. A view-only list would feel
  incomplete and require a follow-up proposal immediately.

**Smallest change?** A full feature module is needed. The core models and API
client infrastructure already exist, so the actual work is the feature layer
(domain + data + presentation) plus route wiring. This is the minimal scope
that delivers value.

---

## Goals

- Users can browse routines filtered by status (active, draft, paused, archived)
- Users can view routine details: templates, schedule, and occurrence history
- Users can take actions: trigger now, pause, resume, archive
- Users can approve or reject AI-generated routine proposals
- The feature follows the established agenda feature pattern (domain/data/presentation)

## Non-goals

- Creating new routines from scratch (requires form UI — future proposal)
- Editing routine templates or schedules (requires edit flow — future proposal)
- Push notifications for routine occurrences
- Offline caching of routines (routines are always fetched fresh from API)
- Background sync or polling for routine state changes

---

## User-Visible Changes

The Routines tab (4th tab in bottom navigation) replaces the "Coming soon"
placeholder with a fully functional routines screen. Users see their routines
organized by status tabs, with a proposals section at the top when pending
AI-suggested routines exist. Tapping a routine opens a detail screen showing
action item templates and recent occurrence history. Users can trigger routines
manually, pause/resume them, and approve or reject AI proposals.

---

## Solution Design

### Architecture

Follow the agenda feature pattern exactly:

```
lib/features/routines/
  domain/
    routines_repository.dart     # Abstract interface
    routines_state.dart          # Sealed state classes
    routine_detail_state.dart    # Sealed state for detail screen
  data/
    api_routines_repository.dart # Implementation using ApiClient
  presentation/
    routines_screen.dart         # List screen (ConsumerStatefulWidget)
    routines_notifier.dart       # List controller (StateNotifier)
    routine_detail_screen.dart   # Detail screen
    routine_detail_notifier.dart # Detail controller
    routines_providers.dart      # All Riverpod providers
```

### Domain contracts

**RoutinesRepository** (abstract interface):

```
fetchRoutines(RoutineStatus status) → List<Routine>
fetchRoutineDetail(String id) → Routine
fetchOccurrences(String id) → List<RoutineOccurrence>
fetchProposals() → List<RoutineProposal>
activateRoutine(String id) → void
pauseRoutine(String id) → void
archiveRoutine(String id) → void
triggerRoutine(String id, String scheduledFor) → void
updateOccurrenceStatus(String routineId, String occurrenceId, OccurrenceStatus status) → void
approveProposal(String proposalId) → void
rejectProposal(String proposalId) → void
```

All methods throw `RoutinesException` on failure. `RoutinesException` is a
sealed class hierarchy defined in `routines_repository.dart` (domain layer):

```
sealed class RoutinesException implements Exception {
  String get message;
}
class RoutinesGeneralException extends RoutinesException {
  final String message;
  RoutinesGeneralException(this.message);
}
class RoutineAlreadyTriggedException extends RoutinesException {
  final String message;
  RoutineAlreadyTriggedException([this.message = 'Already triggered for this date']);
}
class RoutineConflictException extends RoutinesException {
  final String message;
  RoutineConflictException(this.message);
}
```

The data layer maps HTTP status codes to domain-meaningful subtypes: 409 on
trigger → `RoutineAlreadyTriggedException`, 409 on status change →
`RoutineConflictException`, all other errors → `RoutinesGeneralException`.
The domain layer never sees HTTP status codes — this preserves the ADR-NET-001
`ApiResult` abstraction boundary.

**Identity mapping for proposals:** `RoutineProposal.id` is the knowledge
record ID on the backend. The approve/reject endpoints use this same ID in
the path: `POST /records/{RoutineProposal.id}/approve-as-routine` (relative).

**RoutinesState** (sealed, for list screen):

```
RoutinesInitial
RoutinesLoading
RoutinesLoaded { routines: List<Routine>, proposals: List<RoutineProposal> }
RoutinesError { message: String }
```

**RoutineDetailState** (sealed, for detail screen):

```
RoutineDetailInitial
RoutineDetailLoading
RoutineDetailLoaded { routine: Routine, occurrences: List<RoutineOccurrence> }
RoutineDetailError { message: String }
```

### API mapping

All paths are **relative** (no `/api/v1` prefix). The `ApiClient.baseUrl`
already includes `/api/v1`, and `request()` composes as `'$baseUrl$path'`.
This matches P021's convention (e.g., agenda uses `/agenda`, not `/api/v1/agenda`).

| Repository method | HTTP call | Relative path | Response shape |
|---|---|---|---|
| fetchRoutines(status) | GET | /routines?status={status} | `data`: array of Routine (no templates) |
| fetchRoutineDetail(id) | GET | /routines/{id} | `data`: single Routine (with templates) |
| fetchOccurrences(id) | GET | /routines/{id}/occurrences | `data`: array of RoutineOccurrence |
| fetchProposals() | GET | /routine-proposals | `data`: array of RoutineProposal |
| activateRoutine(id) | POST | /routines/{id}/activate | updated Routine (ignored) |
| pauseRoutine(id) | POST | /routines/{id}/pause | updated Routine (ignored) |
| archiveRoutine(id) | POST | /routines/{id}/archive | updated Routine (ignored) |
| triggerRoutine(id, date) | POST | /routines/{id}/trigger | 201 Created / 409 Conflict |
| updateOccurrenceStatus(...) | PATCH | /routines/{routineId}/occurrences/{occId} | updated occurrence (ignored) |
| approveProposal(proposalId) | POST | /records/{proposalId}/approve-as-routine | 201 Created |
| rejectProposal(proposalId) | POST | /records/{proposalId}/reject | 200 OK |

**Response envelope.** All personal-agent endpoints wrap responses in
`{"data": ...}`. The repository must unwrap this envelope before parsing:
`(jsonDecode(body) as Map<String, dynamic>)['data']`. For list endpoints,
`data` is a JSON array; for detail/single endpoints, `data` is a JSON object.
This matches the agenda repository's `_parseResponse` pattern.

### Trigger request body

When triggering a routine, send:
```json
{
  "scheduled_for": "YYYY-MM-DD"
}
```
The `time_window` is derived server-side from the routine's rrule. The notifier
defaults `scheduledFor` to today's date (formatted as `yyyy-MM-dd`). The
repository method is a thin wrapper — no defaulting logic there.

### List screen behavior

- Default tab: Active (most common use case)
- Tab bar: Active | Draft | Paused | Archived
- Switching tabs calls `fetchRoutines(status)` for the selected status
- Proposals section appears above the tab bar only when proposals exist
- Each routine card shows: name, cadence display, next occurrence date.
  Templates are NOT included in the list endpoint response (the backend
  passes `nil` for templates in list calls), so routine cards do not show
  template previews. Templates are visible only on the detail screen.
- Actions per card: "Trigger now" (active only), status toggle button
  (Pause for active, Resume for paused)
- Empty state per tab: centered icon + message (e.g., "No active routines",
  "No paused routines"). No call-to-action since routine creation is a non-goal.
- Pull-to-refresh via `RefreshIndicator` reloads current tab + proposals

**Dual-fetch composition:** On initial load or refresh, the notifier fetches
routines and proposals concurrently. Do NOT use plain `Future.wait` (it rejects
on first failure). Instead, wrap the proposals future to catch errors and return
an empty list:

```
final routinesFuture = _repository.fetchRoutines(status);
final proposalsFuture = _repository.fetchProposals()
    .then((v) => v)
    .catchError((_) => <RoutineProposal>[]);
final results = await Future.wait([routinesFuture, proposalsFuture]);
```

If routines fail, the outer try/catch emits `RoutinesError`. If only proposals
fail, the load succeeds with an empty proposals list (proposals are supplementary).
When switching tabs, only re-fetch routines — proposals are retained from the
initial load.

### Detail screen behavior

- Shows full routine info: name, status badge, schedule (cadence + start_time),
  next occurrence
- Action item templates list (numbered, read-only)
- Recent occurrences list (most recent first, showing date + status)
- Action buttons in app bar or bottom: Activate (for draft/paused),
  Pause (for active), Archive (for non-archived), Trigger now (for active)
- After any action, reload the detail to reflect server state

**Navigation:** The detail screen receives only the routine ID via the route
path parameter (`/routines/:id`). It always fetches fresh data from the API.
The detail notifier fetches `fetchRoutineDetail(id)` and `fetchOccurrences(id)`
in parallel (`Future.wait`). If either fails, emit `RoutineDetailError`.

**List-detail state sync:** The list screen navigates to detail via
`await context.push('/routines/$id')`. When the push completes (user navigates
back), the list screen reloads the current tab. This is reliable because
`context.push` returns a `Future` that completes on pop. No route observer or
`didChangeDependencies` needed.

**Action busy state:** Mutation actions (trigger, pause, archive, activate)
return `Future<bool>` from the notifier, matching the agenda feature pattern.
While the future is pending, the action button shows a `CircularProgressIndicator`
and is disabled to prevent double-taps. The screen manages this via local
`setState` on the button, not via the sealed state.

For 409-specific feedback, the notifier catches `RoutineAlreadyTriggedException`
or `RoutineConflictException` and sets a `lastActionError` string field on the
notifier (not part of the sealed state). The screen reads this after `false` is
returned and shows it in a SnackBar. For generic errors, the notifier sets a
default message. On success, the detail is reloaded and `lastActionError` is
cleared.

### 409 Conflict handling

When `triggerRoutine` receives a 409, the data layer maps it to
`RoutineAlreadyTriggedException`. When a status change endpoint returns 409,
the data layer maps it to `RoutineConflictException`. The notifier catches
these sealed subtypes, sets `lastActionError` to the exception's `message`,
and returns `false`. The screen reads `lastActionError` and shows it in a
SnackBar. No HTTP status codes leak past the data layer.

### Proposal approval flow

- Proposal cards show: name, cadence, suggested items, confidence indicator
- "Approve" button calls `approveProposal(proposalId)`, then reloads list
- "Reject" button shows a confirmation dialog, then calls
  `rejectProposal(proposalId)`
- No inline editing of proposals before approval (non-goal)

### Route changes

Update `router.dart` to:
1. Replace `RoutinesPlaceholderScreen` with `RoutinesScreen` in branch 3
2. Add child route with relative path `:id` (not `/routines/:id`) inside the
   `/routines` GoRoute's `routes:` list, matching the existing pattern at
   `/record` → `'history'` → `':id'`

---

## Affected Mutation Points

All places that need change to wire in the routines feature:

**Needs change:**
- `router.dart` line 66-69 — replace placeholder with RoutinesScreen, add :id child route
- `router.dart` imports — replace placeholder import with routines feature imports

**No change needed:**
- `ApiClient` — generic methods already support all needed HTTP verbs
- `core/models/routine.dart` — models already exist with correct fromMap/toMap
- `core/providers/api_client_provider.dart` — already provides ApiClient
- `app_shell_scaffold.dart` — bottom nav already configured for 5 tabs

---

## Tasks

| # | Task | Layer |
|---|------|-------|
| T1 | Routines domain + data layer: repository interface, sealed states, API implementation, exception type, unit tests | features/routines/domain, data |
| T2 | Routines list screen: notifier, providers, screen with tab filtering and proposal cards, widget tests | features/routines/presentation |
| T3 | Routine detail screen: notifier, screen with occurrences and action buttons, route wiring, widget tests | features/routines/presentation, app/router |
| T4 | Proposal approval flow: approve/reject with confirmation dialog, integration with list reload, widget tests | features/routines/presentation |

### T1 details

- Create `lib/features/routines/domain/routines_repository.dart` — abstract
  interface with all 11 methods listed in Solution Design
- Create `lib/features/routines/domain/routines_state.dart` — sealed
  `RoutinesState` (Initial, Loading, Loaded, Error)
- Create `lib/features/routines/domain/routine_detail_state.dart` — sealed
  `RoutineDetailState` (Initial, Loading, Loaded, Error)
- Create `lib/features/routines/data/api_routines_repository.dart` — implements
  `RoutinesRepository` using `ApiClient`, pattern-matches on `ApiResult`,
  throws sealed `RoutinesException` subtypes on failure. Maps 409 on trigger
  to `RoutineAlreadyTriggedException`, 409 on status change to
  `RoutineConflictException`, all other errors to `RoutinesGeneralException`.
  Unwraps `{"data": ...}` response envelope before parsing (matching agenda
  repository pattern).
- Tests: repository unit tests with mocked ApiClient covering all 11 methods,
  success + error paths, JSON parsing, 409 → sealed RoutinesException subtypes

### T2 details

- Create `lib/features/routines/presentation/routines_notifier.dart` —
  `StateNotifier<RoutinesState>` with `loadRoutines(RoutineStatus)`,
  dual-fetch composition (routines + proposals in parallel via `Future.wait`),
  tab switching (re-fetches routines only, retains proposals), action methods
  returning `Future<bool>` with `lastActionError` for 409 feedback
- Create `lib/features/routines/presentation/routines_providers.dart` —
  `routinesRepositoryProvider`, `routinesNotifierProvider`
- Create `lib/features/routines/presentation/routines_screen.dart` —
  `ConsumerStatefulWidget` with TabBar, proposals section, routine list cards,
  empty state per tab, `RefreshIndicator` for pull-to-refresh, action button
  busy states via local `setState`
- Tests: notifier state transition tests with mocked repository (including
  partial failure: proposals fail but routines succeed → loaded with empty
  proposals), widget tests for screen rendering in each state including
  empty states

### T3 details

- Create `lib/features/routines/presentation/routine_detail_notifier.dart` —
  `StateNotifier<RoutineDetailState>` with `loadDetail(id)` (parallel fetch of
  routine + occurrences via `Future.wait`, error if either fails), action methods
  (activate, pause, archive, trigger, updateOccurrence) returning `Future<bool>`
  with `lastActionError` for 409 SnackBar feedback
- Create `lib/features/routines/presentation/routine_detail_screen.dart` —
  templates list, occurrences list, action buttons with busy states, receives
  routine ID from route path parameter (always fetches fresh)
- Update `router.dart`: replace placeholder import + builder, add
  `/routines/:id` child route pointing to `RoutineDetailScreen`
- Remove `app/placeholders/routines_placeholder_screen.dart` and its test
- Add list-detail sync: list screen uses `await context.push(...)` and reloads
  current tab after the future completes
- Tests: detail notifier tests, detail screen widget tests, router integration

### T4 details

- Add proposal card widget to routines screen with Approve/Reject buttons
- Approve calls `approveProposal(proposalId)` on notifier, reloads routines list
- Reject shows `AlertDialog` confirmation, then calls `rejectProposal(proposalId)`
- Add `approveProposal` and `rejectProposal` methods to `RoutinesNotifier`
- Tests: proposal card widget tests (tap approve, tap reject with dialog),
  notifier tests for approval/rejection flows

---

## Test Impact

### Existing tests affected

- `test/app/placeholders/routines_placeholder_screen_test.dart` — delete
  (placeholder is removed)
- `test/app/router_test.dart` (if exists) — update to expect RoutinesScreen
  instead of placeholder

### New tests

- `test/features/routines/data/api_routines_repository_test.dart` — all 11
  repository methods, success + failure paths, JSON parsing
- `test/features/routines/presentation/routines_notifier_test.dart` — state
  transitions: initial→loading→loaded, initial→loading→error, tab switching,
  proposal loading
- `test/features/routines/presentation/routines_screen_test.dart` — widget
  tests: loading spinner, loaded list, error with retry, empty state per tab,
  proposal section visibility
- `test/features/routines/presentation/routine_detail_notifier_test.dart` —
  load detail, action methods (activate, pause, archive, trigger), occurrence
  status update
- `test/features/routines/presentation/routine_detail_screen_test.dart` —
  widget tests: templates list, occurrences list, action buttons per status
- `test/features/routines/presentation/proposal_card_test.dart` — approve
  button, reject with confirmation dialog

Run: `flutter test test/features/routines/`

---

## Acceptance Criteria

1. Navigating to the Routines tab shows a list of routines fetched from
   `GET /routines?status=active` by default.
2. Tab bar filters routines by status (active, draft, paused, archived);
   switching tabs fetches the corresponding status from the API.
3. Each routine card displays name, cadence, and next occurrence date.
4. Tapping a routine card navigates to `/routines/:id` showing the detail screen.
5. Detail screen shows routine name, status badge, schedule info, full
   templates list, and recent occurrences with date and status.
6. "Trigger now" button on active routines calls
   `POST /routines/{id}/trigger` with today's date.
7. Pause/Resume/Archive buttons call the corresponding status change endpoint
   and reload the view.
8. When pending routine proposals exist, a proposals section appears above the
   tab bar showing proposal cards with Approve and Reject buttons.
9. Approve calls `POST /records/{id}/approve-as-routine` and reloads
   the routines list.
10. Reject shows a confirmation dialog; on confirm calls
    `POST /records/{id}/reject` and removes the proposal from the list.
11. API errors display an error state with a retry button.
12. When a status tab has zero routines, an empty state with descriptive
    message is shown (e.g., "No paused routines").
13. Pull-to-refresh reloads the current tab and proposals.
14. Triggering a routine that returns 409 shows a "Already triggered" SnackBar
    instead of a generic error.
15. Action buttons (trigger, pause, archive) show a loading indicator while
    the request is in flight and are disabled to prevent double-taps.
16. Navigating back from detail to list reloads the list to reflect any
    mutations made on the detail screen.
17. `flutter analyze` passes with zero issues.
18. `flutter test` passes with all tests green.
19. No cross-feature imports (features/routines/ imports only from core/).

---

## Risks

| Risk | Mitigation |
|------|------------|
| Backend routine endpoints not deployed | Feature degrades gracefully — shows API error with retry. Proposal lists prerequisites. |
| Large number of routines per status tab | No pagination in V1 — acceptable for personal use (unlikely to have hundreds). Add if needed later. |
| Trigger endpoint returns 409 (already triggered today) | Show user-friendly "Already triggered" message from the 409 response. |

---

## ADR Updates Required

### ADR-NET-001 Amendment: Domain exception pattern for HTTP error differentiation (P022)

When a feature's notifier must distinguish between different API failure modes
(e.g., 409 Conflict vs. generic error), the translation happens in the data
layer repository implementation:

- The feature defines a sealed exception hierarchy in `domain/` (e.g.,
  `RoutinesException` with subtypes `RoutinesGeneralException`,
  `RoutineAlreadyTriggedException`).
- The data layer maps `ApiPermanentFailure` with specific status codes to
  the corresponding domain exception subtype.
- The notifier pattern-matches on exception subtypes, never on HTTP status codes.

This preserves the `ApiResult` abstraction boundary: HTTP semantics stop at
the data layer, and the domain layer works with business concepts.

---

## Alternatives Considered

No new architectural patterns introduced beyond the sealed domain exception
hierarchy (documented as an ADR-NET-001 amendment above). The feature structure
follows P021 (Agenda): abstract repository, sealed states, StateNotifier
controller, ConsumerStatefulWidget screen. Patterns are established in
ADR-ARCH-003 and ADR-NET-001.

---

## Known Compromises and Follow-Up Direction

### No pagination (V1 pragmatism)
The list screen fetches all routines for a given status in one call. For a
personal agent with tens of routines, this is fine. If routine counts grow
significantly, add `limit`/`offset` query parameters (the backend would need
to support this too).

### No offline caching (V1 pragmatism)
Unlike the agenda feature which caches responses to files, routines are fetched
fresh every time. Routines change less frequently than daily agendas, and the
list is small enough that re-fetching is fast. Add file-based caching if users
report sluggish tab switching.

### No routine creation or editing
Users can only view and manage existing routines. Creating and editing routines
requires form UI with rrule configuration, which is complex enough to warrant
its own proposal.

### Emerging pattern: feature detail screens
After P022, three features will have list→detail navigation (history, agenda
occurrences, routines). If a fourth appears, consider extracting a shared
`DetailScaffold` widget with common patterns (app bar actions, status badges,
reload behavior).
