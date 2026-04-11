# ADR-DATA-003: Plain Dart models with manual serialization

Status: Accepted
Proposed in: P004

## Context

Models need to be serialized for SQLite storage and potentially for JSON API communication. Dart offers several approaches:

- **Manual `fromMap`/`toMap`** — hand-written conversion methods.
- **json_serializable** — codegen-based JSON serialization.
- **freezed** — codegen for immutable data classes with copyWith, equality, and serialization.

## Decision

All models are plain Dart classes with hand-written `fromMap(Map<String, dynamic>)` factory constructors and `toMap()` methods. No codegen (freezed, json_serializable).

## Rationale

The model count is small and the serialization logic is straightforward (flat maps to/from SQLite columns). Codegen would add build_runner to the dev loop for minimal benefit. Consistent with ADR-001's no-codegen stance.

## Consequences

- `fromMap`/`toMap` must be kept in sync with database schema manually.
- No auto-generated `copyWith`, `==`, or `hashCode` — written by hand where needed.
- Model tests verify serialization round-trips.
- If model count grows significantly, freezed can be adopted incrementally.
