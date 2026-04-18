# Proposal 025 — Shared API Client Layer

## Status: Implemented

## Prerequisites
- P005 (API Sync Client) — establishes `ApiClient`, `ApiResult` sealed type, and `apiConfigProvider`; merged
- P017 (Personal Agent Integration) — voice transcript endpoint + agent reply handling; merged
- personal-agent API endpoints for agenda, plan, routines, conversations, chat — must be deployed

## Scope
- Tasks: 3
- Layers: core/network, core/models
- Risk: Low — extends existing `ApiClient` with generic HTTP methods; no changes to sync worker or existing features

---

## Problem Statement

The current `ApiClient` has two methods: `post()` (sends a `Transcript` to a hardcoded request shape) and `testConnection()`. Both take an explicit `url` and `token` parameter — every caller must know the full URL and manage the auth token itself.

New features (Agenda, Plan, Routines, Chat) need to call 20+ personal-agent REST endpoints. Without a shared API layer:

1. **Each feature duplicates HTTP boilerplate** — Dio instance creation, auth header injection, error classification, base URL composition.
2. **URL management is scattered** — callers must concatenate `apiUrl + "/agenda"` themselves, duplicating the base URL logic currently handled by `SyncWorker`.
3. **No support for GET, PATCH, DELETE** — `ApiClient` only has `post()`. Features need all HTTP methods.
4. **No SSE streaming** — Chat requires Server-Sent Events for `POST /chat/stream`. Dio's response stream can handle this, but it needs a dedicated abstraction.
5. **No shared domain models** — `KnowledgeRecord`, `RecordType`, `Routine`, etc. are needed by multiple features but don't exist on the client.

---

## Are We Solving the Right Problem?

**Root cause:** `ApiClient` was built for a single use case (sync worker POSTing transcripts). It hardcodes the request body shape and requires callers to pass the full URL. There is no HTTP layer generic enough for feature repositories to build on.

**Alternatives dismissed:**

- *One fat ApiClient with methods for every endpoint:* Violates the dependency rule — `ApiClient` lives in `core/network` and must not import feature types. Feature-specific request/response mapping belongs in each feature's `data/` layer.
- *Separate Dio instance per feature:* Wastes resources and duplicates timeout/auth configuration. A single shared Dio instance with consistent settings is correct.
- *Retrofit codegen:* Adds build complexity (`build_runner`) and codegen dependency. Manual repository classes are sufficient for the number of endpoints and consistent with ADR-DATA-003 (no codegen).
- *Replace `post()` signature:* Would break `SyncWorker` which depends on `post(Transcript, url, token)`. Instead, add new generic methods alongside the existing one.

**Smallest change?** Add generic HTTP methods (`get`, `request`, `patch`, `delete`) to `ApiClient` that handle base URL composition and auth injection (POST via `request('POST', ...)`). Add an `SseClient` for streaming. Add shared models in `core/models/`. Feature repositories (in later proposals) build on top.

---

## Goals

- Extend `ApiClient` with generic HTTP methods that compose URLs from a base URL and inject auth headers automatically
- Add an SSE stream client for `POST /chat/stream`
- Define shared domain models (`KnowledgeRecord`, `Routine`, `RoutineOccurrence`, etc.) that multiple features will consume
- Maintain backward compatibility — existing `post()` and `testConnection()` methods continue to work unchanged

## Non-goals

- No feature-specific repositories — those belong in each feature's proposal (P021–P024)
- No UI changes
- No changes to `SyncWorker` or existing sync behavior
- No offline caching strategy — that belongs in each feature's proposal
- No changes to `AppConfig` or settings — the existing `apiUrl` and `apiToken` fields are sufficient

---

## User-Visible Changes

None. This proposal is pure infrastructure. Users see no new screens or behavior. The impact is developer-facing: later proposals (P021–P024) can build feature repositories on a clean API layer instead of duplicating HTTP boilerplate.

---

## Solution Design

### Directory Structure

```
lib/
  core/
    network/
      api_client.dart            # Extended with generic get/request/patch/delete
      sse_client.dart            # New — SSE stream client for chat
    models/
      transcript.dart            # Existing — unchanged
      sync_queue_item.dart       # Existing — unchanged
      sync_status.dart           # Existing — unchanged
      transcript_result.dart     # Existing — unchanged
      transcript_with_status.dart # Existing — unchanged
      knowledge_record.dart      # New — shared KnowledgeRecord model
      routine.dart               # New — Routine, RoutineTemplate, RoutineOccurrence
      conversation.dart          # New — Conversation, ConversationEvent
      agenda.dart                # New — AgendaResponse, AgendaItem, AgendaRoutineItem
      plan.dart                  # New — PlanResponse, PlanTopicGroup, PlanEntry
test/
  core/
    network/
      api_client_test.dart       # Extended with generic method tests
      sse_client_test.dart       # New — SSE parsing tests
    models/
      knowledge_record_test.dart # New — serialization round-trip
      routine_test.dart          # New — serialization round-trip
      conversation_test.dart     # New — serialization round-trip
      agenda_test.dart           # New — serialization round-trip
      plan_test.dart             # New — serialization round-trip
```

### ApiClient Extension

Add three convenience methods and one generic method alongside existing `post()` and `testConnection()`. The existing methods remain unchanged — `SyncWorker` continues to call `post(Transcript, url, token)`.

There is no generic `post()` overload — Dart does not support method overloading. Generic POST requests use `request('POST', path, data: ...)`.

**New methods:**

```dart
Future<ApiResult> get(
  String path, {
  Map<String, dynamic>? queryParameters,
});

Future<ApiResult> request(
  String method,
  String path, {
  Map<String, dynamic>? data,
  Map<String, dynamic>? queryParameters,
});

Future<ApiResult> patch(
  String path, {
  Map<String, dynamic>? data,
});

Future<ApiResult> delete(String path);
```

`request()` is the general-purpose method. `get()`, `patch()`, `delete()` are convenience wrappers that call `request()` internally. Generic POST is done via `request('POST', ...)` — not via the existing `post()` which has a different signature.

**Contract: Base URL composition**

The generic methods resolve the full URL from `path` by reading the configured API base URL. The `path` is a relative path like `/agenda` or `/routines/abc-123/trigger`. The base URL comes from a new `baseUrl` field derived from `apiUrl`:

- If `apiUrl` is `https://agent.jarco.casa/api/v1/voice/transcript`, the base URL is `https://agent.jarco.casa/api/v1`
- The generic methods append `path` to this base URL: `https://agent.jarco.casa/api/v1/agenda`

The base URL is derived once and cached. The derivation strips the trailing `/voice/transcript` (or any path after `/api/v1`) from the configured URL.

**Contract: Auth injection**

The generic methods read the token from the provided configuration and inject `Authorization: Bearer {token}` automatically. No caller needs to manage auth headers.

**Contract: Not-configured guard**

All generic methods check `baseUrl` before making a request. If `baseUrl` is null (API not configured), they return `ApiNotConfigured` — a new fourth subtype of the sealed `ApiResult`:

```dart
class ApiNotConfigured extends ApiResult {
  const ApiNotConfigured();
}
```

This avoids misusing `ApiPermanentFailure` (which carries `statusCode`) for a pre-request condition that has no HTTP status code. Feature controllers pattern-match on `ApiNotConfigured` to show a "configure API" prompt.

**Contract: Sealed type exhaustiveness**

Adding `ApiNotConfigured` to the sealed `ApiResult` type is a compile-time breaking change. Existing exhaustive switches in `SyncWorker._drain()` (sync_worker.dart:132) and `SettingsScreen._testConnection()` (settings_screen.dart:159) must add a case for `ApiNotConfigured`. Since neither `post()` nor `testConnection()` ever return `ApiNotConfigured`, both call sites add a no-op/unreachable case:

```dart
// In SyncWorker (switch statement):
case ApiNotConfigured():
  break; // unreachable — post() never returns this

// In SettingsScreen (switch expression):
ApiNotConfigured() => _TestStatus.error,  // unreachable — testConnection() never returns this
```

**Contract: Error classification**

All generic methods reuse `classifyStatusCode` and `classifyDioException` for HTTP-level errors. These methods are promoted from private (`_classifyStatusCode`, `_classifyDioException`) to public (no underscore prefix) so that `SseClient` can also use them. The existing `post()` and `testConnection()` methods are updated to call the renamed methods — no behavioral change.

**ApiClient configuration change:**

The `ApiClient` constructor gains an optional `baseUrl` and `token` parameter for the generic methods:

```dart
class ApiClient {
  ApiClient({Dio? dio, this.baseUrl, this.token});

  final String? baseUrl;
  final String? token;
  final Dio _dio;
}
```

The `apiClientProvider` is updated to supply `baseUrl` and `token` from `appConfigProvider`:

```dart
final apiClientProvider = Provider<ApiClient>((ref) {
  final config = ref.watch(appConfigProvider);
  return ApiClient(
    baseUrl: deriveBaseUrl(config.apiUrl),
    token: config.apiToken,
  );
});
```

The existing `post()` and `testConnection()` methods continue to take explicit `url` and `token` parameters and are unaffected.

### Base URL Derivation

The user configures `apiUrl` as the full voice transcript URL: `https://agent.jarco.casa/api/v1/voice/transcript`. The generic methods need the API root: `https://agent.jarco.casa/api/v1`.

Derivation logic:

```dart
String? deriveBaseUrl(String? apiUrl) {
  if (apiUrl == null || apiUrl.isEmpty) return null;
  final uri = Uri.tryParse(apiUrl);
  if (uri == null) return null;
  // Find /api/v1 in the path and truncate after it
  final segments = uri.pathSegments;
  final apiIdx = segments.indexOf('api');
  if (apiIdx == -1 || apiIdx + 1 >= segments.length) return null;
  // Take segments up to and including 'v1' (or whatever version follows 'api')
  final baseSegments = segments.sublist(0, apiIdx + 2);
  return uri.replace(pathSegments: baseSegments).toString();
}
```

This is resilient: if the user's URL doesn't contain `/api/v1`, `baseUrl` is null and generic methods return `ApiNotConfigured`.

**Contract: Path joining**

`baseUrl` never ends with `/`. `path` always starts with `/`. Joining is string concatenation: `'$baseUrl$path'`. The `deriveBaseUrl` function strips any trailing slash from the result of `uri.replace()`. It is a top-level public function in `api_client_provider.dart`, directly testable. Unit tests verify no double-slash in the composed URL.

### SseClient

A lightweight wrapper around Dio's response stream for Server-Sent Events. Used by the Chat feature (P024) for `POST /chat/stream`.

```dart
class SseClient {
  SseClient({required ApiClient apiClient, Dio? dio});

  Stream<SseEvent> post(
    String path, {
    required Map<String, dynamic> data,
  });
}

class SseEvent {
  final String? event;    // event type (e.g., "tool_use", "result", "error")
  final String data;      // event data (JSON string)
  final String? id;       // optional event ID
}
```

**Contract: SSE protocol**

The SSE client sends a `POST` request with `Accept: text/event-stream` and parses the response stream according to the SSE spec:
- Lines starting with `data:` contribute to the event data
- Lines starting with `event:` set the event type
- Lines starting with `id:` set the event ID
- Empty lines delimit events
- Lines starting with `:` are comments (ignored)

The stream emits `SseEvent` objects and completes when the response stream ends. On Dio errors, it emits an error on the stream using `ApiClient.classifyDioException()` (public after the promotion in T1).

**Contract: Dio instance**

`SseClient` creates its own `Dio` instance (via `_createSseDio()`) with an extended `receiveTimeout` of 10 minutes (vs. the shared instance's 2 minutes). LLM responses with tool use can take several minutes; the shared Dio's 2-minute receive timeout would interrupt long streams. The connect timeout remains 10 seconds (shared). The SSE Dio instance sets `followRedirects: false` (matching the security posture from ADR-NET-001) and uses `ResponseType.stream` for SSE responses.

The constructor accepts an optional `Dio? dio` parameter for test injection. Tests pass a mock Dio adapter to control stream responses and simulate errors — same pattern as `ApiClient(dio: mockDio)` in existing tests.

**Contract: URL composition and auth**

`SseClient` delegates URL composition and auth to the `ApiClient` it wraps. It reads `apiClient.baseUrl` and `apiClient.token` to compose the full URL and `Authorization` header. Request headers include `Content-Type: application/json` and `Accept: text/event-stream`.

**Contract: Not-configured state**

If `apiClient.baseUrl` is null, `SseClient.post()` emits a single `ApiNotConfigured` error on the stream and closes. Feature code handles this the same way as the non-streaming methods.

### Shared Domain Models

All models follow ADR-DATA-003: plain Dart classes with `fromMap()`/`toMap()`, no codegen.

#### Shared Enums

Used across multiple models (Plan, Agenda, record actions).

```dart
enum RecordType {
  topic, question, decision, actionItem, constraint,
  preference, summaryNote, suggestion, journalNote, routineProposal;
}

enum RecordStatus { active, superseded, promoted, done }
enum OriginRole { user, agent, system }
```

#### ConversationRecord

DTO for raw knowledge records returned by `GET /conversations/{id}/records`. Matches the backend's `recordResponse` struct.

```dart
class ConversationRecord {
  final String recordId;
  final String conversationId;
  final RecordType recordType;
  final String subjectRef;
  final Map<String, dynamic> payload;
  final double confidence;
  final OriginRole originRole;
  final String assertionMode;
  final bool userEndorsed;
  final List<String> sourceEventRefs;
}
```

The `payload` field is a raw JSON map whose shape varies by `recordType` (e.g., action items have `text`, decisions have `text` + `rationale`). Feature code extracts display text from `payload` based on `recordType`. This matches the backend's `json.RawMessage` approach — the mobile client does not need a separate payload type per record type for V1.

Note: `PlanEntry` (below) is a separate view-model used by the Plan and Agenda features — it has pre-computed `displayText` and `planBucket` fields that don't exist on raw records.

#### Routine, RoutineTemplate, RoutineOccurrence

```dart
enum RoutineStatus { draft, active, paused, archived }
enum OccurrenceStatus { pending, inProgress, done, skipped }
enum TimeWindow { day, week, month, adHoc }

class Routine {
  final String id;
  final String sourceRecordId;
  final String name;
  final String rrule;
  final String? cadence;
  final String? startTime;        // HH:MM 24h
  final RoutineStatus status;
  final List<RoutineTemplate> templates;  // defaults to [] when absent (list endpoint omits templates)
  final RoutineNextOccurrence? nextOccurrence;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class RoutineTemplate {
  final String? id;               // present in /routines response, absent in /agenda response
  final String text;
  final int sortOrder;
}

class RoutineOccurrence {
  final String id;
  final String routineId;
  final String scheduledFor;      // YYYY-MM-DD
  final TimeWindow timeWindow;
  final OccurrenceStatus status;
  final String? conversationId;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class RoutineNextOccurrence {
  final String date;              // YYYY-MM-DD
  final TimeWindow timeWindow;
}

class RoutineProposal {
  final String id;
  final String? topicRef;
  final String name;
  final String? cadence;
  final String? startTime;
  final List<RoutineProposalItem> items;
  final double confidence;
  final String conversationId;
  final DateTime createdAt;
}

class RoutineProposalItem {
  final String text;
  final int sortOrder;
}
```

#### Conversation, ConversationEvent

```dart
enum ConversationStatus { open, closed }
enum EventRole { user, agent }

class Conversation {
  final String conversationId;
  final String sessionId;
  final ConversationStatus status;
  final DateTime createdAt;
  final int eventCount;
  final DateTime? lastEventAt;
  final String? firstMessagePreview;
  final String? subjectRecordId;
  final String? subjectRecordText;
  final String? subjectRecordStatus;
}

class ConversationEvent {
  final String eventId;
  final String conversationId;
  final int sequence;
  final EventRole role;
  final String content;
  final DateTime? occurredAt;
  final DateTime receivedAt;
}
```

#### AgendaResponse, AgendaItem, AgendaRoutineItem

```dart
class AgendaResponse {
  final String date;
  final String granularity;       // day, week, month
  final String from;
  final String to;
  final List<AgendaItem> items;
  final List<AgendaRoutineItem> routineItems;
}

class AgendaItem {
  final String recordId;
  final String text;
  final String? topicRef;
  final String scheduledFor;      // YYYY-MM-DD
  final String timeWindow;
  final OriginRole originRole;
  final RecordStatus status;
  final int linkedConversationCount;
}

class AgendaRoutineItem {
  final String routineId;
  final String routineName;
  final String scheduledFor;      // YYYY-MM-DD
  final String? startTime;        // HH:MM
  final bool overdue;
  final OccurrenceStatus status;
  final String? occurrenceId;
  final List<RoutineTemplate> templates;
}
```

#### PlanResponse

```dart
class PlanResponse {
  final List<PlanTopicGroup> topics;
  final List<PlanEntry> uncategorized;
  final List<PlanTopicGroup> rules;
  final List<PlanEntry> rulesUncategorized;
  final List<PlanTopicGroup> completed;
  final List<PlanEntry> completedUncategorized;
  final int totalCount;
  final DateTime observedAt;
}

class PlanTopicGroup {
  final String topicRef;
  final String canonicalName;
  final List<PlanEntry> items;
}

class PlanEntry {
  final String entryId;
  final String displayText;
  final String? planBucket;       // committed, candidate, proposed — null for rules
  final double confidence;
  final String conversationId;
  final DateTime createdAt;
  final DateTime? closedAt;       // set for completed items
  final String? recordType;       // constraint, preference — set for rules only
}
```

### API Response Envelope

All personal-agent API responses use a `{"data": ...}` envelope. The generic `ApiClient` methods return the raw response body as `ApiSuccess.body`. Feature repositories parse the envelope:

```dart
// In a feature repository:
final result = await apiClient.get('/agenda', queryParameters: {'date': '2026-04-18'});
if (result case ApiSuccess(:final body)) {
  final json = jsonDecode(body!) as Map<String, dynamic>;
  final data = json['data'] as Map<String, dynamic>;
  return AgendaResponse.fromMap(data);
}
```

This keeps the envelope parsing in feature code, not in `ApiClient`. The `ApiClient` remains transport-layer only (ADR-NET-001).

### Provider Update

The `apiClientProvider` currently lives in `lib/features/api_sync/sync_provider.dart` and creates a bare `ApiClient()`. It moves to `core/providers/` and is updated to inject `baseUrl` and `token`:

```dart
// lib/core/providers/api_client_provider.dart
final apiClientProvider = Provider<ApiClient>((ref) {
  final config = ref.watch(appConfigProvider);
  return ApiClient(
    baseUrl: deriveBaseUrl(config.apiUrl),
    token: config.apiToken,
  );
});
```

The `sync_provider.dart` file keeps a re-export or local reference for backward compatibility. The `SyncWorker` continues to call the old `post(Transcript, url, token)` method — no changes to sync behavior.

---

## Affected Mutation Points

| File / Symbol | Change |
|---------------|--------|
| `lib/core/network/api_client.dart` | Add `baseUrl`, `token` fields. Add `ApiNotConfigured` result subtype. Promote `_classifyStatusCode`/`_classifyDioException` to public. Add generic `get()`, `request()`, `patch()`, `delete()` methods. Existing `post()` and `testConnection()` behavior unchanged. |
| `lib/core/network/sse_client.dart` | New — SSE stream client wrapping Dio response stream. |
| `lib/core/models/knowledge_record.dart` | New — `ConversationRecord`, `RecordType`, `RecordStatus`, `OriginRole` enums. |
| `lib/core/models/routine.dart` | New — `Routine`, `RoutineTemplate`, `RoutineOccurrence`, `RoutineProposal`, status enums. |
| `lib/core/models/conversation.dart` | New — `Conversation`, `ConversationEvent`, status enums. |
| `lib/core/models/agenda.dart` | New — `AgendaResponse`, `AgendaItem`, `AgendaRoutineItem`. |
| `lib/core/models/plan.dart` | New — `PlanResponse`, `PlanTopicGroup`, `PlanEntry`. |
| `lib/core/providers/api_client_provider.dart` | New — promoted `apiClientProvider` with `baseUrl`/`token` injection. |
| `lib/features/api_sync/sync_provider.dart` | Remove `apiClientProvider` (moved to core). Keep `apiConfigProvider`, `syncWorkerProvider`, connectivity providers. |
| `lib/features/settings/settings_screen.dart` | Remove private `_apiClientProvider` (line 14). Use the core `apiClientProvider` instead. Add `ApiNotConfigured` case to `_testConnection` switch. |
| `lib/features/api_sync/sync_worker.dart` | Add `ApiNotConfigured` case (no-op/break) to the `ApiResult` switch in `_drain()`. No behavioral change. |

---

## Tasks

| # | Task | Layer |
|---|------|-------|
| T1 | Extend `ApiClient` with generic `get()`, `request()`, `patch()`, `delete()` methods (POST via `request('POST', ...)`). Add `ApiNotConfigured` as fourth `ApiResult` subtype. Promote `_classifyStatusCode`/`_classifyDioException` to public (`classifyStatusCode`/`classifyDioException`). Add `baseUrl` and `token` constructor parameters. Implement `deriveBaseUrl()` as a public top-level function (strip trailing slash, no double-slash on join). Move `apiClientProvider` to `core/providers/api_client_provider.dart` with `baseUrl`/`token` injection from `appConfigProvider`. Update `sync_provider.dart` imports. Remove `_apiClientProvider` from `settings_screen.dart` (use core provider). Add `ApiNotConfigured` case to exhaustive switches in `sync_worker.dart` and `settings_screen.dart`. Write unit tests covering: generic GET/request/PATCH/DELETE with mock Dio adapter, `deriveBaseUrl` from various `apiUrl` formats, auth header injection, `ApiNotConfigured` when baseUrl is null, error classification reuse, no double-slash in composed URLs. | core/network, core/providers, features/api_sync, features/settings |
| T2 | Create `SseClient` in `lib/core/network/sse_client.dart` with its own Dio instance (10-minute receive timeout, injectable via optional `Dio? dio` constructor param for testing). Implement SSE stream parsing: `data:`, `event:`, `id:` fields, empty-line delimiters, comment lines. Use `ApiClient.classifyDioException()` for error propagation. Expose `Stream<SseEvent>` from `post()`. Write unit tests covering: multi-line data events, event type extraction, stream completion, Dio error propagation via classifyDioException (using injected mock Dio). | core/network |
| T3 | Create shared domain models: `ConversationRecord` (+ `RecordType`, `RecordStatus`, `OriginRole` enums), `Routine` (+ `RoutineTemplate`, `RoutineOccurrence`, `RoutineProposal`), `Conversation` (+ `ConversationEvent`), `AgendaResponse` (+ items), `PlanResponse` (+ groups). All with `fromMap()`/`toMap()` serialization matching personal-agent JSON field names (snake_case). `Routine.templates` defaults to `[]` when absent in list responses. Write round-trip serialization tests for every model, including a test for `Routine.fromMap` with missing `templates` key. | core/models |

---

## Test Impact

### Existing tests affected
- `test/core/network/api_client_test.dart` — add tests for generic methods alongside existing `post()` tests. Existing tests unchanged. Tests that construct `ApiClient(dio: mockDio)` are unaffected because the new `baseUrl` and `token` parameters are optional with null defaults.
- `test/features/api_sync/sync_worker_test.dart` — add `ApiNotConfigured` to any mock/stub `ApiResult` exhaustive patterns if present. The rename of classify methods does not affect tests (they test via public `post()` behavior, not via classify methods directly).
- `test/features/settings/settings_screen_test.dart` — update `_apiClientProvider` references if present. Add `ApiNotConfigured` case to any exhaustive switch patterns.

### New tests
- `test/core/network/api_client_test.dart` — generic `get`/`request`/`patch`/`delete`: correct URL composition, auth header presence, query parameter encoding, error classification for all status ranges.
- `test/core/network/sse_client_test.dart` — SSE line parsing, multi-line data aggregation, event type/id extraction, stream completion on response end, error emission on Dio exception.
- `test/core/models/knowledge_record_test.dart` — `fromMap`/`toMap` round-trip for `ConversationRecord` with all `RecordType` and `RecordStatus` values, including `payload` map preservation.
- `test/core/models/routine_test.dart` — `fromMap`/`toMap` round-trip for `Routine`, `RoutineTemplate`, `RoutineOccurrence`, `RoutineProposal` including nullable fields.
- `test/core/models/conversation_test.dart` — `fromMap`/`toMap` round-trip for `Conversation`, `ConversationEvent`.
- `test/core/models/agenda_test.dart` — `fromMap`/`toMap` round-trip for `AgendaResponse` with nested items.
- `test/core/models/plan_test.dart` — `fromMap`/`toMap` round-trip for `PlanResponse` with nested groups.

---

## Acceptance Criteria

1. `flutter analyze` exits with zero issues.
2. `flutter test` passes — all new and existing tests green.
3. `ApiClient.get('/agenda', queryParameters: {'date': '2026-04-18'})` sends `GET https://agent.jarco.casa/api/v1/agenda?date=2026-04-18` with `Authorization: Bearer {token}` header.
4. `ApiClient.request('POST', '/records/abc/done')` sends `POST https://agent.jarco.casa/api/v1/records/abc/done` with auth header.
5. `ApiClient.patch('/routines/abc/occurrences/xyz', data: {'status': 'done'})` sends PATCH with JSON body and auth header.
6. `ApiClient.delete('/conversations/abc/events/xyz')` sends DELETE with auth header.
7. All generic methods return `ApiNotConfigured` when `baseUrl` is null (API not configured). `ApiNotConfigured` is a new fourth subtype of `ApiResult` with no fields.
8. All generic methods reuse `classifyStatusCode` and `classifyDioException` (promoted from private to public) — error classification is identical to `post()`.
9. Existing `post(Transcript, url, token)` and `testConnection()` methods work identically — no behavioral change for `SyncWorker`.
10. `SseClient.post('/chat/stream', data: {...})` returns a `Stream<SseEvent>` that emits parsed events and completes when the response ends.
11. All models serialize to/from `Map<String, dynamic>` matching the personal-agent JSON field names (snake_case keys).
12. `apiClientProvider` reacts to `appConfigProvider` changes — when the user updates `apiUrl` or `apiToken` in settings, the `ApiClient` is recreated with the new values.

---

## Risks

| Risk | Mitigation |
|------|------------|
| Base URL derivation fails for non-standard `apiUrl` formats | Derivation returns null, generic methods return `ApiNotConfigured`. Settings screen could add validation in a future proposal. Unit tests cover edge cases (trailing slash, no `/api/v1` segment, double-slash prevention). |
| SSE parsing edge cases (multi-line data, retry fields) | Implementation follows the W3C SSE spec. Unit tests cover multi-line data aggregation, empty events, and comment lines. The `retry:` field is parsed but ignored (reconnection is not needed for single-request streams). |
| Model drift between client and server | Models are defined to match current server JSON. Field additions on the server are safe (extra fields ignored by `fromMap`). Field removals break the client — but personal-agent maintains backward compatibility. |
| Moving `apiClientProvider` breaks imports in `SyncWorker` | `sync_provider.dart` re-exports or the import path is updated. Verified by `flutter analyze`. |

---

## Known Compromises and Follow-Up Direction

### No automatic retry for generic methods

The generic `get`/`patch`/`delete` methods return `ApiResult` and leave retry logic to the caller. Only the `SyncWorker` has built-in retry for `post()`. Feature controllers can implement their own retry if needed, but for MVP most API calls are user-initiated (pull-to-refresh, tap action) and a single attempt with error display is sufficient.

### No response caching

Generic methods do not cache responses. Offline access for Agenda/Plan/Routines requires local caching, which belongs in each feature's proposal. The `ApiClient` is transport-only.

### Model subset

The client models are a subset of the server domain types. Fields like `assertion_mode`, `extractor_version`, `interpretation_run_id`, `content_hash`, and `normalized_text` are omitted because no mobile feature needs them. Navigation-relevant fields (`source_record_id`, `subject_record_status`, `received_at`, `closed_at`) are included. If a future feature requires additional fields, the model can be extended without breaking existing code — `fromMap()` ignores unknown keys.

### SSE reconnection not implemented

The `SseClient` does not auto-reconnect on stream interruption. Each chat message is a single request-response cycle. If the stream breaks mid-response, the Chat feature (P024) handles the error and lets the user retry.
