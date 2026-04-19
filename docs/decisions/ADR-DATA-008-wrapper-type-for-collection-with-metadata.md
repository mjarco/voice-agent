# ADR-DATA-008: Wrapper type for collection responses with metadata

Status: Accepted
Proposed in: P024

## Context

Some API endpoints return both a collection and associated metadata alongside it. For example,
`GET /api/v1/chat/backends` returns:

```json
{"backends": [...], "default_backend": "groq"}
```

The naive approach is to return `List<BackendInfo>` from the repository method and discard
`default_backend`. However, the UI needs `default_backend` to initialize `selectedBackend` on
first load — without it, the user always starts with no backend selected rather than the server's
recommended default.

Returning a tuple or using `(List<BackendInfo>, String?)` relies on positional destructuring,
which is brittle and unnamed.

## Decision

When a repository method returns a collection accompanied by one or more metadata fields, define
a named wrapper class in the domain layer:

```dart
class BackendOptions {
  final List<BackendInfo> backends;
  final String? defaultBackend;
  const BackendOptions({required this.backends, this.defaultBackend});
}
```

The repository method signature returns the wrapper type: `Future<BackendOptions> getBackends()`.

Callers pattern-match or access named fields: `options.backends`, `options.defaultBackend`.

## Rationale

A named class:
- Makes the returned metadata discoverable via the type system (no comment or documentation
  needed to know what the second element of a tuple means).
- Is testable independently (`BackendOptions(backends: [...], defaultBackend: 'x')`).
- Can be extended if the API gains additional metadata fields without changing the method
  signature.

## Consequences

- Wrapper types are defined in `domain/` alongside the repository interface and the element type
  they wrap (e.g., `BackendOptions` lives in `domain/chat_repository.dart`).
- Wrapper types are plain Dart classes with no codegen. `fromMap` is not needed — the data
  layer constructs them directly from parsed JSON fields.
- This pattern applies to any future repository method that returns a collection with
  accompanying metadata. If a method only returns a collection (no metadata), return `List<T>`
  directly — do not create a wrapper for wrapping's sake.
- The wrapper type name should describe the "options" or "result" concept rather than the
  JSON shape (e.g., `BackendOptions`, not `BackendsResponse`).
