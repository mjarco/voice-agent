# ADR-DATA-001: SQLite via sqflite with raw SQL, no ORM

Status: Accepted
Proposed in: P004

## Context

The app needs local persistence for transcripts and a sync queue. Options considered:

- **sqflite with raw SQL** — direct SQLite access, full control, no codegen.
- **Drift (formerly Moor)** — type-safe ORM with codegen via build_runner.
- **Hive** — key-value store, no relational integrity.
- **Isar** — NoSQL with indexing, but lacks relational constraints.

The data model is small: two tables (transcripts, sync_queue) with a foreign key relationship.

## Decision

Use `sqflite` with raw SQL statements. No ORM, no codegen. Models use manual `fromMap`/`toMap` for serialization.

Foreign keys are enforced with `ON DELETE CASCADE` (deleting a transcript cascades to its sync_queue entry).

## Rationale

Two tables do not justify an ORM's codegen overhead. Raw SQL keeps the persistence layer transparent and debuggable. `sqflite` serializes writes internally, preventing concurrent write issues. Hive and Isar lack the relational integrity needed for the sync queue foreign key constraint.

## Consequences

- Schema changes require manual migration SQL.
- No compile-time query validation — SQL errors surface at runtime.
- `fromMap`/`toMap` must be kept in sync with schema manually.
- Database initialization is async and must complete before `runApp` — uses provider override pattern.
- Drift can be adopted later if the schema grows significantly.
