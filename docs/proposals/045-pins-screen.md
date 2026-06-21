# Proposal 045 — Pins (Saved References) Screen

## Status: Implemented

## Prerequisites
- P024 (Chat Screen) — provides the `/chat` branch and the pattern for fetching backend data via SSE/HTTP; the Pins screen hangs off Chat as a child route
- P025 (Shared API Layer) — provides `ApiClient` with generic `get`/`delete` methods and the `{"data": ...}` envelope convention in `core/network/api_client.dart`
- personal-agent pins endpoints — must be deployed:
  - `GET /api/v1/pins?view=recent|topic` — list
  - `GET /api/v1/pins/{id}` — full verbatim body
  - `DELETE /api/v1/pins/{id}` — unpin (soft delete)
  - (Backend status per memory: P092 + N001 — Implemented and deployed to prod 2026-06-17.)

## Scope
- Tasks: ~3
- Layers: features/pins (new), core/models (new pin models), core/network (reuse), app/router
- Risk: Tier 2 — additive read-mostly feature consuming a deployed API; no changes to existing features, no storage schema, no audio/session behavior

---

## Problem Statement

The personal-agent lets the user pin verbatim references during a conversation —
"zapamiętaj ten pinout", "zapamiętaj ten przepis" — and stores the exact markdown
artifact (a GPIO pinout, a recipe, a checklist, a config snippet). These pins are
the durable, look-it-up-later half of the agent: things the user wants to read
back word-for-word, not have summarized.

Today those pins are only reachable from the personal-agent web UI in a browser.
The voice-agent — the device the user actually has in hand when they need the
pinout in the garage or the recipe in the kitchen — has no way to show them. The
user pins something by voice, then cannot retrieve it on the same device. That is
the exact moment the mobile companion should be fastest.

Concrete example: the user dictates a wiring pinout into a chat, says "zapamiętaj
ten pinout", and a pin is created. A week later, phone in hand at the workbench,
they have no way to pull that pinout up in the app — they must open a laptop.

---

## Are We Solving the Right Problem?

**Root cause:** The mobile app has no screen that reads the pins API. The backend
already exposes a complete read surface (list + detail + unpin); the gap is
entirely client-side.

**Alternatives dismissed:**
- *Surface pins inside the Chat thread only:* Pins are created in chat, but the
  point of a pin is durable retrieval decoupled from the conversation that
  created it. Browsing them requires a dedicated list, not scrolling chat history.
- *WebView the personal-agent pinboard:* Shows the data but gives a poor mobile
  experience (no native gestures, no offline cache) and contradicts the
  native-client purpose — same reasoning P021 used to dismiss WebView for agenda.
- *Add a sixth bottom-nav tab for Pins:* P020 fixed the shell at 5 tabs (Agenda,
  Plan, Record, Routines, Chat) and the convention is that feature proposals
  replace placeholders, not add top-level routes. Pins is lower-frequency than the
  five primaries, so it belongs as a child route, not a tab.

**Smallest change?** The smallest useful change is a read-only list + detail view:
list pins, tap to read the full verbatim body. Unpin (DELETE) is included because
the backend supports it cheaply and a stale pinboard with no way to remove dead
entries decays fast — but it is the only mutation. No create (the backend has no
POST; pins are created by voice in chat), no edit, no offline queue.

---

## Goals

- List the user's pins fetched from `GET /api/v1/pins`, newest first, with a
  topic-grouped view toggle (`?view=topic`)
- Open a pin to read its full verbatim markdown body (`GET /api/v1/pins/{id}`),
  rendered readably (markdown), with select/copy support
- Unpin a reference (`DELETE /api/v1/pins/{id}`) from the list or detail view,
  with confirmation
- Reach the screen from the Chat tab's app bar (a pin/bookmark icon) since pins
  originate in conversations
- Follow existing data-browsing feature patterns (Agenda P021, Chat P024) for
  consistency

## Non-goals

- Creating or editing pins from the app — the backend has no write endpoint; pins
  are created by voice in chat ("zapamiętaj …"). Out of scope by contract.
- Offline cache of pin bodies — V1 fetches live; a cached pinboard is a follow-up
  (see Known Compromises). Unlike Agenda, pins are reference lookups the user
  typically does online; a stale-cache layer is deferred.
- Search / full-text filter across pins — V1 is browse + topic toggle only.
- Real-time updates (SSE/WebSocket) — pull-to-refresh is sufficient.
- Rich aliases/source-event navigation — `aliases` and `source_event_ids` are in
  the detail response but V1 does not surface them as actionable links.

---

## User-Visible Changes

A pin/bookmark icon appears in the Chat (Conversations) list screen's app bar.
Tapping it pushes a
**Pins** screen: a list of saved references, each row showing the pin name, its
topic label (if any), and when it was created. A segmented control at the top
toggles between "Recent" and "By topic" ordering. Tapping a row opens a **Pin
detail** screen rendering the full saved artifact as readable markdown, with a
copy action. Both the list and the detail screen offer an "Unpin" action (with a
confirmation dialog) that removes the reference. Pull-to-refresh re-fetches the
list. When there are no pins, the screen shows an empty state explaining that
pins are created by saying "zapamiętaj …" in a conversation.

---

## Solution Design

### Backend contract (already deployed)

All routes require `Authorization: Bearer <token>` (the same token already
configured for the personal-agent base URL) and wrap their payload in a
`{"data": ...}` envelope.

**List — `GET /api/v1/pins?view=recent|topic`** (default `recent`):
```json
{ "data": [
  { "record_id": "abc123", "pin_name": "garage pinout",
    "topic_label": "Electronics", "created_at": "2026-06-15T10:30:00Z" }
] }
```
Row DTO fields: `record_id`, `pin_name`, `topic_label` (optional), `created_at`
(RFC3339).

**Detail — `GET /api/v1/pins/{id}`**:
```json
{ "data": {
  "record_id": "abc123", "pin_name": "garage pinout", "topic_label": "Electronics",
  "text": "# Pinout\n\n| Pin | Signal |\n|-----|--------|\n...",
  "aliases": ["pinout", "wiring"], "source_event_ids": ["event-456"],
  "created_at": "2026-06-15T10:30:00Z" } }
```
Adds `text` (verbatim markdown body), `aliases` (optional), `source_event_ids`
(optional).

**Unpin — `DELETE /api/v1/pins/{id}`**:
```json
{ "data": { "record_id": "abc123", "pinned": false } }
```
Soft delete (recoverable server-side). Errors use the standard error envelope:
`404 not_found` if the pin does not exist / is already inactive, `500
internal_error` otherwise.

### Architecture

Full layered structure (domain/data/presentation) like Agenda, because the
feature has a distinct data layer (two GET shapes + one DELETE):

```
features/pins/
  domain/
    pins_repository.dart   — abstract PinsRepository interface
    pins_state.dart        — sealed PinsListState (loading, loaded, error)
                             + sealed PinDetailState
  data/
    api_pins_repository.dart — ApiClient-backed implementation
  presentation/
    pins_providers.dart    — Riverpod providers
    pins_notifier.dart     — StateNotifier<PinsListState> (list)
    pin_detail_notifier.dart — StateNotifier<PinDetailState> (single pin)
    pins_screen.dart       — list screen (pushed from Chat app bar)
    pin_detail_screen.dart — detail screen
```

### Core models (new)

Two plain Dart models in `core/models/pin.dart` (no codegen, `fromMap` only —
these are read-only DTOs, no SQLite serialization needed):

```dart
class PinSummary {            // GET /api/v1/pins rows
  final String recordId;
  final String pinName;
  final String? topicLabel;
  final DateTime createdAt;
  factory PinSummary.fromMap(Map<String, dynamic> m);
}

class PinDetail {             // GET /api/v1/pins/{id}
  final String recordId;
  final String pinName;
  final String? topicLabel;
  final String text;          // verbatim markdown body
  final List<String> aliases;
  final List<String> sourceEventIds;
  final DateTime createdAt;
  factory PinDetail.fromMap(Map<String, dynamic> m);
}
```

Models live in `core/` (not the feature) to keep the dependency rule clean and
mirror where Agenda/Chat models live (P025). Both DTOs share one file
(`core/models/pin.dart`), matching `core/models/agenda.dart` (which already holds
several related classes) rather than the strict one-class-per-file guideline —
the two pin DTOs are a single read contract and are clearer together.

### Domain layer

```
abstract class PinsRepository {
  Future<List<PinSummary>> fetchPins(PinView view);   // view: recent | topic
  Future<PinDetail> fetchPin(String recordId);
  Future<void> unpin(String recordId);
}

enum PinView { recent, topic }   // maps to ?view=recent|topic
```

Sealed states:
```
sealed class PinsListState
  PinsListState.initial()
  PinsListState.loading()
  PinsListState.loaded(List<PinSummary> pins, PinView view)
  PinsListState.error(String message)

sealed class PinDetailState
  PinDetailState.loading()
  PinDetailState.loaded(PinDetail pin)
  PinDetailState.error(String message)
```

No cached-fallback variants (unlike Agenda) because V1 has no offline cache —
keeping the state machine smaller. If/when caching lands, add the optional-cache
variants then.

### Data layer

`ApiPinsRepository implements PinsRepository` using the shared `ApiClient`
(`get`/`delete`), unwrapping the `data` envelope in feature code. The
envelope-unwrapping-in-feature-code convention comes from P025 (and matches
`api_agenda_repository.dart`); ADR-NET-001 governs only the dio→`ApiResult` error
classification reused below, not the envelope:

- `fetchPins(view)` → `apiClient.get('/pins', queryParameters: {'view': view.name})`
  → `(json['data'] as List).map(PinSummary.fromMap)`
- `fetchPin(id)` → `apiClient.get('/pins/$id')`
  → `PinDetail.fromMap(json['data'])`
- `unpin(id)` → `apiClient.delete('/pins/$id')` → ignore body, treat
  `ApiSuccess` as done

Paths are relative; `ApiClient` prepends the base URL which already includes
`/api/v1`. Error mapping mirrors Agenda: `ApiSuccess` → parse; `ApiPermanentFailure`
(incl. 404) / `ApiTransientFailure` → throw a domain exception carrying the
message; `ApiNotConfigured` → throw "API not configured".

`ApiClient` already exposes generic `get` and `delete` (P025) — **no ApiClient
extension is needed** (unlike Agenda, which had to add `postJson`).

### Presentation layer

**PinsNotifier (StateNotifier<PinsListState>):** holds the current `PinView`
(default `recent`); constructor emits `initial` then calls `load()`. Methods:
`load()` (emit `loading`, fetch, emit `loaded`/`error`), `refresh()`,
`setView(PinView)` (update + reload), `unpin(String recordId)` →
`Future<bool>` (calls repository, on success removes the row from the loaded list
and re-emits; on failure returns false so the screen shows a SnackBar — matching
the Agenda pattern of UI-triggered SnackBars, no state mutation on failure).

**PinDetailNotifier (StateNotifier<PinDetailState>):** constructed with a
`recordId` via `StateNotifierProvider.family`; loads on construction. Methods:
`refresh()`, `unpin()` → `Future<bool>`.

**PinsScreen (ConsumerWidget):**
```
Scaffold(
  appBar: AppBar(title: "Pins"),
  body: Column(
    children: [
      _ViewToggle(view, onChanged: notifier.setView),   // Recent | By topic
      Expanded(child: RefreshIndicator(child: switch (state) {
        loading => CircularProgressIndicator,
        loaded(pins) when pins.isEmpty => _EmptyState(
          "No pins yet. Say \"zapamiętaj …\" in a chat to save a reference."),
        loaded(pins) => ListView of _PinTile,
        error(msg)  => _ErrorState(msg, onRetry: notifier.refresh),
      })),
    ],
  ),
)
```
`_PinTile`: `ListTile` with title = `pinName`, subtitle = `topicLabel` +
relative `createdAt`, trailing overflow menu with "Unpin". Tap → `await
context.push` the detail route, then call `notifier.refresh()` on return (per
ADR-ARCH-011, post-navigation list refresh — same pattern `ConversationsScreen`
uses) so a pin unpinned from the detail screen disappears from the list. In the
`topic` view the list is grouped under topic-label section headers (the backend
already orders by topic; the client inserts headers on label change). Pins with a
null/empty `topicLabel` are collected into a single trailing **"No topic"**
section after all labeled groups, so untyped pins are never dropped.

**PinDetailScreen (ConsumerWidget):** AppBar with title = `pinName`, a copy
action (copies the raw `text` to clipboard) and an "Unpin" action (confirmation
dialog → on success `context.pop()` back to the list; the list's awaited-push +
`refresh()` from ADR-ARCH-011 then drops the row — see `_PinTile`). Body renders
`text` as markdown (see Markdown rendering) inside a scroll view.

### Markdown rendering

Pin bodies are markdown artifacts (tables, code fences, lists). V1 renders them
readably with the markdown renderer the app **already depends on**:
`flutter_markdown_plus` (`pubspec.yaml`), which the Chat feature already uses to
render agent messages (`features/chat/presentation/thread_screen.dart` —
`MarkdownBody` with a `MarkdownStyleSheet`). No new dependency is needed.
`PinDetailScreen` follows that existing usage: render `text` via `MarkdownBody`
inside a scroll view, with a copy action that puts the raw `text` on the
clipboard. (`SelectableText` is not combined with `MarkdownBody`; copy is handled
by the explicit copy action, matching how Chat exposes message text.)

### Providers

```dart
final pinsRepositoryProvider = Provider<PinsRepository>((ref) =>
    ApiPinsRepository(ref.watch(apiClientProvider)));

final pinsNotifierProvider =
    StateNotifierProvider<PinsNotifier, PinsListState>((ref) =>
        PinsNotifier(ref.watch(pinsRepositoryProvider)));

final pinDetailNotifierProvider = StateNotifierProvider.family<
    PinDetailNotifier, PinDetailState, String>((ref, recordId) =>
        PinDetailNotifier(ref.watch(pinsRepositoryProvider), recordId));
```

### Route integration

Per P020 (no new top-level routes; pins is not a tab), the Pins screen is a child
route under the Chat branch, reached from the Chat list screen's app bar —
mirroring how `/record/history` is a child of `/record`:

| Route | Added by | Content |
|-------|----------|---------|
| `/chat/pins` | 045 (child of `/chat` branch) | `PinsScreen` |
| `/chat/pins/:id` | 045 (child of `/chat/pins`) | `PinDetailScreen` |

The Chat list screen `ConversationsScreen`
(`features/chat/presentation/conversations_screen.dart`, AppBar title "Chat")
gains one app-bar action: a pin/bookmark `IconButton` appended to its existing
`actions:` list (which already holds the new-conversation and settings icons),
carrying a stable `Key('conversations-pins-icon')` like its siblings, and calling
`context.push('/chat/pins')`. This is the only edit to an existing feature, and it
is additive (one icon). It lives on the conversation **list** AppBar (not the
per-thread `ThreadScreen`) because pins are browsed across conversations, not
scoped to one thread.

> Route placement note: `/chat/pins` and `/chat/pins/:id` must be registered
> ahead of any `/chat/:conversationId` dynamic route in the Chat branch so
> "pins" is not captured as a conversation id. Confirm ordering in `router.dart`
> during T3.

---

## Affected Mutation Points

**Needs change:**
- `app/router.dart` — add `/chat/pins` and `/chat/pins/:id` as child routes of
  the Chat branch (registered before any `/chat/:conversationId` dynamic route)
- `features/chat/presentation/conversations_screen.dart` — append one keyed
  app-bar `IconButton` (`Key('conversations-pins-icon')`) to the existing
  `actions:` list, pushing `/chat/pins`

**No change needed:**
- `pubspec.yaml` — `flutter_markdown_plus` is already a dependency (used by Chat)
- `core/network/api_client.dart` — generic `get`/`delete` reused as-is (P025)
- Other feature screens (recording, history, settings, agenda, routines) — no
  cross-feature imports
- Storage layer — pins are not persisted locally in V1

---

## Tasks

| # | Task | Layer |
|---|------|-------|
| T1 | Core pin models (`PinSummary`, `PinDetail`) + `fromMap` round-trip tests | core/models |
| T2 | Pins domain + data: `PinsRepository` interface, sealed states, `ApiPinsRepository` (list/detail/unpin) + repository tests (envelope unwrap, error mapping, 404 → exception) | features/pins/domain, features/pins/data |
| T3 | Pins presentation: list + detail notifiers, screens, view toggle, unpin flow, markdown rendering, providers, route wiring + Chat app-bar icon + widget/notifier tests | features/pins/presentation, app/router, features/chat |

### T1 details
Add `core/models/pin.dart` with `PinSummary` and `PinDetail` (`fromMap` only;
parse RFC3339 `created_at`, default `aliases`/`source_event_ids` to `[]` when
absent, tolerate missing optional `topic_label`). Tests: map full and minimal
JSON payloads; verify optional-field defaults.

### T2 details
1. **Domain:** `PinsRepository` (3 methods), `PinView` enum, `PinsListState` and
   `PinDetailState` sealed classes.
2. **Data:** `ApiPinsRepository` using `ApiClient.get`/`delete`, unwrapping the
   `data` envelope, mapping `ApiResult` to domain types/exceptions.
3. **Tests:** list maps `ApiSuccess` to `List<PinSummary>`; detail maps to
   `PinDetail`; `view` query parameter is passed through; permanent failure (404)
   and transient failure throw with the message; `ApiNotConfigured` throws.

After merge: domain + data exist and are testable; no UI yet — system consistent.

### T3 details
1. **Presentation:** `PinsNotifier`, `PinDetailNotifier`, `PinsScreen` (toggle,
   list, empty/error states, unpin menu), `PinDetailScreen` (markdown body, copy,
   unpin-with-confirm), `pins_providers.dart`.
2. **Route wiring:** add `/chat/pins` and `/chat/pins/:id` under the Chat branch
   in `router.dart`, **before** any `/chat/:conversationId` dynamic route so
   "pins" is not parsed as a conversation id; append the keyed pin app-bar icon
   to `ConversationsScreen`'s `actions:` (`conversations_screen.dart`).
3. **Tests:** notifier transitions (initial → loading → loaded; error; view
   switch reloads; unpin success removes row, failure returns false); widget
   tests (list renders tiles, empty state, topic-grouped headers, tap pushes
   detail, detail renders markdown text, copy action, unpin confirmation). Use
   `ProviderScope` overrides with a stub repository.

After merge: feature is live behind the Chat app-bar icon.

---

## Test Impact

### Existing tests affected
- `test/app/router_test.dart` — if it enumerates routes, add the two new child
  routes.
- `test/features/chat/…` (P024 chat screen test) — if it asserts the Chat app
  bar's action set, update for the new pin icon.

### New tests
- `test/core/models/pin_test.dart` — `fromMap` round-trips (T1)
- `test/features/pins/data/api_pins_repository_test.dart` — mapping + error
  handling (T2)
- `test/features/pins/presentation/pins_notifier_test.dart` and
  `pin_detail_notifier_test.dart` — state transitions, view switch, unpin (T3)
- `test/features/pins/presentation/pins_screen_test.dart` and
  `pin_detail_screen_test.dart` — rendering + interactions (T3)

How to run: `cd voice-agent && flutter test test/features/pins/`

This proposal has **no device-only contracts** (no notifications, background
tasks, permissions, or audio session work), so no manual test plan is required —
everything is covered by `make verify`.

---

## Acceptance Criteria

1. The Chat list screen (`ConversationsScreen`, AppBar title "Chat") shows a
   pin/bookmark icon (`Key('conversations-pins-icon')`) in its `actions:`;
   tapping it pushes a Pins screen titled "Pins". The `/chat/pins` and
   `/chat/pins/:id` routes resolve correctly (not captured by the
   `/chat/:conversationId` route).
2. The Pins screen fetches `GET /pins?view=recent` (relative to a base URL that
   includes `/api/v1`) and lists each pin with name, topic label (if present),
   and creation time.
3. A "Recent / By topic" toggle re-fetches with `?view=topic` and renders
   topic-grouped section headers; pins with no topic label appear under a single
   trailing "No topic" section (none are dropped).
4. Tapping a pin pushes a detail screen that fetches `GET /pins/{id}` and renders
   the `text` body as readable markdown via `flutter_markdown_plus`
   (`MarkdownBody`, as in `thread_screen.dart`), with a working
   copy-to-clipboard action.
5. The "Unpin" action (from the list overflow menu or the detail screen) shows a
   confirmation dialog, calls `DELETE /pins/{id}`, and on success removes the pin
   from the list; on failure shows a SnackBar and leaves the list unchanged.
6. Pull-to-refresh re-fetches the current view.
7. When the API returns zero pins, the screen shows an empty state mentioning
   that pins are created by saying "zapamiętaj …" in a chat.
8. When the API errors, the screen shows an error state with a retry action.
9. No cross-feature imports — `features/pins/` imports only from `core/` and its
   own directory; the only edit to `features/chat/` is the additive app-bar icon.
10. `flutter analyze` passes with zero issues; `flutter test` passes green.

---

## Risks

| Risk | Mitigation |
|------|------------|
| Pins endpoints not deployed to the configured backend | Prerequisites require deployment; backend is already on prod per P092/N001. Feature shows an error state if unreachable. |
| `/chat/pins` shadowed by a `/chat/:conversationId` dynamic route | Register the static `pins` child routes before the dynamic conversation route in `router.dart`; covered by an acceptance criterion and called out in T3. |
| Large pin bodies render slowly | Pin bodies are small artifacts (pinouts, recipes); detail view is a single scroll. Lazy `ListView`/`SingleChildScrollView` is sufficient. |
| Unpin is destructive from the user's view | Confirmation dialog before DELETE; backend delete is a soft delete (recoverable server-side), so accidental unpins are not permanent data loss. |

---

## Alternatives Considered

**Pins as a sixth bottom-nav tab:** Rejected — P020 fixed the shell at 5 tabs and
the established convention is that feature proposals replace placeholders rather
than add top-level routes. Pins is lower-frequency than the five primaries.

**Embed pins inside the Chat thread (no separate screen):** Rejected — a pin's
value is retrieval decoupled from the originating conversation; browsing needs a
dedicated list, not chat-history scrolling.

**Offline cache like Agenda (P021):** Deferred, not adopted for V1. Agenda is a
glance-in-transit screen where stale-on-failure is valuable; pins are deliberate
reference lookups usually done online. Caching adds a `CachedPin` state variant
and file I/O for marginal V1 value. Listed as a follow-up.

**Add a write/edit path:** Not possible — the backend has no POST/PUT for pins by
design (P092 Open Q3 parks the capture endpoint). Pins are created by voice in
chat. The app stays read + unpin only.

---

## Known Compromises and Follow-Up Direction

### No offline cache (V1 pragmatism)
V1 fetches the pin list and bodies live. If the user opens Pins offline, they see
an error state. A display cache (mirroring Agenda's file cache) is a clean
follow-up if usage shows users reach for pins without connectivity — the sealed
states would gain optional-cache variants then.

### Aliases and source-event navigation (deferred)
The detail response carries `aliases` and `source_event_ids`. V1 ignores them.
A follow-up could show aliases as chips and deep-link `source_event_ids` back to
the originating chat conversation (P024) — but cross-feature deep-linking needs
its own small design.

### Search across pins (deferred)
V1 is browse + topic toggle. If the pinboard grows large, a client-side or
backend search (`GET /api/v1/pins?q=…`, not yet implemented) becomes worthwhile.
