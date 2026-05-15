# ADR-OBS-001: Dev-flavor telemetry singleton with build-time flavor gate

Status: Proposed
Proposed in: P039 — OpenTelemetry Dev-Flavor Telemetry

## Context

Voice-agent has no runtime observability — no Sentry, no crash reporter,
no structured logging that survives a force-quit. The 2026-05-07
mic-silent regression is currently unresolved because the device's
audio state machine is unreachable without a USB debug build.
Telemetry must (a) buffer locally across offline periods, (b) survive
force-quit, (c) be byte-identically absent from `stable` builds so a
personal-use production build carries no observability dependency.

ADR-ARCH-001 mandates Riverpod for all dependency wiring and
voice-agent CLAUDE.md states "Never use global singletons." A
telemetry facade that needs to be reachable from every layer (including
platform-channel callbacks that fire before any widget tree exists, and
from `main()` itself), and that must outlive Riverpod scopes and test
lifecycles, does not fit the Riverpod model.

## Decision

We carve out a single, named exception to the Riverpod-only rule.

### 1. Process-wide singleton

`Telemetry.instance` is a `static` field in
`lib/core/observability/telemetry.dart`, defaulting to the no-op
subtype at static initialisation. No Riverpod provider wraps it. The
facade exposes `event`, `span`, `counter`, `histogram` — call-sites
hold no reference; they reach the facade through the static field.

### 2. Build-time dev/stable gate via flavor-specific entrypoints

Two entrypoints, sharing a body via `appMain(Telemetry t)`:

- `lib/main_dev.dart` — reassigns `Telemetry.instance` to the
  OTel-backed subtype. Imports `package:opentelemetry`.
- `lib/main_stable.dart` — leaves the no-op default. Has no transitive
  import of `package:opentelemetry`.

The default `lib/main.dart` delegates to `main_stable.dart` so
`flutter test` and `flutter run` without an explicit `--target` get the
safe path.

The Android `dev` flavor and the iOS `Dev` xcconfig pass
`--target lib/main_dev.dart`; the `stable` flavor passes
`--target lib/main_stable.dart`.

### 3. Tree-shake acceptance test

`ops/scripts/verify-stable-tree-shake.sh` builds both flavors release
and asserts:
- `libapp.so` size delta ≥ ~150 KB between dev and stable (the real
  proof — OTel SDK + dependencies aren't in the stable AOT).
- `strings libapp.so | grep -i opentelemetry` on the stable build
  returns zero hits (smoke check; strings can survive even when code
  is dead, so this is sanity not proof).

The script is mandatory before merging any change to telemetry or to
the flavor build configs.

### 4. Hot-path rule

Per-frame and per-chunk code paths use counters and histograms only.
Spans are reserved for state transitions and request-scoped
operations. Any new instrumentation that fires at >10 Hz must justify
the choice in code review or convert to a counter.

### 5. Durable-by-default outbox

Spans are persisted to a SQLite `telemetry_outbox` table synchronously
on `onEnd` before the call returns; a separate flush worker drains the
table over OTLP/HTTP. This diverges from the in-memory
`BatchSpanProcessor` default for force-quit durability — see P039
§Offline buffering.

### 6. Telemetry flusher is exempt from ADR-NET-002

The flusher runs on its own 10s foreground / 60s background cadence
regardless of `sessionActiveProvider`. This exception is
dev-flavor-only. ADR-NET-002 carries the amendment recording this.

### 7. Reuse of `ApiClient.classifyStatusCode`

The flusher's HTTP error classification delegates to the existing
`ApiClient.classifyStatusCode` (public since P025).
`ApiTransientFailure` → retry with back-off; `ApiPermanentFailure` →
drop row + bump `telemetry_drop`. There is no parallel OTLP classifier.

## Rationale

Telemetry has properties no feature does: it must run before any
provider scope exists, it must survive widget-tree rebuilds, and it
must default to a safe no-op in every test without ceremony. A
Riverpod provider would either force every test to override it, or
rely on an "uninitialised-state" guard that defeats the purpose.

The flavor-entrypoint mechanism is preferred over conditional imports
because Dart's `import if (...)` only supports `dart.library.*` keys,
and preferred over a runtime `appFlavor` check because the latter does
not eliminate symbols. Tree-shaking from a separate entrypoint is the
only mechanism that produces a byte-identical `stable` snapshot.

A second outbox (alongside `sync_queue`) is justified by different
semantics: telemetry is fire-and-forget with eviction and no
user-visible "resend"; sync_queue has at-most-one-per-transcript and a
resend gesture (ADR-DATA-002, ADR-DATA-006). Homogenising them would
force one set of semantics on both and lose information. The
divergence is intentional and recorded here so a future contributor
does not import ADR-DATA-006 by analogy.

The hot-path rule encodes the implementation lesson that span
allocation/recording on >10 Hz paths can dominate audio-thread budget
on resource-constrained devices.

## Consequences

- **New rule:** Process-wide singletons remain forbidden except where
  this ADR's exemption criteria are met: must survive scope/widget/
  test lifetimes AND must be reachable from `main()` before Riverpod
  exists AND must default to a tested no-op.
- **Future dev-only features should reuse the flavor-entrypoint pattern**
  rather than inventing a runtime gate. The proof script
  `verify-stable-tree-shake.sh` is the canonical acceptance test.
- **Two outboxes now exist** — `sync_queue` (user-resendable,
  at-most-one) and `telemetry_outbox` (claim-based, evictable,
  two-kind). Cross-reads are not expected; if a third outbox appears,
  consider extracting a shared "durable outbox" abstraction.
- **Test impact: none.** Tests inherit the no-op default; no `setUp`
  required. Tests that assert telemetry emissions opt in with a
  recording subtype injected on the singleton.
- **Hot-path-rule violations** (spans at >10 Hz) are reviewable
  code-smell flags, not runtime errors. Spot-profiling in P039 T5b is
  the safeguard.
- **If voice-agent later adopts OTel in `stable`** (production
  telemetry), this ADR is superseded and a new ADR captures the
  privacy / sampling / endpoint posture for prod.
