# ADR-AUDIO-002: Cloud STT via Groq replacing on-device Whisper

Status: Accepted
Proposed in: P002, P011

## Context

The original design (P002) used on-device Whisper via `whisper_flutter_new` for offline-first transcription. This required:

- A ~140MB bundled model asset inflating the app binary.
- Slow inference on mobile hardware (several seconds for short clips).
- Complex FFI integration with platform-specific build issues.

P011 re-evaluated after experiencing these costs in practice. The alternative: cloud-based STT via Groq's free-tier Whisper API, which offers fast inference with no local model.

## Decision

Replace on-device Whisper with Groq cloud STT as the primary engine. The `SttService` interface remains unchanged — `loadModel()` and `isModelLoaded()` become no-ops. The `GroqSttService` implementation uploads WAV files and parses the JSON response.

## Rationale

On-device Whisper was not viable for the target use case: the 140MB model bloated the app, inference was slow, and FFI integration was fragile across platforms. Groq's free tier covers the expected usage volume. The offline-first goal was deprioritized — the app already requires network for syncing transcripts to the backend.

## Consequences

- App binary size reduced by ~140MB.
- Transcription requires network connectivity — no offline STT.
- `SttService` interface preserved for potential future local STT re-introduction.
- `GroqSttService` receives `Ref` for lazy config reads — acknowledged as a layer boundary violation, documented for future cleanup.
- WAV temp files are deleted after upload in a `finally` block regardless of success/failure.
- API key stored in `flutter_secure_storage` alongside other credentials.
