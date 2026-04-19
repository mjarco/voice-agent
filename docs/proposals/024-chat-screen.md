# Proposal 024 — Chat Screen

## Status: Draft

## Prerequisites
- P020 (Navigation Restructure) — provides `/chat` route placeholder (branch 4)
- P025 (Shared API Layer) — provides `Conversation`, `ConversationEvent`, `ConversationRecord`,
  `SseClient`, `SseEvent`, and `ApiClient` generic methods; merged
- personal-agent chat + conversation endpoints — must be deployed at `agent.jarco.casa`

## Scope
- Tasks: ~3
- Layers: features/chat (new), app/router, app/placeholders
- Risk: Medium — SSE streaming requires careful state management; two-screen flow adds navigation
  complexity

---

## Problem Statement

Voice-agent users have no way to hold an ongoing text conversation with their personal agent on
mobile. Voice recordings produce brief replies and trigger knowledge extraction, but there is no
persistent thread — no way to follow up, ask clarifying questions, or browse previous exchanges.
The personal-agent web UI offers a full chat interface, but it requires leaving the app and
opening a browser. When voice is inconvenient (a meeting, public transport, a quiet room at
night), users have no interaction path at all.

Concrete gap: after a voice recording captures "plan a trip to Italy in May", the backend creates
several action items and a decision. The user cannot follow up with "make it Florence specifically"
from mobile — there is no chat thread to send that message into.

The `/chat` tab exists in the navigation shell (P020) but renders a static placeholder with no
functionality.

---

## Are We Solving the Right Problem?

**Root cause:** The mobile client has no data-fetching or rendering layer for conversation data.
The personal-agent API already exposes all needed endpoints (conversation list, events, records,
streaming chat) — the gap is entirely client-side.

**Alternatives dismissed:**

- *WebView embedding the personal-agent web chat:* Technically shows the UI without native
  development, but delivers a degraded mobile experience (no native keyboard management, no
  status bar integration, no GoRouter navigation), and couples the mobile app's navigation to the
  web UI's URL structure.
- *Extend voice feature with follow-up UI instead of adding chat:* Voice and chat serve different
  contexts (can't speak vs. want to compose carefully and re-read history). They are additive, not
  redundant. Merging them into the recording feature would violate the single-responsibility
  guideline and cross the feature isolation rule.

**Smallest change?** Text send + message display alone would work mechanically. Knowledge record
badges (inline display of extracted items) are included because they are the key differentiator
of personal-agent chat — one extra `GET /records` call per exchange. Model/backend selection is
included because it's a single GET + a dropdown and gives users meaningful control over which
LLM responds. Voice input requires moving `SttService` to `core/` (an architectural change) and
is excluded from V1.

---

## Goals

- Display a conversation list showing all past conversations, ordered by recency
- Allow starting new conversations and sending text messages
- Show SSE streaming progress (tool use indicator) and display the final agent reply
- Show extracted knowledge records as inline tappable badges after each exchange, with endorsement
  toggle
- Allow model and backend selection before sending each message

## Non-goals

- Voice input in the chat text field — requires `SttService` in `core/`; deferred
- Offline conversation caching — conversations are server-side; client is a thin view
- Push notifications for incoming messages
- Message search or filtering
- Editing or deleting sent messages
- Markdown rendering of agent replies — plain text in V1
- Pagination of conversation list — the backend returns all conversations in a single response

---

## User-Visible Changes

The Chat tab (index 4, chat icon) changes from a static placeholder to a functional two-screen
interface. Users see a list of past conversations ordered by recency, with a preview of the first
message and a timestamp. Tapping a conversation opens a scrollable thread showing user and agent
messages. Users can type and send text messages; during streaming, a progress indicator shows
when the agent is running a tool (e.g. "Using Bash…"). Once the agent replies, extracted
knowledge items appear as compact badges below the reply — tapping a badge toggles endorsement
(star). A model/backend selector in the thread's AppBar lets users pick which LLM responds before
sending.

---

## Solution Design

### Directory Structure

```
features/chat/
  domain/
    chat_repository.dart        — ChatRepository interface, ModelInfo, BackendInfo, BackendOptions, ChatResult
    chat_state.dart             — ChatListState + ThreadState (sealed)
  data/
    api_chat_repository.dart    — ApiClient + SseClient backed implementation, ChatException
  presentation/
    chat_providers.dart         — Riverpod providers
    conversations_notifier.dart — StateNotifier<ChatListState>
    thread_notifier.dart        — StateNotifier<ThreadState>
    conversations_screen.dart   — replaces ChatPlaceholderScreen
    thread_screen.dart          — new thread screen
```

All shared models (`Conversation`, `ConversationEvent`, `ConversationRecord`, `RecordType`,
`OriginRole`) already exist in `core/models/` (P025). No new core models needed.

### Domain Layer

**State classes use Dart 3 `sealed class` keyword** (not the plain abstract class pattern from the
pre-Dart-3 Agenda feature). This enables exhaustive `switch` at compile time without a default
case, which is the preferred pattern for Dart 3.4+ projects.

**`ChatException`** (defined in `data/api_chat_repository.dart`, matching the `AgendaException`
pattern from P021):

```
class ChatException implements Exception {
  final String message;
  const ChatException(this.message);
  @override String toString() => message;   — ensures UI shows the message, not 'Instance of ChatException'
}
```

Thrown by `ApiChatRepository` for all `ApiResult` failure variants. `ApiNotConfigured` → message
"API not configured". `ApiPermanentFailure` → message from status code. `ApiTransientFailure` →
message from reason field. Defined in data/ because it is a data-layer translation of `ApiResult`
failure variants — not a domain-level discriminated exception type (no subtypes, no pattern
matching by the notifier on exception subtypes).

**`ChatResult`** (defined in `domain/chat_repository.dart`) — the parsed payload from the `result`
SSE event:

```
class ChatResult {
  final String conversationId;
  final String userEventId;
  final String? agentEventId;    — omitempty on backend
  final String reply;
  final String? backend;         — omitempty on backend

  factory ChatResult.fromMap(Map<String, dynamic> map) — parses chatResultJson shape
                                                         complies with ADR-DATA-003
  — Note: `knowledge_extraction` and `warnings` are present in the backend response
    but not modeled in V1; `fromMap` ignores them. These are candidates for a
    follow-up that shows extraction status in the UI.
}
```

The `ThreadNotifier` uses `ChatResult.fromMap(jsonDecode(event.data) as Map<String, dynamic>)`
when processing the `result` SSE event, rather than parsing the JSON ad hoc. This isolates the
payload schema to the domain layer and makes the absent-field cases testable.

SSE stream errors from `SseClient.onError` deliver raw `ApiResult` subtypes (not `ChatException`).
The `ThreadNotifier.send()` `onError` callback maps them:
```
Object error → switch (error) {
  ApiNotConfigured() => 'API not configured',
  ApiPermanentFailure(message: final m) => m,
  ApiTransientFailure(reason: final r) => r,
  _ => error.toString(),
}
```
This mapping is a private helper `_streamErrorMessage(Object)` on `ThreadNotifier` to keep the
listener callback readable.

**Value objects** (defined in `domain/chat_repository.dart`):

```
class ModelInfo {
  final String id;
  final String name;
  final String backendId;   — references BackendInfo.id; named backendId to distinguish from
                              the BackendInfo object itself

  factory ModelInfo.fromMap(Map<String, dynamic> map) → reads 'id', 'name', 'backend' fields
}

class BackendInfo {
  final String id;
  final String name;
  final bool available;

  factory BackendInfo.fromMap(Map<String, dynamic> map) → reads 'id', 'name', 'available' fields
}
```

**ChatRepository interface:**

```
abstract class ChatRepository {
  Future<List<Conversation>> listConversations();
  Future<List<ConversationEvent>> getEvents(String conversationId);
  Future<List<ConversationRecord>> getRecords(String conversationId);
  Stream<SseEvent> streamChat({
    required String sessionId,
    required String content,
    required String idempotencyKey,
    String? model,
    String? backend,
  });
  Future<void> cancelChat({
    required String sessionId,
    required String idempotencyKey,
  });
  Future<Conversation?> getConversation(String conversationId);
  Future<List<ModelInfo>> getModels({String? backend});
  Future<BackendOptions> getBackends();
  Future<bool> toggleEndorse(String recordId);
}
```

`getConversation(id)` is implemented by calling `listConversations()` and returning the first item
where `conversation.conversationId == id`. Returns null if not found (new conversation case cannot
reach this path; it only arises for existing conversations).

**`BackendOptions`** replaces `List<BackendInfo>` as the return type of `getBackends()` to preserve
the `default_backend` field from the API:

```
class BackendOptions {
  final List<BackendInfo> backends;
  final String? defaultBackend;   — from the "default_backend" key in the API response
}
```

`ThreadNotifier` initializes `selectedBackend` from `defaultBackend` when no previous selection
exists (i.e., on first load of a conversation or new draft).

**`recordDisplayText(ConversationRecord r)`** — a top-level function in `domain/chat_repository.dart`
that extracts a human-readable label for a record badge:

```
String recordDisplayText(ConversationRecord r) {
  final text = r.payload['text'] as String?;
  return text?.isNotEmpty == true ? text! : r.subjectRef;
}
```

Per P025: `payload` shape varies by `recordType` but most record types that the UI surfaces
have a `text` key. Fallback to `subjectRef` for record types without a `text` field.
```

**ChatListState (sealed):**

```
sealed class ChatListState:
  ChatListState.loading()
  ChatListState.loaded(List<Conversation> conversations)
  ChatListState.error(String message)
```

**ThreadState (sealed):**

```
sealed class ThreadState:
  ThreadState.loading()
  ThreadState.empty(             — new conversation, no sessionId from server yet
    String sessionId,            — generated UUID v4 client-side
    List<ModelInfo> models,
    List<BackendInfo> backends,
    String? selectedModel,
    String? selectedBackend,
  )
  ThreadState.loaded(
    Conversation conversation,
    List<ConversationEvent> events,
    List<ConversationRecord> records,
    List<ModelInfo> models,
    List<BackendInfo> backends,
    String? selectedModel,
    String? selectedBackend,
  )
  ThreadState.streaming(
    Conversation? conversation,  — null for new conversations mid-first-send
    List<ConversationEvent> events,  — events loaded before send (no synthetic entries)
    List<ConversationRecord> records,
    List<ModelInfo> models,
    List<BackendInfo> backends,
    String? selectedModel,
    String? selectedBackend,
    String pendingUserMessage,   — the text the user sent; displayed as a pending bubble
                                   by the UI without a fake ConversationEvent
    String? toolProgress,        — e.g. "Using Bash…" from tool_use SSE event
  )
  ThreadState.error(String message, ThreadState? previousState)
```

### API Contracts

**`GET /api/v1/conversations`** — returns `{"data": [...]}` envelope per P025. Array items match
`Conversation.fromMap()`. No pagination — full list in one response.

**`GET /api/v1/conversations/{id}/events`** — returns `{"data": [...]}` envelope. Items match
`ConversationEvent.fromMap()`. Events are ordered by `sequence`.

**`GET /api/v1/conversations/{id}/records`** — returns `{"data": [...]}` envelope. Items match
`ConversationRecord.fromMap()`.

**`POST /api/v1/chat/stream`** — SSE endpoint. Request body:

```
{
  "session_id": "<conversation.sessionId or fresh UUID v4 for new conversations>",
  "content": "<user text>",
  "idempotency_key": "<UUID v4, generated per send attempt>",
  "model": "<optional>",
  "backend": "<optional>"
}
```

SSE event types:
- `event: tool_use` → `data: {"type":"tool_use","tool":"<name>","input":"<truncated>"}` — zero or
  more progress events before the final result
- `event: result` → `data: <chatResultJson>` — final event, stream completes after this
- `event: error` → `data: {"error":"<message>"}` — error event, stream completes after this

`chatResultJson` shape (from `result` event — matches backend `chatResponse` struct exactly):

```
{
  "conversation_id": "...",
  "user_event_id": "...",
  "agent_event_id": "...",    — may be absent (omitempty) if agent produced no event
  "reply": "...",
  "backend": "...",           — may be absent (omitempty)
  "knowledge_extraction": {"user_status": "...", "agent_status": "..."},
  "warnings": ["..."]         — may be absent (omitempty)
}
```

Note: there is no `session_id` in the `result` payload — the backend's `chatResponse` struct does
not include it. The client uses `conversation_id` from the result to fetch events/records.

The `reply` field is the complete agent reply (not incremental deltas). The client shows a typing
indicator + pending user bubble during streaming and refreshes events + records from the API after
receiving `result`. If the post-result event fetch fails (transient error), the notifier emits
`ThreadState.error(message, previousLoadedState)` so the user can retry; the SSE reply text is
not lost because `previousLoadedState` holds the pre-send conversation state (the user can re-send).

**`POST /api/v1/chat/cancel`** — request body:
```
{"session_id": "...", "idempotency_key": "..."}
```
Returns `{"cancelled": true/false}`.

**`GET /api/v1/chat/models`** — returns `{"models": [...]}` (no `data` envelope — different
convention from conversation endpoints). Items: `{"id": "...", "name": "...", "backend": "..."}`.

**`GET /api/v1/chat/backends`** — returns `{"backends": [...], "default_backend": "..."}`. Items:
`{"id": "...", "name": "...", "available": true/false}`.

**`POST /api/v1/records/{id}/endorse`** — no body. Returns `{"user_endorsed": true/false}`.

### Data Layer

**ApiChatRepository** implements `ChatRepository`.

All methods follow the same deserialization pattern (matches `api_agenda_repository.dart`):

```
// Step 1: call ApiClient, pattern-match on result
final result = await _apiClient.get('/conversations');
final body = switch (result) {
  ApiSuccess(body: final b) => b!,
  ApiNotConfigured() => throw const ChatException('API not configured'),
  ApiPermanentFailure(message: final m) => throw ChatException(m),
  ApiTransientFailure(reason: final r) => throw ChatException(r),
};

// Step 2: decode JSON string body and unwrap envelope
final json = jsonDecode(body) as Map<String, dynamic>;
return (json['data'] as List).map((e) => Conversation.fromMap(e as Map<String, dynamic>)).toList();
```

Non-envelope endpoints (`/chat/models`, `/chat/backends`) use the same pattern but read
`json['models']` / `json['backends']` instead of `json['data']`.

Method-by-method summary:
- `listConversations()` → `GET /conversations` → `json['data']` array → `Conversation.fromMap()`
- `getEvents(id)` → `GET /conversations/$id/events` → `json['data']` array →
  `ConversationEvent.fromMap()`
- `getRecords(id)` → `GET /conversations/$id/records` → `json['data']` array →
  `ConversationRecord.fromMap()`
- `streamChat(...)` → `sseClient.post('/chat/stream', data: requestBody)` — returns the
  `Stream<SseEvent>` directly; no deserialization needed. Callers must call `.listen()` in the
  same synchronous frame: `SseClient` fires the HTTP request via `_startStream()` before the
  subscriber attaches, and events are buffered by the `StreamController`. Since `send()` assigns
  `_subscription = repository.streamChat(...).listen(...)` synchronously, no events are lost.
- `cancelChat(...)` → `postJson('/chat/cancel', data: {...})` — result discarded on success
- `getConversation(id)` → reuses `listConversations()` result, returns first match by id; returns
  null if not found (not a separate API call — avoids adding a new backend endpoint)
- `getModels({backend})` → `GET /chat/models?backend=...` → `json['models']` → `ModelInfo.fromMap()`
- `getBackends()` → `GET /chat/backends` → `BackendOptions(backends: json['backends'].map(...),
  defaultBackend: json['default_backend'])`
- `toggleEndorse(id)` → `postJson('/records/$id/endorse')` → `json['user_endorsed']` as `bool`

### Presentation Layer

**ConversationsNotifier (StateNotifier<ChatListState>):**

- Constructor calls `load()` immediately
- `load()` → repository `listConversations()` → emit `loaded(sorted by lastEventAt desc)`
- `refresh()` → same as load (for pull-to-refresh)

Conversations are sorted client-side: conversations with `lastEventAt != null` come first (sorted
desc by `lastEventAt`), then conversations without events (sorted by `createdAt` desc).

**ConversationsScreen (ConsumerStatefulWidget):**

Layout:

```
Scaffold(
  appBar: AppBar("Chat", actions: [+ icon, gear icon])
  body: RefreshIndicator(
    child: ListView.builder(
      items: conversations,
      itemBuilder: _ConversationTile,
    ),
  )
  or: EmptyState("No conversations yet")
  or: ErrorState with retry button
)
```

`_ConversationTile`: shows `firstMessagePreview` (or "New conversation") as title, `eventCount`
+ relative timestamp as subtitle. Tapping:
```dart
await context.push('/chat/${conv.conversationId}');
ref.read(conversationsNotifierProvider.notifier).refresh();
```
Refresh is triggered on pop so the list reflects any new messages or newly created conversations.

"+" button in AppBar:
```dart
ref.invalidate(threadNotifierProvider('new'));  // dispose stale 'new' notifier before pushing
await context.push('/chat/new');
ref.read(conversationsNotifierProvider.notifier).refresh();
```
`ref.invalidate(threadNotifierProvider('new'))` is called before every `context.push('/chat/new')`
so that each tap generates a fresh `ThreadNotifier` with a new client-side UUID and empty state.
Without this, Riverpod returns the existing notifier instance keyed by `'new'`, which may already
hold a completed conversation from a previous new-conversation flow.

**ThreadNotifier (StateNotifier<ThreadState>):**

Initialized with `conversationId` (a conversation UUID or the literal `'new'`).

Notifier fields (in addition to Riverpod `state`):
- `StreamSubscription<SseEvent>? _subscription` — stores the active SSE stream subscription
- `String? _currentIdempotencyKey` — the key for the in-flight send, used by `cancelStream()`
- `String? _activeSessionId` — resolved at `send()` time from the current state (see below).
  This is the authoritative session ID source during streaming: `ThreadState.streaming` does not
  carry `sessionId`, so `cancelStream()` reads this field directly.
- `String? _currentConversationId` — set from `result.conversationId` on the `result` SSE event.
  For new conversations (`conversationId == 'new'`), this is the real conversation ID returned
  by the backend. Used for the post-result event/record fetch. Retained after the `result` event
  so that if the post-result fetch fails and the user retries, the notifier knows which
  conversation to fetch. Cleared (set to null) when state successfully transitions to `loaded`.
- `ThreadState? _preSendState` — snapshot of the state just before `send()` begins streaming;
  used by `cancelStream()` and error recovery to restore the pre-send loaded/empty state
- `String? _pendingModel` / `String? _pendingBackend` — used only if `selectModel/Backend` is
  called while state is `loading`. Cleared (set to null) after being applied when state
  transitions to `empty` or `loaded`.

For **existing conversations** (`conversationId != 'new'`):
- Constructor calls `load()` which fetches `Conversation`, events, records, models, backends in
  parallel. The `Conversation` is required to obtain `sessionId` for subsequent `POST /chat/stream`
  calls. It is fetched via `repository.getConversation(conversationId)`.
- If `getConversation` returns null (unexpected — means the conversation was deleted between
  navigation and load), emits `ThreadState.error('Conversation not found', null)`.
- Emits `ThreadState.loaded(...)` with `selectedBackend` initialized from
  `backendOptions.defaultBackend` if no backend was previously selected.

For **new conversations** (`conversationId == 'new'`):
- Constructor generates a UUID v4 as `sessionId`
- Fetches models + backends
- Emits `ThreadState.empty(sessionId, models, backends,
    selectedModel: _pendingModel, selectedBackend: _pendingBackend ?? backendOptions.defaultBackend)`

**`send(String content)` method:**

1. Resolve `sessionId` from current state:
   - `ThreadState.loaded` with `conversation.status == open`: use `state.conversation.sessionId`
   - `ThreadState.loaded` with `conversation.status == closed`: return immediately (no-op)
   - `ThreadState.empty`: use `state.sessionId` (the client-generated UUID)
   - Other variants: return immediately (no-op)
2. Store current state in `_preSendState`. Generate a UUID v4 as `_currentIdempotencyKey`. Store
   `sessionId` in `_activeSessionId`.
3. Emit `ThreadState.streaming(...)` carrying the pre-send `events` and `records` from the
   current state, plus `pendingUserMessage: content`
4. Assign `_subscription = repository.streamChat(...).listen(onEvent, onError: onStreamError)`
5. On `tool_use` event: emit updated streaming state with new `toolProgress` value
6. On `result` event:
   - Set `_currentConversationId = result.conversationId` (persisted notifier field — for new
     conversations, this is the real server-assigned ID; for existing conversations, it matches
     the `conversationId` constructor arg)
   - Fetch fresh events + records from API using `_currentConversationId`
   - On fetch success: emit `ThreadState.loaded(...)` with refreshed data; clear `_preSendState`;
     clear `_currentConversationId` (set to null — no longer needed)
   - On fetch failure: emit `ThreadState.error('Failed to load messages', currentStreamingState)`
     — uses the current streaming state (not `_preSendState`) so `pendingUserMessage` is preserved
     in `previousState` and the UI can display what was sent. `_currentConversationId` is NOT
     cleared on fetch failure — it may be needed if the caller retries.
7. On `error` SSE event: emit `ThreadState.error(message, _preSendState)` — uses `_preSendState`
   (the pre-send loaded/empty state) so the user can retry from a clean state
8. On stream Dart error: emit `ThreadState.error(message, _preSendState)`

Note: error recovery uses different `previousState` depending on the failure point:
- SSE `error` / stream Dart error → `_preSendState` (pre-send loaded/empty; clean retry state)
- Post-result fetch failure → current `streaming` state (preserves `pendingUserMessage` so the
  user can see what was sent, and the reply text is in the SSE result that was already received)

**`send()` idempotency key:** Generated fresh on each call. `send()` is a no-op if
`state is ThreadState.streaming` (belt-and-suspenders guard — the UI also disables the send
button during streaming, so this case should not occur in normal usage). This ensures no rapid
double-send can start a second stream while the first is active.

**`selectModel(String? model)`** and **`selectBackend(String? backend)`**: reconstruct current
state with the new selection:
- `ThreadState.loaded`: emit `loaded(... selectedModel: model)`
- `ThreadState.empty`: emit `empty(... selectedModel: model)`
- `ThreadState.streaming`: emit `streaming(... selectedModel: model)`
- `ThreadState.loading`: store in `_pendingModel`/`_pendingBackend`; applied when state
  transitions to `empty` or `loaded`
Called by the model/backend picker in the AppBar.

**`cancelStream()`**: Guards first — if `state is! ThreadState.streaming` or `_activeSessionId`
is null, returns immediately (no-op). The cancel button in the UI is only shown when
`state is ThreadState.streaming`, so this guard handles edge cases only (e.g. rapid tap after
stream completes). When safe: calls `_subscription?.cancel()` (stops the Dart listener from
receiving further events), then calls `repository.cancelChat(_activeSessionId!, _currentIdempotencyKey!)`
(HTTP POST to stop LLM generation on the backend). Emits the pre-send `loaded` or `empty`
state from `_preSendState`.

The `cancelChat()` call is fire-and-forget: exceptions thrown by it are caught and discarded.
Cancel is best-effort — if the HTTP cancel fails, the backend closes the SSE connection on its
own once the response completes. The notifier has already emitted the pre-send state before the
cancel call returns, so the UI is already consistent regardless of cancel outcome.

Note: Cancelling the Dart `StreamSubscription` stops the `StreamController` from forwarding
further SSE events to the listener — but the `SseClient._startStream()` coroutine continues
running until the backend closes the HTTP connection. The HTTP cancel call is what actually
stops the LLM generation and closes the backend connection. Together they achieve a clean cancel;
if `cancelChat()` fails silently, the backend will close the SSE connection on its own after the
response completes.

**ThreadScreen (ConsumerStatefulWidget):**

Layout:

```
Scaffold(
  appBar: AppBar(
    title: Text(conversation.firstMessagePreview ?? "New Chat"),
    actions: [_ModelBackendPicker → DropdownButton, gear icon],
  )
  body: Column(
    children: [
      Expanded(
        child: ListView(
          reverse: true,          — newest messages at bottom
          children: [
            ...events.map(_MessageBubble),
            if (streaming) _TypingIndicator(toolProgress),
          ],
        ),
      ),
      _InputBar(controller: textEditingController, onSend: notifier.send, canSend: !isStreaming),
    ],
  )
)
```

`_MessageBubble`: right-aligned for user messages (plain text), left-aligned for agent messages.
The last agent bubble in the thread also renders `_RecordBadges` directly below it. All records
for the conversation are shown under the last agent bubble (V1 simplification — per-exchange
grouping via `sourceEventRefs` is a follow-up, see Known Compromises).

`_RecordBadges`: a Wrap of chip-style badges showing the record type label and subject. Each badge
has a star icon reflecting `record.userEndorsed`. Tapping a badge calls
`notifier.toggleEndorse(record.recordId)` (not the repository directly — the notifier owns all
state mutations). The notifier updates the matching `ConversationRecord` in the current state's
`records` list with the flipped `userEndorsed` value returned by the API.

**`toggleEndorse(String recordId)` on `ThreadNotifier`:** calls `repository.toggleEndorse(recordId)`,
receives the new `userEndorsed` bool, finds the matching record in `state.records` by `recordId`,
and emits an updated state with that record's `userEndorsed` field replaced. Works in both
`loaded` and `streaming` variants (no-op in other variants).

`_ModelBackendPicker`: Shows the current backend name. Tapping opens a bottom sheet with backend
options (available backends as radio buttons) and, for API backends, a model dropdown. Selecting
calls `notifier.selectModel()/selectBackend()`.

`_InputBar`: TextField + send button. Send button is disabled when: (a) state is streaming, or
(b) `state is ThreadState.loaded && state.conversation.status == ConversationStatus.closed`.
On send: call `notifier.send(text)` and clear the text field. A "Conversation closed" label
is shown below the input bar when the conversation is closed.

### New Conversation Flow

1. User taps "+" in ConversationsScreen → `context.push('/chat/new')`
2. ThreadNotifier initializes with `conversationId = 'new'`, generates `sessionId = UUID()`
3. ThreadScreen renders empty message list + input bar
4. User sends first message → SSE stream uses the generated `sessionId`
5. `result` event returns actual `conversationId` → notifier fetches events + records
6. State transitions to `ThreadState.loaded` — thread is now a real conversation
7. Back navigation → ConversationsScreen refreshes → new conversation appears in list

### Route Integration

Branch 4 in `router.dart` gets a child route for the thread:

```
StatefulShellBranch(
  routes: [
    GoRoute(
      path: '/chat',
      builder: (_, __) => const ConversationsScreen(),
      routes: [
        GoRoute(
          path: ':id',           — matches both UUIDs and the literal 'new'
          builder: (_, state) {
            final id = state.pathParameters['id']!;
            return ThreadScreen(conversationId: id);
          },
        ),
      ],
    ),
  ],
)
```

`ChatPlaceholderScreen` import in `router.dart` is removed. `app/placeholders/chat_placeholder_screen.dart` is deleted.

### Providers

```
final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  final sseClient = ref.watch(sseClientProvider);
  return ApiChatRepository(apiClient: apiClient, sseClient: sseClient);
});

final sseClientProvider = Provider<SseClient>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return SseClient(apiClient: apiClient);
});

final conversationsNotifierProvider =
    StateNotifierProvider<ConversationsNotifier, ChatListState>((ref) {
  return ConversationsNotifier(ref.watch(chatRepositoryProvider));
});

final threadNotifierProvider =
    StateNotifierProvider.family<ThreadNotifier, ThreadState, String>((ref, conversationId) {
  return ThreadNotifier(
    conversationId: conversationId,
    repository: ref.watch(chatRepositoryProvider),
  );
});
```

`StateNotifierProvider.family` is used for `threadNotifierProvider` so that each thread has its
own notifier instance keyed by `conversationId`. This allows multiple threads to be initialized
without state collision.

`sseClientProvider` is defined in `core/providers/api_client_provider.dart` alongside
`apiClientProvider` (both depend on `apiClientProvider`, so they're co-located).

---

## Affected Mutation Points

All files that create or replace the chat screen:

**Needs change:**

- `lib/app/router.dart` — branch 4 builder: replace `ChatPlaceholderScreen()` with
  `ConversationsScreen()`, add child `/chat/:id` route returning `ThreadScreen(conversationId: id)`
- `lib/app/placeholders/chat_placeholder_screen.dart` — deleted entirely
- `lib/core/providers/api_client_provider.dart` — add `sseClientProvider`

**No change needed:**

- `core/models/conversation.dart`, `core/models/conversation_record.dart` — models are complete
  from P025
- `core/network/sse_client.dart` — reused as-is
- `core/network/api_client.dart` — all generic methods already present (P025 + P021 added
  `postJson`)
- All other feature screens — no cross-feature imports

---

## Tasks

| # | Task | Layer |
|---|------|-------|
| T1 | Chat domain + data: `ChatRepository` interface (9 methods), `ChatListState`/`ThreadState` sealed classes, `ModelInfo`/`BackendInfo`/`BackendOptions`/`ChatResult`/`ChatException` types, `recordDisplayText()` helper, `ApiChatRepository`, `sseClientProvider`, repository + `ChatResult` unit tests | features/chat/domain, features/chat/data, core/providers |
| T2 | Conversation list: `ConversationsNotifier`, `ConversationsScreen`, `chat_providers.dart` (repository + notifier providers), replace `ChatPlaceholderScreen` in router, delete placeholder file, notifier + widget tests | features/chat/presentation, app/router, app/placeholders |
| T3 | Thread screen: `ThreadNotifier` (SSE flow, new-conversation mode, send/cancel/selectModel), `ThreadScreen` (message bubbles, typing indicator, knowledge record badges + endorse, model/backend picker), `threadNotifierProvider` family, child route wiring, notifier + widget tests | features/chat/presentation, app/router |

### T1 details

1. **Domain:** Define `ChatRepository` interface with 9 methods (includes `getConversation`). Define
   `ModelInfo`, `BackendInfo`, `BackendOptions`, `ChatResult`, and `recordDisplayText()` helper.
   `ChatResult.fromMap(Map<String, dynamic>)` must handle absent `agentEventId`, absent `backend`,
   absent `warnings`. Define `ChatListState` and `ThreadState` sealed classes.
   `ThreadState.streaming.toolProgress` is nullable `String`.
2. **Data:** `ApiChatRepository` — implement all 9 methods. Define `ChatException` in data/ (not
   domain/) — matches `AgendaException` pattern from P021 where the exception is a data-layer
   translation of `ApiResult` failures, not a discriminated domain type. `ChatException.toString()
   => message`. `getConversation(id)` reuses
   `listConversations()` result (no extra HTTP call). `getBackends()` parses both `backends` array
   and `default_backend` field. `getModels()` parses `json['models']`. All other fetch methods
   unwrap `data` envelope per pattern in Solution Design.
3. **Core providers:** Add `sseClientProvider` to `lib/core/providers/api_client_provider.dart`.
4. **Tests:**
   - `test/features/chat/data/api_chat_repository_test.dart`: mock ApiClient + SseClient. Test
     each method: `ApiSuccess` → correct model, `ApiPermanentFailure` → exception,
     `ApiNotConfigured` → exception; `getConversation` returns matching item; `getBackends` parses
     `default_backend`; `toggleEndorse` parses `user_endorsed` boolean.
   - `test/features/chat/domain/chat_result_test.dart`: `ChatResult.fromMap` with all optional
     fields present, absent `agentEventId`, absent `backend`, absent `warnings`, malformed map.
   - `test/features/chat/domain/record_display_text_test.dart`: `recordDisplayText` for records
     with `payload['text']`, without `text` key (fallback to `subjectRef`).

After merge: repository layer is complete, no UI uses it yet — consistent state.

### T2 details

1. **ConversationsNotifier:** `load()` called from constructor, sorts conversations (lastEventAt
   desc, then createdAt desc). `refresh()` public method for pull-to-refresh.
2. **ConversationsScreen:** AppBar with "Chat" title, "+" icon, gear icon. `ListView.builder`
   with `RefreshIndicator`. `_ConversationTile` shows `firstMessagePreview` (fallback: "New
   conversation"), event count, relative timestamp. Empty state when list is empty. Error state
   with retry button. Gear navigates to `/settings` using `context.push('/settings')` (not
   `context.go` — preserves shell branch state per ADR-ARCH-002).
3. **chat_providers.dart:** `chatRepositoryProvider`, `conversationsNotifierProvider`, and a
   **stub** `threadNotifierProvider` family (returns a `ThreadNotifier` that holds
   `ThreadState.loading()` permanently with no API calls). The stub exists solely so T2 compiles
   when `ConversationsScreen` calls `ref.invalidate(threadNotifierProvider('new'))`. T3 replaces
   the stub with the full implementation.
4. **Route wiring:** Replace `ChatPlaceholderScreen` with `ConversationsScreen` in router branch 4.
   Delete `app/placeholders/chat_placeholder_screen.dart`.
5. **Tests:**
   - `test/features/chat/presentation/conversations_notifier_test.dart`: `load()` → loaded state,
     sort order (lastEventAt null goes last), refresh, error on failure
   - `test/features/chat/presentation/conversations_screen_test.dart`: renders tiles, empty state,
     error state, gear navigates to settings, "+" navigates to `/chat/new`
   - Delete `test/app/placeholders/chat_placeholder_screen_test.dart` if it exists

T2 creates `lib/features/chat/presentation/thread_screen.dart` as a placeholder `ThreadScreen`
stub (a minimal Scaffold with title "Thread" and a back button). T2 wires the child route
`/chat/:id` in `router.dart` to this stub. T3 replaces the stub with the full implementation by
rewriting `thread_screen.dart`. T2 is independently mergeable (stub compiles and routes work).
T3 is also independently mergeable (replaces the stub). The system is consistent after each merge:
after T2, conversations open to a minimal thread screen; after T3, they open to the full UI.

### T3 details

1. **ThreadNotifier:** Full SSE flow as described in Solution Design. Stores
   `StreamSubscription<SseEvent>? _subscription`, `String? _currentIdempotencyKey`,
   `String? _activeSessionId`, `ThreadState? _preSendState`, `String? _pendingModel`,
   `String? _pendingBackend` as notifier fields.
   `load()` for existing conversations fetches `Conversation` via `repository.getConversation(id)`,
   events, records, models, backends in parallel; emits error if `getConversation` returns null.
   `send()` is a no-op if `state is ThreadState.streaming` or conversation is closed. Resolves
   `sessionId` per state variant (see Solution Design), assigns `_subscription` via
   `repository.streamChat(...).listen(...)`, handles `tool_use` events (update `toolProgress`),
   `result` events (parse via `ChatResult.fromMap(jsonDecode(event.data) as Map<String, dynamic>)`,
   fetch fresh events + records;
   on fetch failure emit error with current streaming state), `error` SSE events (emit error with
   `_preSendState`). Stream `onError` uses private `_streamErrorMessage(Object)` helper.
   `toggleEndorse(id)` calls repository and reconstructs state with updated record.
   `selectModel()`/`selectBackend()` reconstruct per state variant (or store pending if `loading`).
   `dispose()` calls `_subscription?.cancel()` before super.dispose().
2. **ThreadScreen:** Full implementation replacing the T2 stub. Message bubbles (user = right-
   aligned blue, agent = left-aligned grey). Pending user message from `state.pendingUserMessage`
   shown as a dimmed user bubble at the bottom during streaming. Typing indicator with
   `toolProgress` text when streaming. `_RecordBadges` beneath the last agent bubble — all
   conversation records shown there (V1). Endorsement toggle calls `notifier.toggleEndorse()`.
   Model/backend picker opens `showModalBottomSheet` with backend radio buttons and optional model
   dropdown. `_InputBar` with TextField + send button; disabled during streaming; cleared after
   send.
3. **`threadNotifierProvider` family** added to `chat_providers.dart`.
4. **Tests:**
   - `test/features/chat/presentation/thread_notifier_test.dart`: loading existing conversation
     (loading → loaded, `getConversation` called), `getConversation` returns null → error state,
     new conversation (loading → empty, `selectedBackend` from `defaultBackend`), send no-op when
     streaming, send no-op on closed conversation, send flow (loaded → streaming → loaded after
     result), `pendingUserMessage` set during streaming, tool_use updates `toolProgress`,
     SSE `error` event → error with `_preSendState`, stream Dart error via `_streamErrorMessage`
     (`ApiNotConfigured`, `ApiPermanentFailure`, `ApiTransientFailure`),
     post-result fetch failure → error with current streaming state (preserves `pendingUserMessage`),
     cancelStream guard (no-op when not streaming), cancelStream reverts to `_preSendState`,
     toggleEndorse updates record in state, selectModel in all state variants
   - `test/features/chat/presentation/thread_screen_test.dart`: renders user and agent bubbles,
     pending user bubble during streaming, shows typing indicator, record badges render, endorse
     tap calls notifier.toggleEndorse (not repository directly), input bar disabled during
     streaming, send calls notifier.send(), model picker opens bottom sheet

Mutation points covered: `ThreadScreen` stub (T2) replaced with full implementation.

---

## Test Impact

### Existing tests affected

- `test/app/router_test.dart` — if it verifies branch 4 renders `ChatPlaceholderScreen`, update
  assertion to `ConversationsScreen`
- `test/app/app_test.dart` — if it asserts "Chat" tab text, should still pass; may need update
  if content assertion becomes more specific
- `test/app/placeholders/chat_placeholder_screen_test.dart` — delete if present (T2 removes the
  placeholder file)

### New tests

- `test/features/chat/data/api_chat_repository_test.dart` — repository method coverage (T1)
- `test/features/chat/domain/chat_result_test.dart` — `ChatResult.fromMap` optional-field combinations (T1)
- `test/features/chat/domain/record_display_text_test.dart` — `recordDisplayText` helper (T1)
- `test/features/chat/presentation/conversations_notifier_test.dart` — list state transitions (T2)
- `test/features/chat/presentation/conversations_screen_test.dart` — widget rendering (T2)
- `test/features/chat/presentation/thread_notifier_test.dart` — SSE flow + state transitions (T3)
- `test/features/chat/presentation/thread_screen_test.dart` — widget rendering + interactions (T3)

How to run: `cd voice-agent && flutter test test/features/chat/`

---

## Acceptance Criteria

1. Tapping the Chat tab (index 4) shows `ConversationsScreen` with AppBar title "Chat" and a list
   of past conversations sorted by most-recent-activity first.
2. Tapping a conversation navigates to `/chat/{id}` and loads the thread with all past messages.
3. Tapping "+" navigates to `/chat/new`, shows an empty thread with a functional input bar.
4. Sending a text message from an existing thread calls `POST /api/v1/chat/stream` with the
   conversation's `session_id` and the typed content.
5. Sending a message from a new thread (`/chat/new`) generates a fresh UUID v4 as `session_id`.
   After the `result` SSE event, the thread has a real `conversation_id` and subsequent
   `GET /conversations/{id}/events` and `GET /conversations/{id}/records` calls succeed.
6. During streaming, the typing indicator is visible and the send button is disabled.
7. `tool_use` SSE events update the typing indicator text (e.g. "Using Bash…") before the final
   result arrives.
8. After the `result` event, the agent reply appears as a message bubble, and extracted records
   appear as badges below the agent bubble within the same exchange.
9. Tapping an unendorsed record badge calls `POST /api/v1/records/{id}/endorse` and adds a star;
   tapping an endorsed badge removes it.
10. The model/backend picker in the thread AppBar shows available backends; selecting a backend
    updates `selectedBackend` in state and uses it in the next `POST /chat/stream` request.
11. Pull-to-refresh on the conversation list re-fetches from `GET /api/v1/conversations`.
12. When API is not configured, all screens show an error state with "API not configured" message.
13. `flutter analyze` passes with zero issues.
14. `flutter test` passes with all tests green.
15. No cross-feature imports — `features/chat/` imports only from `core/` and within its own
    directory.
16. `ChatPlaceholderScreen` file is deleted; no imports to it remain.
17. Tapping the gear icon in `ConversationsScreen` navigates to `/settings` via `context.push('/settings')`.
18. When a conversation's status is `closed`, the `_InputBar` send button is disabled and a
    "Conversation closed" label is shown; `send()` is a no-op.
19. `BackendOptions.defaultBackend` is used to initialize `selectedBackend` on first thread load.

---

## Risks

| Risk | Mitigation |
|------|------------|
| SSE stream not cancelled on screen disposal | `ThreadNotifier.dispose()` calls `_subscription?.cancel()`. `dispose()` fires when Riverpod removes the provider — at app shutdown, not on back navigation (family provider is not auto-disposed). An in-progress stream that the user "backs out of" continues until `result`/`error` fires, then cleanly completes. This is the desired behaviour. |
| `result` SSE event arrives after the user navigates back | Notifier continues to completion. State update has no visible effect (no listener). The updated state is available if the user navigates back to the same thread. |
| `GET /conversations/{id}/events` after send may miss the new events (race with backend) | Fetch is triggered only after the `result` SSE event confirms the agent reply is written. Backend completes event storage before emitting `result`. Race is safe. |
| `GET /api/v1/conversations` and chat endpoints using different envelope conventions | Repository methods use the correct parser per endpoint (envelope vs. direct array). This is tested in T1 with concrete mock responses. |
| `threadNotifierProvider.family` keeps all opened threads in memory | Acceptable for V1: conversation threads are lightweight (text events only). Can add `autoDispose` in a follow-up if memory becomes a concern on very long history. |

---

## Alternatives Considered

**`FutureProvider.family` for thread events instead of StateNotifier:** A `FutureProvider` could
load events once but cannot manage SSE streaming state, optimistic user messages, or streaming
cancellation. `StateNotifier` is the correct choice.

**Accumulate SSE delta text client-side for word-by-word rendering:** The backend does not emit
delta events in V1 (only `tool_use` + `result`). Delta streaming would require a backend change.
The typing indicator during `tool_use` events provides sufficient streaming feedback for V1.

**Separate `ConversationDetailScreen` for reading (non-interactive) vs `ThreadScreen` for chat:**
Over-engineering for V1. The same screen serves both reading history and composing new messages —
the input bar is simply disabled when a conversation is closed.

---

## Known Compromises and Follow-Up Direction

### No voice input in chat (V1 pragmatism)

The original stub intended a mic button in the text input bar, reusing `RecordingController` for
STT. This requires `SttService` to move from `features/recording/domain/` to `core/` so that
`features/chat/` can import it without violating the dependency rule. That architectural change
belongs in its own proposal. For V1, the input bar is text-only.

### Plain text agent replies (V1 pragmatism)

Personal-agent replies often contain markdown (bullet lists, headers, code blocks). V1 displays
them as plain strings. Adding `flutter_markdown` is a one-file change in `_MessageBubble` — deferred
because markdown rendering requires testing on both platforms and it doesn't affect functionality.

### Knowledge records shown under latest agent bubble only (V1 pragmatism)

`_RecordBadges` displays all conversation records beneath the last agent bubble in the thread —
not grouped per exchange. Proper per-exchange grouping requires matching each record's
`sourceEventRefs` against the corresponding agent event's `eventId`. This matching is well-defined
(both fields exist on the models) but adds rendering complexity for V1. The degenerate case (many
exchanges → all records under the last bubble) is visually tolerable for conversations with < 10
exchanges, which covers most use cases. Grouping by exchange is a visual follow-up with no API
or state changes required.

### `threadNotifierProvider.family` not auto-disposed

All opened thread notifiers stay alive for the app session. For most users this is fine (a few
conversations). If memory usage becomes a concern, adding `.autoDispose` is a one-line change
but requires careful handling of in-progress streams — deferred until there's evidence of a
problem.

### Thread load fetches full conversation list to resolve `sessionId` (V1 pragmatism)

`getConversation(id)` is implemented by calling `listConversations()` (a full `GET /conversations`
fetch) and returning the matching item. This means opening any existing conversation thread issues
a list fetch just to obtain the `Conversation` object (and its `sessionId`). For a backend with
< 50 conversations, this is a 1–2 KB response and negligible in practice. A dedicated
`GET /conversations/{id}` endpoint would eliminate the extra list fetch — deferred until the
backend exposes it or conversation counts grow large.

### `knowledge_extraction` and `warnings` not modeled in `ChatResult` (V1 pragmatism)

The `result` SSE event carries `knowledge_extraction` and `warnings` fields that `ChatResult.fromMap`
currently ignores. A future follow-up can add these fields to display extraction status or surface
backend warnings inline in the thread UI.
