# Proposal 021 — Agenda Screen

## Status: Implemented

## Prerequisites
- P020 (Navigation Restructure) — provides `/agenda` route placeholder (branch 0)
- P025 (Shared API Layer) — provides `AgendaResponse`, `AgendaItem`, `AgendaRoutineItem` models in `core/models/agenda.dart` and `ApiClient` with generic `get`/`patch`/`delete` methods in `core/network/api_client.dart`
- personal-agent `GET /api/v1/agenda` endpoint — must be deployed

## Scope
- Tasks: ~3
- Layers: features/agenda (new), core/network, app/router, app/placeholders
- Risk: Low — additive feature replacing a placeholder, no changes to existing features

---

## Problem Statement

Voice-agent users have no visibility into their daily tasks, action items, or routine occurrences from the mobile app. To check what's due today, mark items done, or skip a routine occurrence, they must open the personal-agent web UI in a browser. This defeats the purpose of having a mobile companion app — the phone should be the fastest way to glance at today's agenda and take quick actions on items.

Concrete example: the user finishes a voice recording about buying groceries. The backend creates an action item. To see that item and mark it done later, the user has to leave the app and open the web UI. A native agenda screen would surface this in the first tab.

---

## Are We Solving the Right Problem?

**Root cause:** The mobile app has no data-fetching or rendering layer for agenda data. The `/agenda` route exists (P020) but renders a static placeholder with no API integration.

**Alternatives dismissed:**
- *WebView embedding the personal-agent web UI:* Would technically show the agenda, but provides a poor mobile experience (no native gestures, no offline support, no integration with app state). Contradicts the purpose of building a native mobile client.
- *Push notifications for agenda items instead of a screen:* Notifications remind but don't let users browse, mark done, or skip. They complement an agenda screen but don't replace it.

**Smallest change?** The smallest useful change is a read-only agenda list for a single day. However, the ability to mark items done and skip routines is what makes the screen actionable rather than just informational. Date navigation is necessary because users check tomorrow's plan too. Offline cache is needed because users open the app in transit. All four capabilities (fetch, actions, date nav, cache) are included because each is small and together they make the screen useful.

---

## Goals

- Display action items and routine occurrences for a selected date, fetched from the personal-agent API
- Allow marking action items as done and routine occurrences as done/skipped directly from the mobile app
- Support date navigation (previous/next day, jump to today) so users can plan ahead
- Cache the last-fetched agenda locally for instant display when offline or on slow networks
- Follow existing feature patterns (History as reference) for consistency

## Non-goals

- Week or month granularity views — day view only for V1
- Creating new action items or routines from the agenda screen
- Reordering or editing action item text
- Real-time sync (WebSocket/SSE) — pull-to-refresh is sufficient for V1
- Offline action queueing — done/skip actions require connectivity (show error if offline)

---

## User-Visible Changes

The Agenda tab (first tab, calendar icon) changes from a static placeholder to a functional screen. Users see today's action items grouped by status (active first, then done) and routine occurrences with their templates. They can tap a checkbox to mark an action item done, swipe a routine occurrence to skip it, and navigate between dates with left/right arrows or a "Today" button. When offline, the screen shows the last-fetched data with a "last updated" indicator.

---

## Solution Design

### Architecture

The feature follows the three-layer pattern from CLAUDE.md (domain/data/presentation). Note: the existing History feature uses a flat structure (notifier + screen in one directory). Agenda uses the full layered structure because it has a distinct data layer (API + cache) that justifies separation:

```
features/agenda/
  domain/
    agenda_repository.dart    — abstract AgendaRepository interface
    agenda_state.dart         — sealed AgendaState (loading, loaded, error)
  data/
    api_agenda_repository.dart — ApiClient-backed implementation
  presentation/
    agenda_providers.dart     — Riverpod providers
    agenda_notifier.dart      — StateNotifier<AgendaState>
    agenda_screen.dart        — ConsumerStatefulWidget replacing placeholder
```

Models (`AgendaResponse`, `AgendaItem`, `AgendaRoutineItem`) already exist in `core/models/agenda.dart` (P025). No new models needed.

### Domain Layer

**CachedAgenda wrapper** (defined in `domain/agenda_repository.dart` alongside the interface):

```dart
class CachedAgenda {
  const CachedAgenda({required this.response, required this.fetchedAt});
  final AgendaResponse response;
  final DateTime fetchedAt;
}
```

**AgendaRepository interface** (full contract including cache — see Offline Cache section for rationale):

```
abstract class AgendaRepository {
  Future<AgendaResponse> fetchAgenda(String date);
  Future<CachedAgenda?> getCachedAgenda(String date);
  Future<void> cacheAgenda(String date, AgendaResponse response);
  Future<void> markActionItemDone(String recordId);
  Future<void> updateOccurrenceStatus(String routineId, String occurrenceId, OccurrenceStatus status);
}
```

**AgendaState (sealed):**

```
sealed class AgendaState
  AgendaState.initial()
  AgendaState.loading(CachedAgenda? cached)
  AgendaState.loaded(AgendaResponse response, DateTime fetchedAt)
  AgendaState.error(String message, CachedAgenda? cached)
```

The notifier starts in `initial` and immediately transitions to `loading` by calling `loadAgenda()` in its constructor. The `loading` variant carries an optional `CachedAgenda` (response + fetchedAt timestamp) so the UI can show stale data with a progress indicator during refresh. The `error` variant also carries an optional `CachedAgenda` so the UI can show stale data with an error banner and "Last updated" timestamp rather than a blank screen.

### Data Layer

**ApiAgendaRepository** implements `AgendaRepository` using `ApiClient`:

- `fetchAgenda(date)` → `apiClient.get('/agenda', queryParameters: {'date': date, 'granularity': 'day'})` → parse `ApiSuccess.body` as JSON → `AgendaResponse.fromMap()`
- `markActionItemDone(recordId)` → `apiClient.postJson('/records/$recordId/done')` — the generic POST method on ApiClient (see Affected Mutation Points)
- `updateOccurrenceStatus(routineId, occurrenceId, status)` → `apiClient.patch('/routines/$routineId/occurrences/$occurrenceId', data: {'status': status.toJson()})`

Note: all paths are relative — `ApiClient` prepends `baseUrl` which already includes `/api/v1` (via `deriveBaseUrl()` in `api_client_provider.dart`).

The `updateOccurrenceStatus` method guards against nullable `occurrenceId`: if `AgendaRoutineItem.occurrenceId` is null (routine not yet instantiated for that date), the UI disables the skip/done buttons. The repository method requires a non-nullable `occurrenceId` — callers must only invoke it when an occurrence exists.

**Response envelope:** Per P025, all personal-agent API responses use a `{"data": ...}` envelope. `ApiClient` returns the raw body; the repository unwraps the envelope before constructing models:

```dart
final json = jsonDecode(result.body!) as Map<String, dynamic>;
final data = json['data'] as Map<String, dynamic>;
return AgendaResponse.fromMap(data);
```

This keeps envelope parsing in feature code, not in `ApiClient` (ADR-NET-001).

**Error mapping:** `ApiSuccess` → unwrap `data` envelope, return parsed model. `ApiPermanentFailure` / `ApiTransientFailure` → throw a domain exception with the message. `ApiNotConfigured` → throw with "API not configured" message.

### ApiClient Extension

The existing `ApiClient.post()` method signature is `post(Transcript, {required String url, String? token})` — it's transcript-specific. The agenda feature needs a generic POST similar to the existing generic `get`/`patch`/`delete` methods. A new `postJson` method is needed:

```
Future<ApiResult> postJson(String path, {Map<String, dynamic>? data})
```

Named `postJson` to follow the verb-based naming convention of `get`/`patch`/`delete` while disambiguating from the legacy transcript-specific `post()`. It delegates to the existing `request('POST', path, data: data)` dispatcher and reuses `classifyStatusCode`/`classifyDioException`.

### Presentation Layer

**AgendaNotifier (StateNotifier<AgendaState>):**

Named `AgendaNotifier` following the `HistoryNotifier` convention for StateNotifier-based controllers.

- Holds `selectedDate` (defaults to today)
- Constructor initializes state to `AgendaState.initial()`, then calls `loadAgenda()`
- `loadAgenda()` — reads cache first (via repository), emits `loading(cached)`, fetches from API, emits `loaded`, writes cache (via repository)
- `refresh()` — same as loadAgenda but used by pull-to-refresh
- `selectDate(DateTime date)` — updates selectedDate, triggers loadAgenda
- `goToToday()` — selectDate(DateTime.now())
- `previousDay()` / `nextDay()` — date arithmetic + selectDate
- `markDone(String recordId)` — calls repository, then refreshes on success
- `skipOccurrence(String routineId, String occurrenceId)` — calls repository, then refreshes
- `completeOccurrence(String routineId, String occurrenceId)` — calls repository, then refreshes

On action failure: the `markDone`, `skipOccurrence`, and `completeOccurrence` methods are `Future<bool>` — they return `true` on success, `false` on failure. The screen's UI callback awaits the result and shows a `SnackBar` directly in the widget code on failure (matching the existing app pattern where SnackBars are triggered from UI callbacks, not from state). The notifier state is not modified on failure — no optimistic updates in V1.

**AgendaScreen (ConsumerStatefulWidget):**

Layout:
```
Scaffold(
  appBar: AppBar(
    title: "Agenda",
    actions: [gear icon → context.push('/settings')]  // follows P020 placeholder pattern
  ),
  body: Column(
    children: [
      _DateNavigationBar(date, onPrevious, onNext, onToday),
      Expanded(
        child: RefreshIndicator(
          child: ListView(
            children: [
              if (actionItems.isNotEmpty) ...[
                _SectionHeader("Action Items"),
                ...actionItems.map(_ActionItemTile),
              ],
              if (routineItems.isNotEmpty) ...[
                _SectionHeader("Routines"),
                ...routineItems.map(_RoutineItemTile),
              ],
              if (actionItems.isEmpty && routineItems.isEmpty)
                _EmptyState("No items for this date"),
            ],
          ),
        ),
      ),
      if (state is AgendaStateLoaded && isStale)
        _StaleDataBanner(lastUpdated),
    ],
  ),
)
```

**_DateNavigationBar:** Row with left arrow, formatted date ("Friday, April 18, 2026"), right arrow, and a "Today" chip/button. Tapping arrows calls `previousDay()`/`nextDay()`. "Today" calls `goToToday()`. "Today" button is hidden when already showing today's date.

**_ActionItemTile:** ListTile with leading checkbox (tappable → `markDone`), title = item text, subtitle = topic ref (if present), trailing = status badge. Done items show strikethrough text and are sorted after active items.

**_RoutineItemTile:** ExpansionTile with title = routine name, subtitle = start time + status badge, trailing = overdue indicator. Expanded content shows template items as a checklist. Swipe-to-dismiss triggers skip. Tapping a "Done" button marks the occurrence complete.

### Offline Cache

Simple file-based cache in the app's documents directory:

- On successful fetch: write `AgendaResponse.toMap()` as JSON to `agenda_cache_{date}.json`
- On load (before API call): read cached file if it exists, show immediately as `AgendaState.loading(cached)` with stale indicator
- On API error: keep showing cached data with error banner
- Cache files older than 7 days are cleaned up lazily (on first fetch per app session, not blocking)

Cache is a data-layer concern. The repository uses a `CachedAgenda` wrapper that pairs the response with a `fetchedAt` timestamp:

```dart
class CachedAgenda {
  const CachedAgenda({required this.response, required this.fetchedAt});
  final AgendaResponse response;
  final DateTime fetchedAt;
}
```

The `AgendaRepository` interface includes cache methods:

```
abstract class AgendaRepository {
  Future<AgendaResponse> fetchAgenda(String date);
  Future<CachedAgenda?> getCachedAgenda(String date);
  Future<void> cacheAgenda(String date, AgendaResponse response);
  Future<void> markActionItemDone(String recordId);
  Future<void> updateOccurrenceStatus(String routineId, String occurrenceId, OccurrenceStatus status);
}
```

`ApiAgendaRepository` implements cache methods using `path_provider` (already a dependency) for the documents directory and `dart:io` File for read/write. The cache file stores `{"fetched_at": "...", "response": {...}}` so the timestamp survives serialization. The notifier orchestrates the flow: call `getCachedAgenda` → emit `loading(cached)` → call `fetchAgenda` → emit `loaded` → call `cacheAgenda`. No SQLite table needed — this is ephemeral display cache, not authoritative data.

The 7-day cleanup runs inside `ApiAgendaRepository.fetchAgenda()` on first invocation per session (guarded by a boolean flag). It lists files matching `agenda_cache_*.json`, deletes those with dates older than 7 days. Non-blocking — runs after the fetch response is returned.

### Providers

```dart
final agendaRepositoryProvider = Provider<AgendaRepository>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return ApiAgendaRepository(apiClient);
});

final agendaNotifierProvider =
    StateNotifierProvider<AgendaNotifier, AgendaState>((ref) {
  final repository = ref.watch(agendaRepositoryProvider);
  return AgendaNotifier(repository);
});
```

Note: with `StatefulShellRoute.indexedStack`, the Agenda branch preserves state when the user switches tabs. The `agendaNotifierProvider` survives tab switches, so cached data remains visible. A fresh API call happens only on pull-to-refresh or date change, not on tab re-selection.

### Route Integration

In `router.dart`, replace `AgendaPlaceholderScreen` with `AgendaScreen` in branch 0. The placeholder file and import are removed. No new routes needed.

---

## Affected Mutation Points

All methods that modify agenda-related state:

**Needs change:**
- `router.dart` branch 0 builder — replace `AgendaPlaceholderScreen` with `AgendaScreen`
- `ApiClient` — add `postJson()` method for generic POST (currently only transcript-specific `post()` exists)
- `app/placeholders/agenda_placeholder_screen.dart` — removed entirely

**No change needed:**
- `core/models/agenda.dart` — models are complete from P025
- `core/network/api_client.dart` existing `get()`/`patch()`/`delete()` — reused as-is
- Other feature screens (recording, history, settings) — no cross-feature imports
- `app_shell_scaffold.dart` — Agenda tab icon/label already correct from P020

---

## Tasks

| # | Task | Layer |
|---|------|-------|
| T1 | ApiClient: add generic `postJson()` method + unit tests | core/network |
| T2 | Agenda domain + data: repository interface, sealed state, API repository with file cache + tests | features/agenda/domain, features/agenda/data |
| T3 | Agenda presentation: notifier, screen, providers, route wiring, replace placeholder + widget/notifier tests | features/agenda/presentation, app/router |

### T1 details

Add `postJson(String path, {Map<String, dynamic>? data})` to `ApiClient` that delegates to the existing `request('POST', path, data: data)` dispatcher. This mirrors the pattern of `get()`, `patch()`, and `delete()`.

Tests: extend existing ApiClient test file with cases for `postJson` — success, permanent failure, transient failure, not configured.

Mutation points covered: `ApiClient` generic POST.

### T2 details

1. **Domain:** `AgendaRepository` interface (5 methods: fetchAgenda, getCachedAgenda, cacheAgenda, markActionItemDone, updateOccurrenceStatus). `AgendaState` sealed class (initial, loading with optional cached response, loaded with lastUpdated, error with optional cached response).

2. **Data:** `ApiAgendaRepository` implementing `AgendaRepository`. Uses `ApiClient.get()` for fetch, `ApiClient.postJson()` for mark-done, `ApiClient.patch()` for occurrence status. Maps `ApiResult` to domain types. Implements file-based cache (read/write JSON to documents directory, 7-day cleanup).

3. **Tests:** `ApiAgendaRepository` maps `ApiSuccess` to `AgendaResponse`, maps failures to exceptions, cache read/write round-trips, cache cleanup.

After merge: domain types and data implementation exist, can be injected into tests. No UI yet — system is consistent.

Mutation points covered: none yet (data layer only).

### T3 details

1. **Presentation:**
   - `AgendaNotifier` (StateNotifier) — date selection, load/refresh, action dispatch, cache orchestration via repository
   - `AgendaScreen` — replaces placeholder. Scaffold with AppBar (title + gear icon per P020 placeholder pattern), date navigation bar, RefreshIndicator wrapping ListView with action items section and routines section, empty state, stale data banner
   - `agenda_providers.dart` — repository provider + notifier provider

2. **Route wiring:** Replace `AgendaPlaceholderScreen` import with `AgendaScreen` in `router.dart` branch 0. Delete `app/placeholders/agenda_placeholder_screen.dart`.

3. **Tests:**
   - Notifier tests: state transitions (initial → loading → loaded), load error (loading → error with cache), date navigation, mark-done success/failure, skip/complete occurrence success/failure
   - Widget tests: AgendaScreen renders action items, renders routine items with templates, empty state, date navigation bar, checkbox tap triggers markDone, pull-to-refresh, stale data banner, gear icon navigates to settings. Use `ProviderScope` overrides with stub repository.

After merge: full feature is live, placeholder removed.

Mutation points covered: router branch 0, placeholder removal.

---

## Test Impact

### Existing tests affected

- `test/app/app_test.dart` — currently asserts "Agenda" tab text exists. Should still pass since AgendaScreen will have the same tab label. May need updating if the screen content assertion becomes more specific.
- `test/app/router_test.dart` — if it verifies the Agenda route renders AgendaPlaceholderScreen, the assertion changes to AgendaScreen.
- `test/app/placeholders/agenda_placeholder_screen_test.dart` — imports and instantiates `AgendaPlaceholderScreen` directly. Must be deleted when the placeholder is removed (T3), otherwise `flutter test` will fail to compile.

### New tests

- `test/core/network/api_client_test.dart` — extended with `postJson` cases (T1)
- `test/features/agenda/data/api_agenda_repository_test.dart` — ApiResult mapping, error handling, cache round-trip (T2)
- `test/features/agenda/presentation/agenda_notifier_test.dart` — state transitions, date navigation, action dispatch (T3)
- `test/features/agenda/presentation/agenda_screen_test.dart` — widget rendering, interactions, navigation (T3)

How to run: `cd voice-agent && flutter test test/features/agenda/`

---

## Acceptance Criteria

1. Tapping the Agenda tab (index 0) shows a screen with AppBar title "Agenda" and a date navigation bar defaulting to today's date.
2. The screen fetches `GET /agenda?date=YYYY-MM-DD&granularity=day` (relative to base URL which includes `/api/v1`) and displays action items grouped with an "Action Items" section header.
3. The screen displays routine occurrences grouped with a "Routines" section header, each showing the routine name, start time (if present), and expandable template items.
4. Tapping a checkbox on an active action item calls `POST /records/{id}/done` and refreshes the list on success.
5. Swiping a routine occurrence (only when `occurrenceId` is non-null) triggers `PATCH /routines/{id}/occurrences/{occ_id}` with `status: "skipped"` and refreshes the list on success. Routine items without an `occurrenceId` have skip/done buttons disabled.
6. Tapping left/right arrows in the date bar loads the previous/next day's agenda.
7. Tapping "Today" resets the date to the current day.
8. Pull-to-refresh re-fetches the current date's agenda from the API.
9. When the API returns an error and a cached response exists, the screen shows the cached data with a "Last updated" banner.
10. When no items exist for the selected date, the screen shows an empty state message.
11. The gear icon in the AppBar navigates to `/settings` via `context.push()`.
12. `flutter analyze` passes with zero issues.
13. `flutter test` passes with all tests green.
14. No cross-feature imports — `features/agenda/` imports only from `core/` and its own directory.

---

## Risks

| Risk | Mitigation |
|------|------------|
| API endpoint not deployed when mobile feature ships | Prerequisites list requires backend deployment. Feature gracefully shows error state if API is unreachable. |
| Cache file I/O blocks UI thread on slow devices | JSON files for single-day agenda are small (<10KB). Use `compute()` if profiling shows jank — not expected for V1. |
| Action items marked done but API call fails silently | No optimistic updates in V1. UI waits for API confirmation before refreshing. Error shown via SnackBar. |

---

## Alternatives Considered

**FutureProvider.family instead of StateNotifier controller:** A `FutureProvider.family(date)` could handle the fetch-and-cache pattern with less code. Rejected because the controller needs to manage multiple concerns (selected date, cache orchestration, action dispatch, error recovery with cached fallback) that don't fit cleanly into a single FutureProvider. The History feature validates that StateNotifier works well for this pattern.

**SharedPreferences for cache instead of JSON files:** SharedPreferences would avoid `path_provider` but has a 1MB practical limit on some platforms and doesn't support per-key cleanup. JSON files are simpler for date-keyed cache with TTL cleanup.

**Optimistic updates for mark-done/skip:** Would make the UI feel snappier but introduces complexity (rollback on failure, stale state). V1 uses confirmation-first pattern consistent with the rest of the app. Can be added later if latency is noticeable.

---

## Known Compromises and Follow-Up Direction

### Day-only granularity (V1 pragmatism)
The backend supports `granularity=day|week|month` but V1 only implements day view. The `AgendaResponse` model already carries `granularity`, `from`, and `to` fields, so adding week/month views later is a UI-only change — no model or repository changes needed.

### No offline action queue (V1 pragmatism)
Done/skip actions require connectivity. If offline, the user sees an error. Queueing actions locally (like the transcript sync queue in P004/P005) would add significant complexity. Acceptable for V1 because agenda actions are less time-sensitive than voice recordings — the user can retry when online.

### Emerging pattern: feature-level file cache
History uses SQLite for persistence (authoritative data). Agenda uses JSON files (display cache). If Plan (P023) and Routines (P022) also need display caches, a shared `CacheService` abstraction in `core/` may be worth extracting. Not building it now — two instances don't justify the abstraction.
