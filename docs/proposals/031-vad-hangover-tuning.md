# Proposal 031 — VAD Hangover Tuning and Dynamic Adjustment

## Status: Draft (seed)

## Origin

Conversation 2026-04-22. During a live test session, utterances were
fragmented — VAD treated natural pauses as end-of-speech and sent partial
segments to STT. Tested 10 s -> 1000 ms -> 800 ms; 800 ms was the best
compromise between natural pause tolerance and agent reaction latency.

## Prerequisites

- 012-hands-free-local-vad — VAD engine and session model
- 013-vad-advanced-settings — user-facing VAD config (hangover slider)

Both are implemented.

**No cross-project dependency.** This is entirely client-side.

## Scope

- Risk: Medium — hangover changes affect perceived responsiveness of the
  entire hands-free flow; too long feels sluggish, too short fragments speech
- Layers: `core/audio/` (VAD engine adapter), `core/config/` (VadConfig),
  `features/settings/` (advanced settings UI), `features/recording/`
  (hands-free controller and orchestrator)
- Expected PRs: 2 (metrics collection, then dynamic adjustment)

## Problem Statement

The code default for hangover is 500 ms (`VadConfig.defaults()` in
`core/config/vad_config.dart:18`). During the 2026-04-22 test session, the
user manually tuned the slider to 800 ms, which worked better for their
speech pattern. The 500 ms default was chosen in P013 as a reasonable
starting point, but:

1. Different speakers have different pause patterns — a fast speaker pauses
   ~300 ms between sentences; a deliberate speaker pauses ~1200 ms.
2. Noisy environments cause the VAD to see micro-pauses as silence, leading
   to more fragmentation at the same hangover value.
3. Conversational context matters — after an open-ended question from the
   agent, the user is more likely to pause while thinking.

Without data from real usage, any fixed default is a guess. Without dynamic
adjustment, the user must manually tune the slider for each environment.

## Research Needed

Before designing the solution, collect data:

1. **Fragmentation metrics.** Track per-session: total segments sent to STT,
   segments that arrived within N seconds of each other from the same
   utterance (heuristic: same conversation turn), average segment duration,
   and the active `VadConfig` snapshot (at minimum `hangoverMs`).
   Without recording the active hangover value, correlating fragmentation
   data with the configured setting is impossible — especially since P013
   lets users change it via the slider.
2. **Industry benchmarks.** Research typical hangover values in production
   voice assistants (Alexa: ~700-1000 ms reported; Google Assistant: adaptive;
   Siri: undocumented). Document findings in the proposal before implementation.
3. **User feedback.** After 1+ week of real usage with the user's configured
   hangover value, review whether fragmentation is a practical problem or
   acceptable.

## Proposed Direction

### Phase 1 — Metrics (T1)

Add lightweight fragmentation tracking to `HandsFreeController`:

- Count segments per hands-free session
- Track inter-segment gaps (time between `EngineSegmentReady` events)
- Capture the active `VadConfig` snapshot at session start (at minimum
  `hangoverMs`) so metrics can be correlated with the configured value
- Log a structured session summary on `stopSession()` via `debugPrint` of
  a JSON-formatted object: total segments, mean/max gap, fragmentation
  ratio (multi-segment turns / total turns), active hangover value
- No persistent storage in v1. If Phase 2 needs queryable history for
  calibration, define a storage approach in the Phase 2 design after
  reviewing Phase 1 data

No user-visible change. Data collection only.

### Phase 2 — Dynamic Hangover (T2)

Based on Phase 1 data, implement one of:

**Option A — Adaptive hangover (preferred if data supports it):**
Formula: `hangover = base + (noise_proxy * scaling)`
- `base`: user-configured default (whatever the slider says)
- `noise_proxy`: needs research — Silero VAD exposes per-frame speech
  probability (float 0-1), not a noise level estimate. Low probability
  during non-speech could mean silence or noise. **Research question:** Does
  Silero's frame-level probability distribution during non-speech segments
  correlate with ambient noise level? If not, what other signal could serve
  as a noise proxy (e.g., audio energy level from raw PCM)?
- `scaling`: calibration constant, tuned from Phase 1 data
- Clamp to [400 ms, 3000 ms] — note: the current `VadConfig.clamp()` uses
  [100, 2000]; if dynamic adjustment can push beyond 2000 ms, the upper
  bound in `VadConfig.clamp()` must be updated

**Option B — Pragmatic (if data shows current default is good enough):**
- Change default from 500 ms to whatever the Phase 1 data suggests is
  optimal across sessions
- Add an "auto" option to the hangover slider that applies Option A
- Keep manual override as-is

Context-aware hangover (adjusting based on agent question type) was
considered but is **out of scope** for this proposal. It would require
`SyncWorker` (in `features/api_sync/`) to relay question-type metadata to
`HandsFreeController` (in `features/recording/`), which is a cross-feature
dependency. If needed, a future proposal should route this signal through a
shared provider in `core/` (same pattern as `agentReplyProvider`).

### ADR Impact

- **ADR-AUDIO-006 (session-scoped immutable VAD config):** If dynamic
  hangover adjusts mid-session (Option A), this ADR needs amendment — the
  hangover would become the one mutable parameter within a session. If
  adjustment happens only at session start (based on last session's metrics),
  the ADR is preserved. Phase 1 data will inform which approach is needed.

## Acceptance Criteria (Phase 1)

1. On `stopSession()`, a JSON-formatted session summary is logged via
   `debugPrint` containing: total segments, mean inter-segment gap, max
   inter-segment gap, fragmentation ratio, active `hangoverMs`.
2. Metrics collection adds no disk I/O on the audio processing path —
   counters and timestamps only.
3. `make verify` passes. No cross-feature imports.
4. Phase 2 acceptance criteria will be defined after Phase 1 data review.

## Risks

| Risk | Mitigation |
|------|------------|
| Metrics collection overhead affects real-time audio performance | Keep it to in-memory counters and timestamps; no disk I/O, no allocations on the audio path. Log only on session stop. |
| Phase 2 dynamic adjustment conflicts with user's manual slider (P013) — which takes precedence? | "Auto" mode is opt-in; when selected, dynamic adjustment overrides the slider value. When slider is manually set, dynamic adjustment is disabled. |
| Option A mid-session mutation violates ADR-AUDIO-006 | Phase 1 data will show whether mid-session adjustment is actually needed or session-start adjustment suffices. If ADR amendment is needed, it goes through architectural review. |
| Noise proxy from Silero probability is unvalidated | Explicitly flagged as a research question. Phase 1 data may reveal a simpler heuristic (e.g., fragmentation ratio alone). |

## Tasks

| # | Task | Layer | Notes |
|---|------|-------|-------|
| T1 | Add fragmentation metrics logging to `HandsFreeController`. Capture segment count, inter-segment gaps, active `hangoverMs`. Log JSON summary on `stopSession()`. | features/recording, core/config | Mergeable alone. No user-visible change. |
| T2 | (After >= 1 week of T1 data) Design and implement dynamic hangover based on Phase 1 findings. Update `VadConfig.clamp()` if range changes. Amend ADR-AUDIO-006 if mid-session mutation is chosen. | core/config, features/recording, features/settings | Depends on T1 data. Separate proposal revision before implementation. |

## Dependencies

| Dependency | Status | Blocking? |
|---|---|---|
| 012-hands-free-local-vad | Implemented | No |
| 013-vad-advanced-settings | Implemented | No |
| ADR-AUDIO-006 | Accepted | May need amendment in Phase 2 |

## When to Address

Phase 1 (metrics) can start immediately. Phase 2 (dynamic adjustment)
depends on Phase 1 data — at least 1 week of real usage.

## Related

- P000-backlog entry "VAD hangover tuning"
- 012-hands-free-local-vad
- 013-vad-advanced-settings
- ADR-AUDIO-006-immutable-vad-config
