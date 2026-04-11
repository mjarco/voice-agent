# ADR-AUDIO-006: Session-scoped immutable VAD configuration

Status: Accepted
Proposed in: P013

## Context

Hands-free mode exposes five tunable VAD parameters (pre-roll, hangover, min speech duration, max segment duration, cooldown). These are user-adjustable in settings. The question: when do config changes take effect?

- **Live update** — changes apply immediately to the running session. Requires resetting VAD state machine mid-frame.
- **Session-scoped** — config is captured at `engine.start()` and immutable for the session duration. Changes apply on next session start.

## Decision

`VadConfig` is a value class captured at `engine.start()` time. Configuration is immutable for the duration of a hands-free session. Changes in settings take effect on the next session start.

`VadConfig` provides a `clamp()` instance method that returns a new `VadConfig` with all fields clamped to valid ranges, guarding against corrupted or out-of-range values from SharedPreferences.

## Rationale

Changing VAD thresholds mid-frame would require resetting the internal state machine (frame counters, hangover state), creating a class of bugs where the previous state is incompatible with new thresholds. Session-scoped immutability is simpler, predictable, and sufficient — users adjust settings between sessions, not during active listening.

## Consequences

- Users must restart hands-free mode to see config changes — acceptable UX since settings are rarely changed during active use.
- `VadConfig.clamp()` provides a safety net against corrupted persistence values.
- Five parameters are persisted as flat SharedPreferences keys — no nested serialization.
- Testing can inject arbitrary VadConfig values without mocking SharedPreferences.
