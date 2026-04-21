# ADR-DATA-009: One-shot idempotent removal migration in `AppConfigService.load()`

Status: Proposed
Proposed in: P026

## Context

P026 removes five persisted settings (`wakeWordEnabled`, `picovoiceAccessKey`,
`wakeWordKeyword`, `wakeWordSensitivity`, `backgroundListeningEnabled`) and four
legacy IPC keys (`activation_state`, `activation_toggle_requested`,
`activation_stop_requested`, `foreground_service_running`) plus one SecureStorage
key (`picovoice_access_key`). Without explicit removal, these keys persist
forever in user installs even though no code reads them.

This is the project's first migration of any kind affecting `SharedPreferences`
or `flutter_secure_storage`. SQLite has `_onUpgrade` infrastructure (see
`SqliteStorageService`) that has not been exercised in production. The two
storage backends have different failure modes (SecureStorage delete can throw on
corrupted Keychain; SharedPreferences `remove` is effectively infallible).

## Decision

Removal migrations run synchronously inside `AppConfigService.load()` on first
launch of the version that introduces them, gated by a boolean flag in
SharedPreferences whose key encodes the migration identity:

```
if prefs.getBool('<migration_name>_done') == true: return
for each prefs key: prefs.remove(key)
for each secure storage key:
  try { await secureStorage.delete(key: ...) } catch (_) { log only }
prefs.setBool('<migration_name>_done', true)
```

The migration runs before `AppConfig` is constructed. SecureStorage delete
failures are swallowed (logged only) and the migration flag is set anyway, so
a failed delete does not block app start or re-trigger on next launch.

## Rationale

Synchronous in-load migration guarantees the migration runs before any consumer
reads `AppConfig`, so deleted-field defaults (e.g., `backgroundListeningEnabled
= false`) are never observed transiently. The blocking cost (~50–200 ms one-time,
dominated by the SecureStorage delete on iOS Keychain) is acceptable compared
to the alternatives (deferred migration with risk of incomplete cleanup, or a
separate init step duplicating the storage handles).

Per-migration named flags avoid a versioning scheme — appropriate for one-shot
removals. A versioning registry would be overkill for the expected migration
cadence (rare, one-off cleanup of abandoned features).

## Consequences

- Each removal migration adds one SharedPreferences flag that lives forever.
  After ~10 such migrations, `AppConfigService.load()` will have ~10 early-return
  checks. If that count grows further, a registry pattern (one flag per version,
  list of migrations per version) becomes attractive.
- SecureStorage delete failures are silently ignored. If a user has a stuck
  Keychain entry from a deleted feature, it persists across app launches until
  they reinstall or manually clear app data. Acceptable trade-off vs. blocking
  app start.
- Migration is one-direction. If a deleted feature is reintroduced later under
  the same key names, the migration will not re-run for users who already
  migrated; the reintroduced feature must either pick a different key namespace
  or accept that returning users start from defaults.
- This pattern is for SETTINGS removal only. Migrations that touch SQLite rows
  must use `_onUpgrade` in `SqliteStorageService`. Migrations that span both
  layers atomically need a separate design.
