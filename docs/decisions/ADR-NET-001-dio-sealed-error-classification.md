# ADR-NET-001: Dio HTTP client with sealed ApiResult error classification

Status: Accepted
Proposed in: P005

## Context

The app needs an HTTP client for syncing transcripts to the user's API and for Groq STT uploads. Two choices:

- **`http` package** — minimal, no built-in timeout configuration, no native multipart support for file uploads.
- **Dio** — configurable timeouts, interceptors, `FormData` for multipart uploads, structured exception types (`DioException` with typed `DioExceptionType`).

Additionally, the sync worker needs to classify API errors into retryable (transient) vs. permanent categories to decide whether to retry or give up.

## Decision

Use Dio as the HTTP client. Wrap all API responses in a sealed `ApiResult` type:

- `ApiSuccess` — 2xx response, optionally carries response body.
- `ApiPermanentFailure` — 4xx (except 408, 429). Will not be retried.
- `ApiTransientFailure` — 408, 429, 5xx, timeouts, connection errors. Eligible for retry.

Hardcoded client configuration: 10s connect timeout, 15s receive timeout, `followRedirects: false`.

## Rationale

Dio provides timeout granularity and typed exceptions that map cleanly to the sealed result type. The `http` package would require manual timeout handling and multipart construction. The no-redirect policy prevents open-redirect attacks from the user's configured API endpoint — if their endpoint returns 301/302, the client treats it as an error rather than silently following.

## Consequences

- Sync worker pattern-matches on `ApiResult` to decide retry vs. fail — no exception handling in the drain loop.
- Groq STT service uses Dio's `FormData` for multipart WAV upload.
- No-redirect policy may surprise users whose API is behind a load balancer with redirects — they must configure the final URL directly.
- `testConnection()` sends `{'test': true}` POST to verify endpoint reachability without polluting the backend.

## Amendment: Pre-request conditions and multiple Dio instances (P025)

### Fourth ApiResult subtype

The sealed `ApiResult` type is extended with a fourth subtype for pre-request conditions:

- `ApiNotConfigured` — the API base URL is not set. Returned by generic methods (`get`, `request`, `patch`, `delete`) when `baseUrl` is null. Never returned by the legacy `post()` or `testConnection()` methods.

Taxonomy:

- **Pre-request conditions:** `ApiNotConfigured`. Checked before any HTTP call is made. No HTTP status code, no Dio interaction.
- **Post-request outcomes:** `ApiSuccess`, `ApiPermanentFailure`, `ApiTransientFailure`. Result of an actual HTTP request.

Growth constraint: new `ApiResult` subtypes should only be added when the condition must be handled identically to HTTP results (i.e., the caller uses one `switch` over all outcomes). Conditions that can be checked independently (e.g., network connectivity) should be handled before calling `ApiClient`, not encoded as result subtypes.

### Classify methods promoted to public

`classifyStatusCode` and `classifyDioException` are public so that `SseClient` can reuse error classification without duplicating logic. They are pure functions with no side effects.

### Multiple Dio instances

`SseClient` creates its own Dio instance with an extended receive timeout (10 minutes) for long-running SSE streams. All Dio instances MUST preserve the security settings: `followRedirects: false`. Timeout values may be adjusted for the use case.

## Amendment: Domain exception pattern for HTTP error differentiation (P022)

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

### Non-2xx response body constraint on domain exception messages (P023)

`ApiClient` discards non-2xx response bodies — only the HTTP status code and
`response.statusMessage` (the HTTP reason phrase, e.g. "Conflict") are available
when a request fails. Features that map HTTP 4xx errors to domain exceptions
**must not** attempt to forward backend-provided error detail from the response
body, as no body content is accessible.

Consequence: when a feature exception maps a 4xx to a user-visible SnackBar
message (e.g., `PlanConflictException`, `RoutineAlreadyTriggedException`), the
message must be:
- A hardcoded, human-readable domain string defined in the exception class, OR
- Derived solely from the HTTP status code (not the response body).

If a feature needs backend-provided error detail in its SnackBar, the `ApiClient`
must first be extended to preserve 4xx response bodies — that is a separate,
scoped change requiring its own proposal task.

## Amendment: SSE stream error mapping in feature notifiers (P024)

`SseClient` emits raw `ApiResult` subtypes as stream errors — not domain exceptions. Feature
notifiers that subscribe to `SseClient` streams must map these to user-readable messages in a
private helper (e.g., `_streamErrorMessage(Object error)`):

```dart
String _streamErrorMessage(Object error) => switch (error) {
  ApiNotConfigured() => 'API not configured',
  ApiPermanentFailure(message: final m) => m,
  ApiTransientFailure(reason: final r) => r,
  _ => error.toString(),
};
```

This helper is a private method on the notifier, not a shared utility — each feature's notifier
defines its own. The `onError` callback passed to `Stream.listen()` calls this helper and emits
the appropriate error state.

This keeps the `ApiResult` abstraction boundary: HTTP and SSE error types stay below the
presentation layer. The notifier's error state carries only a `String` message.

Note: `SseClient.post()` emits errors as `ApiResult` subtypes (not `ChatException` or similar
domain exceptions). The stream error handler in the notifier is where translation occurs — not in
`SseClient` itself (which is a shared core component unaware of feature domains).
