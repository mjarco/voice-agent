# ADR-ARCH-008: Ephemeral cross-feature state via core StateProvider

Status: Accepted
Proposed in: P017

## Context

Features sometimes need to communicate ephemeral state that does not belong in persistent configuration. For example, P017 needs `features/api_sync` to emit the agent's text reply so that `features/recording` can display it. This state is transient — it resets on user action, has no persistence, and carries no domain semantics beyond "the latest value."

Two options:

- **Feature-to-feature import** — one feature exposes the state, the other imports it. Violates ADR-ARCH-003 (feature isolation).
- **Core StateProvider** — a `StateProvider` in `core/providers/` acts as a decoupled channel. The producing feature writes; the consuming feature watches. No cross-feature imports.

## Decision

Ephemeral cross-feature state uses `StateProvider` (or `StateNotifierProvider`) in `core/providers/`. The provider name should describe the value it carries (e.g., `latestAgentReplyProvider`), not the producer or consumer.

Rules:
- The provider must be in `core/providers/`, never in a feature.
- The provider's default value must be a safe no-op (e.g., `null`, empty list).
- The producing feature writes via `ref.read(provider.notifier).state = value`.
- The consuming feature watches via `ref.watch(provider)`.
- Ephemeral providers are NOT for persistent or configuration state — those belong in `core/config/` per ADR-ARCH-005.

## Rationale

This is the minimal mechanism for cross-feature communication that respects feature isolation. Riverpod's `StateProvider` provides reactivity, testability (via overrides), and no coupling between producer and consumer. The alternative — event buses, streams, or shared services — adds infrastructure for what is a simple value-passing problem.

## Consequences

- `core/providers/` may accumulate ephemeral state providers as features grow. If the count becomes unmanageable, a `core/state/` directory can be introduced.
- Ephemeral state is lost on app restart — by design. If persistence is needed, the state should migrate to `core/config/` or `core/storage/`.
- Testing uses `ProviderScope(overrides: [provider.overrideWith(...)])` — same as configuration providers.
- Each ephemeral provider should document its producer(s) and consumer(s) in a doc comment.
