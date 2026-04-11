# ADR-ARCH-005: App configuration ownership in core layer

Status: Accepted
Proposed in: P009

## Context

P006 initially placed `AppConfig`, `AppConfigService`, and `AppConfigNotifier` in `features/settings/`. This caused cross-feature import violations: `features/api_sync/` needed to read the API URL from `features/settings/`, breaking ADR-003's feature isolation rule.

## Decision

All app configuration types (`AppConfig`, `AppConfigService`, `AppConfigNotifier`) live in `core/config/`. The settings feature (`features/settings/`) is a pure UI layer that reads and writes through core providers.

## Rationale

Configuration is consumed by multiple features (api_sync, recording, settings UI). Placing it in one feature forces other features to import across the boundary. Moving to core makes configuration a shared concern accessible to all features without violating the dependency rule.

## Consequences

- `features/settings/` contains only the settings screen and its presentation logic — no business logic or data types.
- All features access configuration through `core/config/` providers.
- Adding new configuration fields means modifying core, not a feature module.
