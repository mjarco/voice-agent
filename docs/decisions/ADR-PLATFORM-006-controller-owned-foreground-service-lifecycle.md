# ADR-PLATFORM-006: Foreground service lifecycle owned by session controller

Status: Proposed
Proposed in: P026

## Context

The Android foreground service and iOS `playAndRecord` audio session are the
platform-level keepalive mechanisms that prevent the OS from suspending the app
process during active hands-free recording. P019 wired these to
`ActivationController`'s state machine via a `controller.addListener` block in
the provider factory (a generic state-listener pattern). With P026,
`ActivationController` is deleted; the only consumer of the keepalive is
`HandsFreeController`'s session lifecycle.

Two mechanisms were considered for triggering start/stop:

- **State-listener in provider factory:** `controller.addListener` fires after
  state transitions, calling `BackgroundService.startService` when state leaves
  `HandsFreeIdle` and `stopService` when it returns.
- **Explicit calls inside controller methods:** `HandsFreeController.startSession`
  awaits `BackgroundService.startService` BEFORE calling `_startEngine`, and
  `stopSession` / `_terminateWithError` await `BackgroundService.stopService`
  before transitioning state.

The state-listener approach has an iOS-specific ordering problem: the listener
fires AFTER state transitions to a non-idle variant, which happens AFTER
`orchestrator.start()` emits `EngineListening`, which happens AFTER audio capture
has begun. ADR-AUDIO-009 requires the iOS `playAndRecord` category to be set
BEFORE capture for correct `allowBluetooth` and microphone-routing options.

## Decision

Controllers that own platform keepalive lifecycle call
`BackgroundService.startService()` / `stopService()` explicitly at session
boundaries. They do NOT delegate this responsibility to a generic state
listener attached to their notifier.

Specifically for `HandsFreeController`:

- `startSession()` awaits `BackgroundService.startService()` AFTER guards pass
  and BEFORE `_startEngine()`.
- `stopSession()` awaits `BackgroundService.stopService()` at the start of the
  method (after the idle guard returns early).
- `_terminateWithError()` calls `BackgroundService.stopService()` (fire-and-forget
  via `unawaited` is acceptable; see Consequences).

## Rationale

Explicit-call ordering satisfies ADR-AUDIO-009's "category set BEFORE capture"
requirement. State-listener mechanism cannot satisfy it because the listener
fires after the engine has emitted its first event. The explicit pattern also
makes the call sequence visible at the call site, which is easier to reason
about than a side effect attached to a state transition in a provider factory.

The explicit pattern conflicts with the generic listener pattern established by
the now-deleted `activation_provider.dart` (see ADR-ARCH-009). That precedent
is overridden by ADR-AUDIO-009's ordering requirement; the listener pattern
remains suitable for downstream side effects that do not need to precede
capture, but not for audio-session category switching.

## Consequences

- `HandsFreeController` takes a direct dependency on `BackgroundService` via
  `Ref`. The dependency is read on demand (not injected at construction) to
  avoid widening the constructor.
- `_terminateWithError()` is synchronous and uses `unawaited(stopService())`.
  The next `startSession()` awaits `startService()`, which is idempotent
  (`BackgroundService.startService` returns early when already running).
- Tests must verify call ORDER (`startService` before `_startEngine`,
  `stopService` before `HandsFreeIdle` transition), not just call counts.
  A tracking stub that records call timestamps suffices.
- This pattern applies whenever a controller starts a platform capability
  that requires preconditions (audio session, background service, sensor).
  For controllers that only need to react to state transitions without
  preconditions, the listener pattern in ADR-ARCH-009 is still valid.
