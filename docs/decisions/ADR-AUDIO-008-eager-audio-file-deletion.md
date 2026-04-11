# ADR-AUDIO-008: Eager audio file deletion after transcription

Status: Accepted
Proposed in: P001, P012

## Context

The app produces WAV files during recording that flow through the STT pipeline. After transcription, the audio file is no longer needed for the current workflow. Options:

- **Retain audio** — keep WAV files for replay, re-transcription, or sending to the user's API alongside the text. Requires storage management, disk space monitoring, and cleanup policies.
- **Eager delete** — delete the WAV file immediately after transcription, in all code paths. Only the text transcript survives.

## Decision

Delete audio files eagerly. Every code path that produces a WAV file has a corresponding deletion:

- `GroqSttService.transcribe()` deletes the file in a `finally` block regardless of success or failure.
- `RecordingServiceImpl.cancel()` deletes the partial file.
- `HandsFreeController` deletes WAV files for rejected jobs (too short, empty transcript).

No audio file survives beyond the operation that consumes it.

## Rationale

Retaining audio requires disk space management (WAV at 16kHz mono is ~1.9 MB/min), a cleanup policy, and UI for replaying recordings. For a voice-to-text app that sends only text to the backend, audio retention adds complexity with no current use case. Eager deletion also enhances privacy — no voice recordings persist on the device.

## Consequences

- No "replay original audio" feature possible — text is the only artifact.
- No re-transcription with different settings — would require re-recording.
- Audio is not sent to the user's API — only text, timestamp, language, and device ID.
- No disk space accumulation from audio files.
- Enhanced privacy: no voice recordings persist on device after transcription.
- If audio retention is needed later, the deletion points must be replaced with a storage + cleanup system.
