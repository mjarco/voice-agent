# ADR-ARCH-004: Stub provider pattern for incremental feature delivery

Status: Accepted
Proposed in: P005, P008

## Context

Features are built incrementally across proposals. Some features depend on configuration or services that don't exist yet. For example:

- P005 (API sync) needs the API URL, but P006 (settings screen) hasn't been built yet.
- P008 (navigation shell) needs to know if the API URL is configured, but P006 doesn't exist yet.

Blocking implementation until dependencies are ready would serialize all development.

## Decision

Use stub providers that return safe defaults, to be replaced by real implementations in later proposals. Both original stubs have been replaced by P006:

- `apiConfigProvider` (P005) originally returned `ApiConfig(url: null)` — now reads from `appConfigProvider`.
- `apiUrlConfiguredProvider` (P008) originally returned `false` — now checks `config.apiUrl`.

## Rationale

Stubs allow features to be built and tested in isolation with well-defined integration points. The stub's type signature is the contract — the replacement must match it exactly. This enables parallel proposal development without blocking.

## Consequences

- Each stub must be documented with its replacement target (which proposal replaces it).
- Stubs must return safe defaults (null URL, false for "configured") — never values that trigger real behavior.
- Replacing a stub is a one-line provider swap — no consumer changes needed.
- Orphaned stubs (never replaced) indicate incomplete feature delivery.
