# ADR-AUDIO-003: Local VAD with chunked cloud STT for hands-free mode

Status: Accepted
Proposed in: P012

## Context

Hands-free mode needs to detect when the user is speaking and transcribe each speech segment. Three approaches were considered:

1. **Amplitude threshold** — simple RMS-based detection. Unreliable in varying noise environments.
2. **Local VAD + chunked cloud STT** — local voice activity detection segments audio; each segment is sent to Groq for transcription independently.
3. **Provider-side streaming** — send continuous audio to a cloud provider that handles VAD and streaming transcription. Requires fundamental architecture change (streaming vs file-based).

## Decision

Option 2: local VAD for speech detection, combined with chunked cloud STT via Groq. Speech detection runs locally in real-time; recognized segments are uploaded as individual WAV files to Groq for transcription.

`VadService` is a synchronous frame classifier — `classify(Uint8List frame)` must not block the audio stream. It defines a `frameSize` in bytes for the expected input chunk size.

## Rationale

Separating detection (local, real-time) from recognition (cloud, per-segment) preserves the existing file-based STT architecture (ADR-005). Amplitude thresholds are too unreliable for real use. Provider streaming would require replacing the entire STT pipeline and sync architecture.

## Consequences

- Two layers: `VadService` (local, synchronous) and `GroqSttService` (cloud, async per-segment).
- Segment boundaries are determined by VAD heuristics: pre-roll, hangover, min speech duration, max segment duration, cooldown.
- Segments are queued with a serial STT slot — one transcription at a time.
- Segment job state machine: QueuedForTranscription -> Transcribing -> Persisting -> Completed/Rejected/Failed.
- Network required for transcription — no offline hands-free.
