# Proposal 033 — API Cost Dashboard

## Status: Draft (seed)

## Origin

Conversation 2026-04-22. The user wants to see aggregated API costs
(daily / monthly) in the mobile app. This complements the ability to ask
the agent about cost verbally (personal-agent P051) — the dashboard gives
a retrospective visual view, while P051 gives a conversational on-demand
answer.

## Prerequisites

- 020-navigation-restructure — 5-tab shell with route structure
- 021-agenda-screen — pattern for a screen fetching backend aggregates
- 025-shared-api-layer — shared API client with GET support

All are implemented.

**Cross-project dependencies:**

| personal-agent proposal | Status | What it provides | Blocking? |
|---|---|---|---|
| P033 (api-usage-and-cost-tracking) | **Implemented** | `api_usage_log` table tracking per-request tokens and cost | Yes — data source |
| P051 (agent-tool-cost-of-conversation) | **Draft** | Agent tool for conversational cost queries | No — complementary, not blocking |

**Required backend work:** personal-agent P033 stores per-request usage data,
but there is no aggregation endpoint yet. This proposal needs a new
`GET /api/v1/usage/summary?from=DATE&to=DATE` endpoint on personal-agent
that returns daily aggregates (input_tokens, output_tokens, cost_usd,
cost_pln, model breakdown). This would be a lightweight backend addition
— a new proposal seed (~P055) or an extension of P033.

**Why server-side aggregation:** Keeping cost calculation, model pricing
tables, and currency conversion on the backend is cheaper per request,
cacheable, and keeps pricing logic in one place. The voice-agent just
renders what it receives.

## Scope

- Risk: Low — read-only screen, no state mutation, no storage change, no
  platform behavior change
- Layers: `features/usage/` (new feature module), `core/network/` (API
  client already supports GET), `app/router.dart` (new child route)
- Expected PRs: 1 (after backend endpoint exists)

## Problem Statement

The user tracks API costs via personal-agent's web UI or by asking the agent.
Neither gives a quick mobile-native view of spending trends. Opening the web
UI on mobile is friction; asking the agent interrupts the voice flow and
requires an active conversation.

A dedicated screen in the mobile app would let the user glance at costs
without context-switching.

## Proposed Solution

### Routing

`/settings/usage` — child route of `/settings`, same pattern as
`/settings/advanced` (P013). This is consistent with the CLAUDE.md routing
convention: "Infrequently accessed screens (e.g., Settings) are top-level
GoRoutes outside the shell." Cost checking is occasional, not daily — it
fits as a settings sub-screen.

Route ownership table in CLAUDE.md should be updated to include
`/settings/usage` owned by P033.

### Screen: Usage / Costs

**Content:**

1. **Current month summary** — total cost (PLN primary, USD secondary),
   total tokens (input + output), number of requests.
2. **Daily breakdown** — vertical list of daily rows with proportional-width
   bars (Container width = daily cost / max daily cost). Tapping a day
   expands to show per-model breakdown.
3. **Previous month** — same summary for comparison, collapsed by default.

**Loading state:** Centered `CircularProgressIndicator` (same pattern as
P021 `AgendaScreen`).

**Error state:** Error message with a "Retry" button. No cached fallback —
this is a read-only, non-critical screen.

**No charting library in v1.** Proportional bars via `Container` are
sufficient. If a charting library is needed later, `fl_chart` is the
standard Flutter choice.

### Data Source

`GET /api/v1/usage/summary?from=DATE&to=DATE` returning:

```json
{
  "period": {"from": "2026-04-01", "to": "2026-04-23"},
  "total_cost_usd": 12.34,
  "total_cost_pln": 49.36,
  "total_input_tokens": 1234567,
  "total_output_tokens": 567890,
  "total_requests": 42,
  "daily": [
    {
      "date": "2026-04-01",
      "cost_usd": 0.56,
      "cost_pln": 2.24,
      "requests": 3,
      "models": {"claude-sonnet-4-20250514": {"cost_usd": 0.40}, "gpt-4o": {"cost_usd": 0.16}}
    }
  ]
}
```

The UI shows "requests" (API calls), not "conversations" — these are
different metrics and the backend tracks requests. The label should read
"Requests" to match the data.

### Feature Module Structure

```
lib/features/usage/
  domain/
    usage_summary.dart         -- UsageSummary, DailyUsage, ModelCost models
  data/
    usage_service.dart         -- fetches from API via shared ApiClient
  presentation/
    usage_screen.dart          -- ConsumerStatefulWidget rendering the dashboard
    usage_controller.dart      -- StateNotifier<UsageState> managing period
                                  selection (current/previous month), refresh,
                                  loading/error states
    usage_providers.dart       -- StateNotifierProvider for UsageController
```

`StateNotifierProvider` (not `FutureProvider`) because the screen needs:
- Period switching (current month / previous month / custom range)
- Pull-to-refresh
- Loading/error state management

This matches the P021 `AgendaNotifier` pattern.

## Acceptance Criteria

1. Screen is accessible via `/settings/usage` from the settings screen.
2. Current-month summary renders total cost (PLN + USD), total tokens,
   and request count.
3. Daily breakdown renders with proportional-width bars. Tapping a day
   shows per-model cost breakdown.
4. Previous-month summary is displayed (collapsed by default).
5. Loading state shows a centered spinner. Error state shows a message
   with a "Retry" button.
6. No cross-feature imports. `features/usage/` imports only from `core/`.
7. `flutter analyze` passes. `flutter test` passes.

## Tasks

| # | Task | Layer | Notes |
|---|------|-------|-------|
| T1 | Domain models (`UsageSummary`, `DailyUsage`, `ModelCost`) + `UsageService` fetching from API. Unit tests with mocked `ApiClient`. | features/usage/domain, features/usage/data, test | Mergeable alone (no UI). |
| T2 | `UsageController` (StateNotifier), `UsageScreen`, providers, route wiring in `router.dart`. Widget tests for loading/error/happy-path states. Settings screen link. | features/usage/presentation, app/router, test | Depends on T1. |

## Test Impact

**New test files:**
- `test/features/usage/domain/usage_summary_test.dart` — model
  `fromMap`/`toMap` round-trip
- `test/features/usage/data/usage_service_test.dart` — API call with
  mocked `ApiClient`, error handling
- `test/features/usage/presentation/usage_screen_test.dart` — widget test:
  loading spinner, error + retry, data rendering, period switching

**No existing tests affected.**

## Risks

| Risk | Mitigation |
|------|------------|
| Backend aggregation endpoint contract not yet defined — response shape may change | The proposed shape is a starting point. When the backend proposal is written, voice-agent models adapt. Keep models in `features/usage/domain/`, not `core/models/`, to limit blast radius. |
| Daily array could be large for long-time users (months of data) | Backend should paginate or cap to the requested `from-to` range. Client requests only one month at a time. |
| Currency conversion accuracy depends on static backend rate | Acceptable for cost visibility — exact billing is not the goal. Backend P051 documents `USD_TO_PLN` as static config. |

## Dependencies

| Dependency | Status | Blocking? |
|---|---|---|
| personal-agent P033 (cost tracking) | Implemented | Data exists but no aggregation endpoint |
| **personal-agent usage summary endpoint** | **Not yet proposed** | **Yes — blocks this proposal** |
| personal-agent P051 (cost tool) | Draft | Not blocking — complementary |
| 025-shared-api-layer | Implemented | No |
| 021-agenda-screen | Implemented | Pattern reference |

## When to Address

After the backend usage summary endpoint is available. The voice-agent side
is straightforward once the API contract is defined.

## Related

- P000-backlog entry "Daily / monthly API cost dashboard in mobile UI"
- personal-agent P033 (api-usage-and-cost-tracking)
- personal-agent P051 (agent-tool-cost-of-conversation)
- 021-agenda-screen (pattern for aggregate data screens)
- 006-settings-screen (navigation pattern for sub-screens)
