# ADR-ARCH-006: Domain port pattern for platform services in core

Status: Accepted
Proposed in: P015, P016

## Context

Multiple features need access to platform capabilities (text-to-speech, audio feedback). If these services live in a feature module, other features cannot import them without violating ADR-003.

Two options:

- **Feature-owned services** — TTS in features/tts/, audio feedback in features/audio_feedback/. Other features import across boundaries.
- **Core domain ports** — abstract service interfaces in core/ with implementations wired via Riverpod. All features access through core providers.

## Decision

Platform services that are consumed by multiple features are defined as abstract interfaces (domain ports) in core/:

- `TtsService` in `core/tts/` — abstraction over `flutter_tts`.
- `AudioFeedbackService` in `core/audio_feedback/` — abstraction over `audioplayers`.

Implementations live alongside their interfaces in core. Providers are in core so all features can import without cross-feature violations.

## Rationale

These services are shared infrastructure, not feature-specific logic. Placing them in core follows the same principle as `StorageService` and `ApiClient` — they serve multiple consumers and belong in the shared layer.

## Consequences

- Adding a new platform service follows this pattern: interface + implementation + provider in core/.
- Core's dependency footprint grows with each platform service — acceptable if the service is genuinely shared.
- Single-consumer services should stay in their feature module until a second consumer appears.
- Implementations are thin adapters — business logic stays in controllers.
