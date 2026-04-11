# ADR-AUDIO-005: Microphone exclusivity and WAV file ownership

Status: Accepted
Proposed in: P012

## Context

The app has two AudioRecorder instances (manual recording and hands-free orchestrator) and produces WAV temp files that flow through the STT pipeline. Two concerns:

1. **Microphone access** — iOS and Android allow only one active audio capture session. Concurrent access causes platform exceptions.
2. **File cleanup** — WAV files written to temp directories must be deleted after use to prevent storage leaks.

## Decision

**Microphone exclusivity:** at most one AudioRecorder is active at any time. Mutual exclusivity is enforced at the UI level (mode switching) with defence-in-depth guards (orchestrator checks before starting). P014's suspend/resume pattern explicitly stops the hands-free recorder before starting manual recording.

**WAV file ownership contract:**
- `GroqSttService` deletes files that reach the Transcribing state (in `finally`, regardless of success/failure).
- The controller deletes files for Rejected jobs (too short, empty transcript).
- No WAV file survives beyond session end.

## Rationale

Platform audio APIs enforce single-capture at the OS level — attempting concurrent capture throws exceptions. Making exclusivity explicit in the app logic prevents cryptic platform errors. The file ownership contract prevents both leaks (nobody deletes) and double-deletes (multiple owners).

## Consequences

- Starting manual recording requires stopping hands-free first — adds latency to mode switches.
- Every code path that produces a WAV file must have a corresponding deletion path.
- File deletion failures are logged but not fatal — OS temp cleanup provides a safety net.
- Testing must verify file cleanup for all job terminal states.
