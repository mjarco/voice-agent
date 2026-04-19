# ADR-NET-003: SSE streaming via dedicated SseClient

Status: Proposed
Proposed in: P025

## Context

The Chat feature (P024) requires Server-Sent Events (SSE) for streaming LLM responses from the backend. The existing `ApiClient` handles request-response HTTP calls and returns `ApiResult`. SSE requires a fundamentally different interaction model: a single HTTP request that produces a stream of events over time.

Two approaches were considered:

- **Add streaming to ApiClient** — extend `ApiClient` with a method that returns `Stream<SseEvent>`. Keeps one class but mixes two interaction models.
- **Separate SseClient** — a dedicated class for SSE, composing with `ApiClient` for URL/auth but managing its own Dio instance with appropriate timeouts.

## Decision

SSE streaming uses a dedicated `SseClient` in `core/network/`. It composes with `ApiClient` for base URL and auth token but creates its own Dio instance with an extended receive timeout (10 minutes vs. the shared instance's 2 minutes). The `SseClient` parses the SSE wire protocol (`data:`, `event:`, `id:` fields, empty-line delimiters) and emits `SseEvent` objects on a Dart `Stream`.

Error handling: Dio errors are classified using the shared `classifyDioException()` function and emitted as stream errors. Pre-request failures (API not configured) emit `ApiNotConfigured` as a stream error.

The SSE Dio instance preserves the security settings from ADR-NET-001 (`followRedirects: false`) while overriding timeouts for the streaming use case.

## Rationale

A separate class keeps `ApiClient` focused on request-response semantics (consistent with ADR-NET-001). SSE has different lifecycle requirements: long-lived connections, incremental parsing, stream-based error propagation. Mixing these into `ApiClient` would complicate its API surface and testing.

Composing with `ApiClient` for URL/auth avoids duplicating configuration logic. The separate Dio instance avoids the shared instance's receive timeout killing long-running streams.

## Consequences

- Two network classes in `core/network/`: `ApiClient` (request-response) and `SseClient` (streaming). If a third interaction model is needed (e.g., WebSocket), it follows the same pattern: dedicated class, shared URL/auth.
- Feature code handles errors differently for streaming vs. request-response: `switch` on `ApiResult` for `ApiClient`, stream error handlers for `SseClient`.
- The SSE Dio instance's 10-minute timeout is specific to the LLM chat use case. Other streaming use cases may need different timeouts — the constructor accepts an optional `Dio` for customization.
- SSE reconnection is not implemented. Each request is a single request-response stream. Reconnection logic, if needed, belongs in the feature layer.

## Amendment: sseClientProvider co-location (P024)

`sseClientProvider` is defined in `lib/core/providers/api_client_provider.dart` alongside
`apiClientProvider`. Both providers depend on the same base URL and auth token configuration;
co-locating them in the same file keeps related infrastructure providers together and avoids
a separate file for a single-line provider.

```dart
// lib/core/providers/api_client_provider.dart
final sseClientProvider = Provider<SseClient>((ref) {
  return SseClient(apiClient: ref.watch(apiClientProvider));
});
```

This is the required location for `sseClientProvider`. Feature providers that need `SseClient`
access it via `ref.watch(sseClientProvider)`, not by constructing `SseClient` directly.
