# Proposal 023 — Plan Screen

## Status: Implemented

## Prerequisites
- P020 (Navigation Restructure) — provides `/plan` route with `PlanPlaceholderScreen`
- P022 (Routines Screen) — establishes feature layer pattern followed here
- `GET /api/v1/plan` and `POST /api/v1/records/{id}/*` endpoints — operational in personal-agent

## Scope
- Tasks: ~2
- Layers: features/plan (new), core/models (read-only), app/router
- Risk: Low — additive feature, follows P022 pattern exactly

---

## Problem Statement

Voice-agent users see a placeholder tab for "Plan" that does nothing. The personal-agent backend exposes a full global plan view (`GET /api/v1/plan`) with active action items, standing rules (constraints/preferences/decisions), and completed items organised by topic. Users must open the web UI to review or act on extracted knowledge records — there is no mobile access.

---

## Are We Solving the Right Problem?

**Root cause:** The `/plan` route was added as a placeholder in P020. The backend plan API is fully implemented and battle-tested. The gap is purely in the mobile client.

**Alternatives dismissed:**
- *Surfacing plan data in the agenda tab:* The agenda is date-scoped; the plan is timeless. Merging them would collapse two distinct mental models.
- *Read-only view first, actions later:* Actions (done, dismiss, promote, confirm, endorse) are the primary value — a read-only plan list has low utility. Implemented together in V1.

**Smallest change?** Two tasks matching the P022 split (domain+data / presentation) is the minimum mergeable path. Offline caching and action queuing are explicitly deferred.

---

## Goals

- Display all active plan entries grouped by topic with record-type badges
- Display standing rules (constraints, preferences, decisions) in a separate collapsible section
- Allow inline record actions: done/dismiss (all active entries), confirm (candidate only), endorse (all rules)
- Show completed items in a collapsed section
- Pull to refresh

## Non-goals

- Offline caching or action queuing (network-connected only in V1)
- Postpone action (requires date picker — separate follow-up)
- Derive action (requires text input — separate follow-up)
- Harden/relax actions (advanced, low demand)
- Topic detail navigation screen
- Filter UI by topic or record type

---

## User-Visible Changes

The "Plan" tab (previously a placeholder) shows all knowledge extracted from conversations: active entries grouped by topic with trust-level badges (committed/candidate/proposed), a collapsible Rules section (constraints, preferences, decisions), and a collapsible Completed section. Committed entries show Done and Dismiss; candidate/proposed entries additionally show Confirm. Rules show Dismiss and Endorse. Pull to refresh reloads from the backend.

---

## Solution Design

### API contract

**Fetch:**
```
GET /api/v1/plan
→ 200 {"data": {
    "topics": [{"topic_ref", "canonical_name", "items": [ActiveEntry]}],
    "uncategorized": [ActiveEntry],
    "rules": [{"topic_ref", "canonical_name", "items": [RuleEntry]}],
    "rules_uncategorized": [RuleEntry],
    "completed": [{"topic_ref", "canonical_name", "items": [ActiveEntry]}],
    "completed_uncategorized": [ActiveEntry],
    "total_count": int,
    "observed_at": timestamp
  }}

ActiveEntry (JSON shape, maps to PlanEntry): {entry_id, display_text, plan_bucket?, confidence, conversation_id, created_at, closed_at?}
RuleEntry  (JSON shape, maps to PlanEntry): {entry_id, record_type, display_text, confidence, conversation_id, created_at}
```

Both JSON shapes map to the single existing Dart type `PlanEntry` — `planBucket` is non-null for active/completed entries, `recordType` is non-null for rules, the other is null. No new top-level model classes are needed; `PlanBucket` and `RecordType` enums are added to `plan.dart` as typed representations of these string fields.

`plan_bucket` values for active/completed entries: `committed`, `candidate`, `proposed`.
`record_type` values for rules: `constraint`, `preference`, `decision`.

Note: `globalPlanEntryResponse` does NOT include `record_type` for active entries. Action button logic must branch solely on `plan_bucket`.

**Actions** (all POST, no request body, wrapped in `{"data": ...}`):
```
POST /api/v1/records/{id}/done      → 200 {record_id, closed_at}
POST /api/v1/records/{id}/dismiss   → 200 {record_id, closed_at}
POST /api/v1/records/{id}/confirm   → 200 {record_id, plan_bucket}
POST /api/v1/records/{id}/endorse   → 200 {record_id, user_endorsed}
```

409 (`invalid_lifecycle_transition`) → `PlanConflictException("Action not available for this item")`. The backend error body is **not** accessible through `ApiClient` (non-2xx bodies are discarded; only `response.statusMessage` is available). The hardcoded message avoids exposing an empty or HTTP-phrase-only string to the user.

Response bodies are intentionally discarded — after every successful action the notifier calls `load()` for a full refresh.

### Existing models

`lib/core/models/plan.dart` already has `PlanResponse`, `PlanTopicGroup`, `PlanEntry` with correct `fromMap`/`toMap`. No changes needed. `PlanEntry.planBucket` covers active items; `PlanEntry.recordType` covers rules (both fields optional, one set per entry type).

### Feature layer structure

```
lib/features/plan/
  domain/
    plan_repository.dart       # abstract + PlanException hierarchy
    plan_state.dart            # PlanInitial | PlanLoading | PlanLoaded | PlanError
  data/
    api_plan_repository.dart   # implements PlanRepository via ApiClient
  presentation/
    plan_notifier.dart         # StateNotifier<PlanState>
    plan_providers.dart        # planRepositoryProvider, planNotifierProvider
    plan_screen.dart           # ConsumerStatefulWidget
```

### State machine

`PlanNotifier` starts in `PlanInitial`, calls `load()` in constructor:
- `load()`: clears `lastActionError = null`, sets `PlanLoading` → fetches → `PlanLoaded(response)` or `PlanError(message)`. Clearing on load prevents stale error messages from persisting after a successful pull-to-refresh.
- `refresh()`: identical to `load()` — resets to `PlanLoading` (same as P022 `RoutinesNotifier.refresh()`). `PlanScreen` ties `RefreshIndicator.onRefresh` to the `Future` returned by `refresh()`; the `RefreshIndicator` spinner handles the in-progress indication independently.
- Action methods: `Future<bool>` + `lastActionError` pattern (identical to P022). Each action method also clears `lastActionError = null` at the top before attempting the call.
- After successful action: call `load()` to refresh the plan (causes `PlanLoading` flash — acknowledged in Known Compromises)

### UI layout

```
AppBar: "Plan"  | gear icon → /settings

Section: Active Items (N)          [chevron toggle]
  [Topic: Health]
    committed   Schedule dentist       [Done] [Dismiss]
    candidate   Start running 3x/w    [Confirm] [Done] [Dismiss]
  [Uncategorized]
    proposed    Prep Q2 deck           [Done] [Dismiss]

Section: Rules (N)                 [chevron toggle]
  [Topic: Work]
    decision    No Jira for small tasks    [Dismiss] [Endorse]
    constraint  No meetings before 10am   [Endorse]
    preference  Prefer async comms         [Endorse]

Section: Completed (N)             [chevron toggle — collapsed by default]
  [done items, display_text only, no badges, no action buttons]

When any section has no items, show inline text "No items" within that section.
Section counts in headers are computed from each section's entry arrays
(not from PlanResponse.totalCount, which only counts active action items).
```

Action buttons per `plan_bucket` (active entries):
- `committed`: Done + Dismiss
- `candidate`: Confirm + Done + Dismiss — `confirm` is valid for `heuristic_candidate` action items, which map to the `candidate` plan_bucket
- `proposed`: Done + Dismiss only — `proposed` comes from `agent_proposed` kind, which the backend rejects with 409 on confirm

Action buttons per `record_type` (rules — backend lifecycle constraints verified):
- `decision`: Dismiss + Endorse (decisions are dismissible)
- `constraint` or `preference`: Endorse only (Dismiss rejected by backend → 409)

**Endorse semantics:** `POST /records/{id}/endorse` toggles endorsement server-side on every call. `globalPlanEntryResponse` does not include `user_endorsed`, so the plan view cannot reflect endorsement state after refresh — the Endorse button is a fire-and-forget signal with no visual toggle state in V1. This is acknowledged in Known Compromises.

### Error handling

`PlanException` sealed hierarchy:
- `PlanGeneralException(message)` — catch-all
- `PlanConflictException(message)` — HTTP 409

`ApiPlanRepository` maps `ApiPermanentFailure` with status 409 → `PlanConflictException`; all others → `PlanGeneralException`.

---

## Affected Mutation Points

**Needs change:**
- `lib/app/router.dart` — replace `PlanPlaceholderScreen` import and usage with `PlanScreen`
- `lib/app/placeholders/plan_placeholder_screen.dart` — delete

**New:**
- `lib/features/plan/domain/plan_repository.dart`
- `lib/features/plan/domain/plan_state.dart`
- `lib/features/plan/data/api_plan_repository.dart`
- `lib/features/plan/presentation/plan_notifier.dart`
- `lib/features/plan/presentation/plan_providers.dart`
- `lib/features/plan/presentation/plan_screen.dart`

**Needs change:**
- `lib/core/models/plan.dart` — add `PlanBucket` and `RecordType` enums; update `PlanEntry` to use typed fields instead of `String?` for `planBucket` and `recordType`. This keeps widget action-button branching on typed values rather than raw string literals, matching the `RoutineStatus` enum pattern from P022.

**No change needed:**
- `lib/core/network/api_client.dart` — generic HTTP methods are sufficient

---

## Tasks

| # | Task | Layer |
|---|------|-------|
| T1 | Domain + data: `PlanRepository`, `PlanException` hierarchy, `PlanState`, `ApiPlanRepository` with plan fetch and all 5 record actions; repository unit tests | domain, data |
| T2 | Presentation: `PlanNotifier`, `PlanScreen` with collapsible sections + action buttons, `plan_providers.dart`, router wiring, placeholder deletion; notifier unit tests + widget tests | presentation, app |

### T1 details

- Add `PlanBucket` enum (`committed`, `candidate`, `proposed`) and `RecordType` enum (`constraint`, `preference`, `decision`) to `lib/core/models/plan.dart`; update `PlanEntry.planBucket: PlanBucket?` and `PlanEntry.recordType: RecordType?` with `fromMap` parsing
- `PlanException` sealed: `PlanGeneralException`, `PlanConflictException`
- `PlanConflictException` carries hardcoded message `"Action not available for this item"` — backend 409 body is not accessible via `ApiClient` (non-2xx bodies discarded)
- `PlanRepository` abstract: `fetchPlan()`, `markDone(id)`, `dismiss(id)`, `confirm(id)`, `toggleEndorse(id)` — all return `void` (caller doesn't use response fields; full reload follows each action)
- `ApiPlanRepository`: `fetchPlan` calls `GET /plan`, unwraps `data` with `_parseSingle`; action methods call `POST /records/{id}/{action}`, map 409 → `PlanConflictException`, other failures → `PlanGeneralException`
- Tests: stub repository, test all methods; update existing `plan_test.dart` to use typed enum values

### T2 details

- `PlanState`: `PlanInitial | PlanLoading | PlanLoaded({required PlanResponse plan}) | PlanError({required String message})`
- `PlanNotifier`: constructor calls `load()`; `refresh()` = `load()`; action methods = `Future<bool>` with `lastActionError`, reload after success
- `PlanScreen`: `ConsumerStatefulWidget`, per-section collapse state (`Set<String> _collapsed`), per-entry busy tracking (`Set<String> _busyIds`), `use_build_context_synchronously` safe (no context params to async handlers)
- Section keys: `Key('plan-active-section')`, `Key('plan-rules-section')`, `Key('plan-completed-section')`
- Entry card key: `Key('plan-entry-${entry.entryId}')`
- Action button keys: `Key('plan-done-${id}')`, `Key('plan-dismiss-${id}')`, `Key('plan-confirm-${id}')`, `Key('plan-endorse-${id}')`
- Empty state key: `Key('plan-empty-state')`
- Error retry key: `Key('plan-retry-button')`
- Widget tests: all sections render, action buttons correct per type, empty state, error state, settings navigation

---

## Test Impact

### Existing tests affected
- `test/app/placeholders/plan_placeholder_screen_test.dart` — delete (placeholder gone)
- `test/core/models/plan_test.dart` — update to use `PlanBucket` and `RecordType` enum values instead of raw strings

### New tests
- `test/features/plan/presentation/plan_notifier_test.dart` — load/refresh/error/action success+failure, `lastActionError` clears
- `test/features/plan/presentation/plan_screen_test.dart` — renders sections, entry cards, action buttons by type, empty state, error+retry, section collapse toggle, settings navigation

Run: `flutter test test/features/plan/`

---

## Acceptance Criteria

1. `/plan` tab loads and displays `GET /api/v1/plan` data without error when API is reachable.
2. Active items appear grouped by topic under "Active Items" section; uncategorized items appear at the bottom of that section.
3. Rules appear under a "Rules" section; each rule shows its `record_type` badge.
4. Completed items appear under a "Completed" section, collapsed by default.
5. Tapping a section header toggles collapse/expand.
6. Committed entries show Done and Dismiss; candidate entries show Confirm, Done, and Dismiss; proposed entries show Done and Dismiss only; decision rules show Dismiss and Endorse; constraint/preference rules show Endorse only.
7. Tapping Done calls `POST /records/{id}/done` and refreshes the plan list.
8. Tapping Dismiss calls `POST /records/{id}/dismiss` and refreshes.
9. Tapping Confirm (on candidate entries only) calls `POST /records/{id}/confirm` and refreshes.
10. Tapping Endorse (on rules) calls `POST /records/{id}/endorse` and refreshes.
11. Section headers show item counts computed from each section's entry array (not from `PlanResponse.totalCount`).
12. Conflicting action (409) shows a SnackBar with the error message; list is not refreshed.
13. While an action is in-flight for entry X, entry X's buttons are disabled and show a spinner.
14. Pull to refresh reloads the plan from the API; any stale error message is cleared.
15. Network error transitions to error state with a Retry button.
16. `flutter analyze` passes with zero issues; `flutter test` passes.

---

## Risks

| Risk | Mitigation |
|------|------------|
| Action on already-closed record (409) | PlanConflictException mapped, SnackBar shown, list not modified |
| Large plan (many topics/items) | ListView is lazy; no pagination needed for personal-agent scale |

---

## Alternatives Considered

Not needed — this proposal follows the established P022 pattern without introducing new architectural decisions.

---

## Known Compromises and Follow-Up Direction

### No offline caching (V1 pragmatism)
Plan data is fetched fresh on every load. If the API is unreachable, the screen shows an error. Offline support (cache + action queue) requires a dedicated proposal covering persistence schema and sync semantics — deferred to a follow-up.

### Postpone and derive deferred
Both actions require non-trivial UI (date picker for postpone, text field for derive). Implementing them as inline interactions would complicate the screen significantly. They are deferred to a follow-up feature slice once the base screen is established.

### Full reload after each action (V1 pragmatism)
After any successful record action, the notifier calls `load()` which transitions through `PlanLoading`, causing the list to briefly blank. This is consistent with P022 and keeps state management simple. Optimistic updates (remove/update the entry immediately, then refresh) are deferred with offline caching to a follow-up proposal.

### Endorsement state not visible in plan view (V1 pragmatism)
`globalPlanEntryResponse` does not include `user_endorsed`. After tapping Endorse and refreshing, the plan view cannot indicate whether an entry is endorsed. The Endorse button is a fire-and-forget action in V1. A follow-up could add `user_endorsed` to the global plan API response to support a toggle indicator.

### Generic 409 error message (V1 pragmatism)
`ApiClient` discards non-2xx response bodies; only the HTTP status phrase is available. When a record action returns 409, the SnackBar shows a generic "Action not available for this item" rather than the backend's domain-specific message. A follow-up could extend `ApiClient` to preserve error response bodies for 4xx responses.
