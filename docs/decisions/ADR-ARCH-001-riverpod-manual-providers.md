# ADR-ARCH-001: Riverpod with manual providers, no codegen

Status: Accepted
Proposed in: P000

## Context

The app needs a state management solution. Flutter offers several options: setState, BLoC, Provider, Riverpod, and MobX.

Riverpod itself supports two styles:

- **Manual providers** — hand-written `Provider`, `StateNotifierProvider`, `FutureProvider` declarations.
- **Codegen** — `riverpod_generator` with `@riverpod` annotations that auto-generate provider boilerplate.

## Decision

Use `flutter_riverpod` with manually declared providers. No codegen (`riverpod_generator`, `build_runner`).

Controllers use `StateNotifier`. Providers are declared per-feature.

## Rationale

Codegen adds build_runner dependency, slower iteration, and generated files to review — unnecessary complexity for a project with a small number of providers. Manual providers make the dependency graph explicit and readable.

Riverpod was chosen over Provider for its compile-time safety, testability via `ProviderScope(overrides:)`, and independence from the widget tree.

## Consequences

- Every provider must be manually typed and declared — slightly more boilerplate per provider.
- No `build_runner` in the dev loop — faster iteration.
- Test setup uses `ProviderScope(overrides: [...])` for dependency injection.
- If the provider count grows significantly, codegen can be adopted later without changing runtime behavior.
