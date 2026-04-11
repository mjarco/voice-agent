# ADR-ARCH-003: Layered architecture with strict feature isolation

Status: Accepted
Proposed in: P000, P009

## Context

The app needs a module structure that prevents spaghetti imports as features grow. Two common approaches:

- **Flat structure** — all code in a few top-level directories (models, screens, services). Simple but imports become unrestricted.
- **Feature-first with layered core** — each feature is a self-contained module; shared code lives in a core layer. Features cannot import from each other.

## Decision

Three top-level layers with a strict dependency rule:

```
features/  ->  core/  <-  app/
features/ do NOT import from other features/
```

- **core/** — shared models, storage, network, providers. Imports nothing from features/ or app/.
- **features/** — self-contained feature modules (recording, transcript, api_sync, history, settings). Each imports only from core/ and its own directory.
- **app/** — app-level configuration (router, theme, root widget). Imports from core/ and features/.

Each feature follows an internal `data/`, `domain/`, `presentation/` structure.

## Rationale

Feature isolation prevents coupling between independent concerns. When P009 code review found cross-feature imports (settings -> recording, core -> features), the violations were fixed by moving shared types (e.g. `AppConfig`) to core. The rule is enforced by grep checks in the CLAUDE.md.

## Consequences

- Shared types must live in core/, even if initially used by only one feature.
- Communication between features goes through core providers, never direct imports.
- Violation of the dependency rule is a merge blocker.
- Adding a new feature is low-risk — it cannot break existing features.
