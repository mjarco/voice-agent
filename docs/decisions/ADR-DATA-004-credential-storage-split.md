# ADR-DATA-004: Credential storage split between SharedPreferences and flutter_secure_storage

Status: Accepted
Proposed in: P006

## Context

The settings screen persists several values: API URL, API token, display preferences. These have different security requirements:

- **API URL and display settings** — not sensitive, need fast synchronous reads.
- **API token** — sensitive credential, should use platform keychain/keystore.

## Decision

- Non-sensitive settings (API URL, display preferences) are stored in `SharedPreferences`.
- Sensitive credentials (API token, Groq API key) are stored in `flutter_secure_storage`, which uses iOS Keychain and Android Keystore.

Settings auto-save on field change (no save button). Token saves on focus loss.

## Rationale

`flutter_secure_storage` provides platform-level encryption for secrets but has async access and slower reads. `SharedPreferences` is synchronous and fast but stores values in plaintext XML/plist. The split matches security requirements to storage capabilities.

## Consequences

- Two storage backends to initialize and manage.
- `AppConfigNotifier` uses a `Completer`-based `loadCompleted` Future to ensure async secure storage load finishes before config is read.
- Test setup must mock or override both storage backends.
- All secret values go through `flutter_secure_storage` — no exceptions.
