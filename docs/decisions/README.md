# Architecture Decision Records

This directory contains architectural decisions for the voice-agent mobile app.
Each ADR documents one significant decision: the context that forced it, the option chosen, and the trade-offs accepted.

## What belongs in an ADR

We follow Michael Nygard's original definition: an ADR captures a decision that
affects the system's **structure, non-functional characteristics, dependencies,
interfaces, or construction techniques** — in short, a decision that would be
costly to reverse (Grady Booch) or that you wish you could get right early
(Martin Fowler).

A good litmus test: *would someone in the future wonder "why did we do it this
way?" and not find the answer in the code or git history?* If yes, write an ADR.

**In scope:**

- Domain model decisions — how concepts are represented, what they mean, and how they relate
- Data model choices (e.g. separate field vs embedding in an existing structure)
- Persistence strategies (SQLite schema design, storage backend selection)
- Architecture boundary and package layout decisions
- Integration patterns (sync vs async, file-based vs streaming)
- Interface contracts that constrain future evolution
- Platform-specific decisions (audio session categories, permission handling)

**Out of scope:**

- Adding or removing individual screens or routes (documented in router.dart)
- Bug fixes, refactors, and implementation details recoverable from code and git
- Temporary workarounds or experiments
- Decisions already captured in external standards or libraries

## Format

Each ADR uses the Context / Decision / Rationale / Consequences structure. Keep them concise
and focused on a single decision. See any existing ADR for reference.


### ARCH — Architecture & Dependency Injection

| ADR | Title | Status |
| --- | ----- | ------ |
| [ADR-ARCH-001](ADR-ARCH-001-riverpod-manual-providers.md) | Riverpod with manual providers, no codegen | Accepted |
| [ADR-ARCH-002](ADR-ARCH-002-gorouter-stateful-shell-route.md) | GoRouter with StatefulShellRoute navigation | Accepted |
| [ADR-ARCH-003](ADR-ARCH-003-layered-feature-isolation.md) | Layered architecture with strict feature isolation | Accepted |
| [ADR-ARCH-004](ADR-ARCH-004-stub-provider-pattern.md) | Stub provider pattern for incremental delivery | Accepted |
| [ADR-ARCH-005](ADR-ARCH-005-app-config-in-core.md) | App configuration ownership in core layer | Accepted |
| [ADR-ARCH-006](ADR-ARCH-006-domain-port-pattern.md) | Domain port pattern for platform services | Accepted |
| [ADR-ARCH-007](ADR-ARCH-007-async-db-init-before-runapp.md) | Async DB init before runApp | Accepted |

### AUDIO — Audio, STT & Recording

| ADR | Title | Status |
| --- | ----- | ------ |
| [ADR-AUDIO-001](ADR-AUDIO-001-16khz-mono-wav-format.md) | 16kHz mono PCM WAV as canonical audio format | Accepted |
| [ADR-AUDIO-002](ADR-AUDIO-002-cloud-stt-groq.md) | Cloud STT via Groq replacing on-device Whisper | Accepted |
| [ADR-AUDIO-003](ADR-AUDIO-003-local-vad-chunked-stt.md) | Local VAD with chunked cloud STT for hands-free | Accepted |
| [ADR-AUDIO-004](ADR-AUDIO-004-separate-hands-free-model.md) | Separate hands-free session model | Accepted |
| [ADR-AUDIO-005](ADR-AUDIO-005-microphone-exclusivity-file-ownership.md) | Microphone exclusivity and WAV file ownership | Accepted |
| [ADR-AUDIO-006](ADR-AUDIO-006-immutable-vad-config.md) | Session-scoped immutable VAD configuration | Accepted |
| [ADR-AUDIO-007](ADR-AUDIO-007-ios-ambient-audio-session.md) | iOS ambient audio session category for playback | Accepted |
| [ADR-AUDIO-008](ADR-AUDIO-008-eager-audio-file-deletion.md) | Eager audio file deletion after transcription | Accepted |

### DATA — Storage & Persistence

| ADR | Title | Status |
| --- | ----- | ------ |
| [ADR-DATA-001](ADR-DATA-001-sqlite-sqflite-raw-sql.md) | SQLite via sqflite with raw SQL, no ORM | Accepted |
| [ADR-DATA-002](ADR-DATA-002-sync-queue-delete-on-sent.md) | Sync queue state machine with delete-on-sent | Accepted |
| [ADR-DATA-003](ADR-DATA-003-plain-dart-models.md) | Plain Dart models with manual serialization | Accepted |
| [ADR-DATA-004](ADR-DATA-004-credential-storage-split.md) | Credential storage split | Accepted |
| [ADR-DATA-005](ADR-DATA-005-device-id-uuidv4.md) | Device ID as UUIDv4 in SharedPreferences | Accepted |

### NET — Network & Sync

| ADR | Title | Status |
| --- | ----- | ------ |
| [ADR-NET-001](ADR-NET-001-dio-sealed-error-classification.md) | Dio HTTP client with sealed ApiResult error classification | Accepted |
| [ADR-NET-002](ADR-NET-002-foreground-only-sync.md) | Foreground-only sync with no background processing | Accepted |

### PLATFORM — Mobile Platform & UX

| ADR | Title | Status |
| --- | ----- | ------ |
| [ADR-PLATFORM-001](ADR-PLATFORM-001-direct-save-without-review.md) | Direct save without review screen | Accepted |
| [ADR-PLATFORM-002](ADR-PLATFORM-002-cancel-on-background.md) | Cancel-on-background policy for recording | Accepted |
| [ADR-PLATFORM-003](ADR-PLATFORM-003-permission-via-record-package.md) | Microphone permission via record package | Accepted |
