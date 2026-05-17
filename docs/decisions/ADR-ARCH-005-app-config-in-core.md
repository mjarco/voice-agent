# ADR-ARCH-005: App configuration ownership in core layer

Status: Accepted
Proposed in: P009
Amended in: P040 (cross-isolate-safe property)

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

## P040 amendment — cross-isolate-safe property

`AppConfigService` (SharedPreferences-backed) is the **cross-isolate-safe**
configuration store: it can be read from background isolates (e.g., the
workmanager agenda-refresh task per ADR-NET-002 P040 amendment and
ADR-PLATFORM-007) without re-opening SQLite or re-parsing on-disk cache
files. SharedPreferences is platform-isolate-safe and lightweight; reads
complete in microseconds with no async setup beyond the standard plugin
initialization.

`SqliteStorageService` also works from a background isolate (the SQLite
plugin is platform-isolate-safe), but it is the heavier choice — full DB
open, schema check, possible migration — and is reserved for data that
genuinely needs a relational store.

**Rule of thumb:** scalar config values used by short-lived background
tasks belong in `AppConfigService`. Structured records that need queries
or schemas belong in `SqliteStorageService`. P040 added `lastAgendaFetchAt`
to `AppConfigService` under this rule; the value is read by both the
foreground staleness check and the background isolate's 50-min skip
guard.
