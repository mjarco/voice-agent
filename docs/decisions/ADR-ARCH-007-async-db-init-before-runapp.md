# ADR-ARCH-007: Async database initialization before runApp with throw-if-not-overridden provider

Status: Accepted
Proposed in: P004

## Context

The app requires SQLite to be ready before any screen renders — every feature reads from the database on first frame. Flutter's `runApp` is synchronous, but database initialization (`SqliteStorageService.initialize()`) is async.

Options for bridging async initialization into the synchronous widget tree:

- **FutureProvider** — lazy initialization on first read. Requires every consumer to handle `AsyncValue` loading/error states. Adds loading spinners throughout the app.
- **Pre-runApp await** — initialize in `main()` before `runApp()`, inject the ready instance via provider override. Consumers get a synchronous `StorageService` with no loading states.
- **Lazy singleton** — global mutable state, not testable.

## Decision

Initialize the database in `main()` with `await SqliteStorageService.initialize()` before calling `runApp()`. Inject the initialized instance via `storageServiceProvider.overrideWithValue(storage)` on `ProviderScope`.

The default `storageServiceProvider` throws `UnimplementedError` if not overridden — a runtime guard that fails fast if the override is missing.

## Rationale

Pre-runApp initialization guarantees every widget has database access from the first frame, eliminating loading spinners and `AsyncValue` handling in every consumer. The throw-if-not-overridden pattern is distinct from the stub providers in ADR-010: stubs return safe defaults for missing features, while this provider crashes intentionally because the database is a hard dependency.

## Consequences

- Cold start is slightly longer (database opens during splash screen) — acceptable for SQLite which opens in milliseconds.
- No `AsyncValue` handling needed in any database consumer — simpler widget code.
- Tests must provide the override: `ProviderScope(overrides: [storageServiceProvider.overrideWithValue(mockStorage)])`.
- If a second async service needs pre-runApp initialization, the same pattern applies in `main()`.
