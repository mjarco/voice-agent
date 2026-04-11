# ADR-AUDIO-004: Separate hands-free session model from manual recording

Status: Accepted
Proposed in: P012, P014

## Context

The app supports two recording modes: manual (tap-to-record / press-and-hold) and hands-free (VAD-driven continuous listening). These modes have fundamentally different lifecycles:

- Manual recording: user-initiated start/stop, single audio file, single transcript.
- Hands-free: continuous listening with automatic segmentation, multiple audio segments, multiple transcripts per session.

Two design options:

- **Unified state machine** — extend `RecordingState` with hands-free states. Simpler provider graph but complex state transitions.
- **Separate session model** — dedicated `HandsFreeSessionState` with its own lifecycle. More types but cleaner separation.

## Decision

Hands-free mode uses a separate sealed class `HandsFreeSessionState` with its own lifecycle states (Idle, Listening, Capturing, Stopping, WithBacklog, Error). `HandsFreeOrchestrator` manages its own `AudioRecorder` instance, separate from `RecordingServiceImpl`.

Manual and hands-free modes are mutually exclusive. The UI enforces this, with a defence-in-depth guard preventing both from being active simultaneously.

## Rationale

The two modes have different state machines, different output cardinality (one vs many segments), and different user interaction patterns. Merging them into one state machine would create a combinatorial explosion of transitions. Separate models make each mode independently testable and evolvable.

## Consequences

- Two `AudioRecorder` instances exist in the app — only one is active at a time.
- `HandsFreeOrchestrator` owns its recorder lifecycle independently.
- P014 added suspend/resume: `suspendForManualRecording()` / `resumeAfterManualRecording()` allow manual recording to temporarily take over the microphone while preserving the hands-free job backlog.
- Adding new recording modes would follow the same pattern — new session model, new orchestrator.
