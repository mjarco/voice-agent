# ADR-DATA-007: Backend API models in core/models with external ownership

Status: Proposed
Proposed in: P025

## Context

The app needs Dart models for data returned by the personal-agent REST API (conversations, routines, agenda items, plan entries, knowledge records). These models mirror the backend's JSON response shapes. Unlike existing core models (`Transcript`, `SyncQueueItem`) whose schema is defined by the mobile app's SQLite schema, these models have external ownership — the Go backend defines the canonical shape.

Two placement options:

- **Feature-specific models** — each feature (agenda, plan, routines) defines its own models in `features/{name}/domain/`. Isolated but leads to duplication when multiple features share types (e.g., `RecordType`, `RoutineTemplate`).
- **Core shared models** — models in `core/models/`, available to all features. Single source of truth for shared types.

## Decision

Backend API response models live in `core/models/` alongside app-owned models. They follow the same conventions (ADR-DATA-003): plain Dart classes with `fromMap()`/`toMap()`, no codegen. Field names in `fromMap()` use snake_case keys matching the backend's JSON serialization.

Models are a subset of the backend's types — only fields needed by the mobile UI are included. `fromMap()` ignores unknown keys (forward compatibility). Missing optional fields use sensible defaults (e.g., `templates` defaults to `[]`).

## Rationale

Multiple features consume overlapping types: `RoutineTemplate` is used by both Agenda and Routines; `RecordType` and `RecordStatus` enums span Plan, Agenda, and Conversations. Placing shared types in core avoids duplication and cross-feature imports.

The ownership distinction (backend-defined vs. app-defined) does not require a separate directory — the naming and file-level documentation make the provenance clear. If the model count grows significantly, a `core/models/api/` subdirectory could be introduced.

## Consequences

- Backend API changes (field renames, removals) require updating core models. Field additions are safe (ignored by `fromMap()`).
- `core/models/` contains both app-owned and backend-owned types. File-level doc comments should note the backend source (e.g., "Matches personal-agent's `routineResponse` struct").
- Round-trip serialization tests verify `fromMap()`/`toMap()` against expected JSON shapes. These tests serve as contract verification: if the backend shape changes, the test fails.
- Models are DTOs, not rich domain objects. Business logic (display formatting, filtering, sorting) belongs in feature controllers, not in the model classes.
