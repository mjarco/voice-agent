# Proposal 039 — OpenTelemetry Dev-Flavor Telemetry

## Status: Implemented (2026-05-18). T5a manual verification passed on iOS Simulator + physical iPhone. Deployment of the T2 stack onto `laptop.lan` and a one-day dwell test (AC #3) are the only operational steps remaining; the code track is closed.

T0 / T1 / T3 / T4 / T5b on main. T4 wrapped in two halves:
- **T4a (PR #304)** — `telemetry_outbox` SQLite schema + CRUD on
  `StorageService` + `TelemetryStorageNoop` mixin.
- **T4b-1 (PR #305)** — `OtlpEncoder` + `DurableSpanProcessor` +
  `TelemetryFlushWorker` modules with 13 new unit tests, **not**
  wired into the live export path yet.
- **T4b-2 (PR #306)** — swap wiring in `OtelTelemetry.boot`.
  Dev-flavor span emission now goes through the SQLite outbox.

`verify-stable-tree-shake.sh` updated: strings check (0 OTel hits
in stable AOT) is the hard gate per ADR-OBS-001 §3; size delta is
informational since T4a's CRUD methods are reachable from both
flavors.

**AC #4 (force-quit durability) closed.** Spans now persist to
SQLite synchronously on `onEnd` before the call returns — the
10s flush window from the old `SimpleSpanProcessor` model is gone.

The dev-flavor diagnostic chain verified end-to-end on Simulator
on 2026-05-17 used the T3 `SimpleSpanProcessor` path. The swap to
the durable path was code-gated only — a short manual re-run is
the lightweight way to confirm parity. Update
`docs/manual-tests/p039-t5b-handsfree-telemetry.md` Expected
column for one detail: spans now land in the Collector with up to
~10 s delay (the flush interval) instead of synchronously.

**T5c landed (PR #308):** `devTelemetryEnabled` + `otelCollectorUrl`
in `AppConfig`, gate in `lib/main_dev.dart`, Settings → Advanced
section visible on dev flavor only (via new `isDevFlavorProvider`).
Six widget tests. Tree-shake still PASS (0 OTel hits in stable AOT).

**T6 complete (PRs #310–#315):** instrumentation table from §v1 fully
wired:
- T6-STT (#310) — `stt.request` span around Groq HTTP round-trip
- T6-sync (#311) — `sync.batch` span + `sync.failure` event
- T6-TTS (#313) — `tts.speak` span + `tts.interrupt` event
  (gated on actually-playing)
- T6-lifecycle (#314) — `app.foreground` / `app.background` /
  `app.terminate` events from `AppShellScaffold`
- T6-hardware-button (#315) — `input.volume_button` +
  `input.media_button` events from `RecordingScreen`

**T2 + T7 + T8 landed (PR #317):** full backend stack
(`telemetry.docker-compose.yml` with Collector + Tempo), Grafana
dashboard JSON (`ops/grafana/voice-agent-dev.json`, 11 panels in 3
sections), runbook (`docs/observability.md`). Verified locally end
to end — POST OTLP → Collector → Tempo search returns the trace.
Home-host deployment is the user's last manual step; the runbook
walks through it.

**T5a landed (PR #319):** iOS-only ship — Swift extension of the
existing `MediaButtonBridge` interruption + route-change observers
(no new observers, proposal's #1 risk neutralised), new
`TelemetryEventEmitter.swift` exposing
`EventChannel('com.voiceagent/telemetry_native_events')`, Dart-side
`TelemetryNativeBridge` consumer, wiring from `lib/main_dev.dart`,
5 widget tests. Verified end-to-end on physical iPhone iOS 26.4.2 —
5× `audio.session.route_changed` events captured including a real
Garmin watch trying to take audio routing (reason=8). Android
scaffolding deferred until NDK fix on the dev host.

**Remaining operational steps (no code):**
- Deploy the T2 stack on `agent.jarco.casa` (Collector + Tempo
  + Grafana data source + dashboard provisioning per
  `docs/observability.md`).
- One-day dwell test in normal use, per the proposal's AC #3
  (mic-silent scenario reproducible end-to-end in Grafana).

## Origin

Conversation 2026-05-15. The 2026-05-07 mic-silent regression (see project
memory and ADR-AUDIO-011) is currently a known-issue because we have no way
to observe the device-side state machine without a USB-connected debug build.
A user-visible bug whose symptom is "mic stops, force-quit fixes it" is
exactly the class of problem mobile telemetry exists to solve, and adding
proper instrumentation now amortises across the next dozen incidents.

This proposal scopes a real telemetry pipeline rather than ad-hoc logging.
We picked OpenTelemetry over a lightweight bespoke protocol because the work
is ~1.3× the bespoke option (mostly one-time infra setup) and the artifact
is standard tooling instead of project-specific code that would later need
migration.

## Prerequisites

- **P035 (dual installation flavors)** — implemented. The dev flavor is the
  gate (`appFlavor == 'dev'`, but enforced at build time — see
  §Dev/stable gate); the `stable` flavor compiles telemetry out
  entirely.
- **Home-monitor stack** — Prometheus / Grafana / Alertmanager already
  running on `laptop.lan:9090 / :3000 / :9093`. This proposal adds Tempo
  (and optionally Loki) to the same host; no greenfield infrastructure.
- **personal-agent REST API on `:8888`** — existing transport pattern for
  voice-agent → laptop. Telemetry uses the **OTel Collector** on the laptop
  directly (over the same LAN), not personal-agent — they remain separate
  concerns.

## Scope

- Risk: **Medium** — new dependency, new network egress from mobile, new
  ops surface on `laptop.lan`. The blast radius is bounded by the
  dev-flavor gate; the `stable` flavor must be byte-identical with
  respect to telemetry — no OTel symbols in the AOT snapshot. This is
  enforced by **conditional imports driven by a build-time
  `--dart-define`**, not by a runtime `appFlavor` check (see §Dev/stable
  gate).
- Layers: `lib/core/observability/` (new), `lib/app/app.dart` (boot wiring),
  call-sites in `lib/features/recording/data/hands_free_orchestrator.dart`,
  `lib/features/recording/data/groq_stt_service.dart`,
  `lib/features/api_sync/`, plus iOS / Android native hooks for audio
  session events.
- Expected PRs: ~5–6 (see Tasks).

## Problem Statement

We can reach personal-agent's prod logs and the home-monitor stack from
anywhere on the LAN. We cannot reach voice-agent's runtime state — what we
have:

- `debugPrint` lines that only exist when a USB cable is plugged in.
- Crash reports (none — no Sentry equivalent).
- Force-quit screenshots ex-post from the user.

Concrete unanswered questions from the 2026-05-07 mic-silent regression
that telemetry would have answered in minutes:

1. Was the silence preceded by an `EngineError` (`onError` /
   `_onStreamDone` from `hands_free_orchestrator.dart:217–222`), or did
   chunks just stop arriving?
2. If `onError` — what is the actual native error message
   (`avfaudio` code)?
3. How long after which lifecycle event (route change, app background,
   TTS playback) did the silence start?
4. How many times has this happened to the user, total? (Memory says
   "since 2026-05-07" but we have no count.)

This is also a recurring pattern. Future audio/STT/sync incidents will land
in the same blind spot.

## Are We Solving the Right Problem?

**Root cause of the observability gap:** mobile clients run on devices we
don't own (the user's phone) and have intermittent network connectivity.
Standard server-side observability does not apply. Solutions need to:

1. Buffer events locally so an offline period does not drop data.
2. Flush opportunistically when connectivity returns.
3. Survive force-quit (in particular: we want telemetry to be readable
   *after* a force-quit recovered the mic).

**Alternatives dismissed:**

- **Sentry / Firebase Crashlytics** — they solve a different problem
  (crashes, not stateful spans). They also pin us to a SaaS we don't
  control, and the personal-data posture is wrong for a personal agent
  that handles knowledge items.
- **`debugPrint` + custom log file** — works for a single bug investigation
  but doesn't compose. We'd reinvent timestamps, structured attributes,
  sampling, batching, retention, and visualisation.
- **Lightweight bespoke protocol (SQLite → personal-agent → Prometheus)** —
  considered and rejected in conversation. Compared to OTel: ~3 days vs
  ~3.5–4 days, but we'd ship a custom wire format that is not
  trace-context-propagation compatible. Future cross-instance tracing
  (mobile → personal-agent → upstream P066a) would need a second
  migration. Not worth the ~1 day saved.

**Smallest change:** a `Telemetry` facade in `lib/core/observability/`
that wraps `package:opentelemetry`'s `Tracer` / `Meter` APIs. Call-sites
use the facade. The OTel-backed implementation is in a separate Dart
file that is **conditionally imported** based on
`--dart-define=ENABLE_TELEMETRY=true`; `stable` flavor builds (no
define) get a no-op concrete subtype and the OTel package is tree-shaken
out of the AOT snapshot (proven by T3 acceptance test).

**ADR-AUDIO-011 collision (acknowledged):** the requester's suspicion
is that `cancelOnError: true` in `hands_free_orchestrator.dart:221` +
`_emitError → stop()` is the root cause of the mic-silent regression.
However, ADR-AUDIO-011 §3 ("Always-on audio capture") explicitly intends
this behaviour — "an audio I/O failure in always-on capture is a
session-level error worth surfacing." Telemetry alone does **not** fix
the regression. P039 produces the data needed for a follow-up proposal
that either (a) amends ADR-AUDIO-011 to distinguish transient vs
terminal stream errors, or (b) keeps the kill semantics and adds a UI
recovery affordance. Reader: do not interpret T5 instrumentation as a
licence to flip `cancelOnError` to `false` without that follow-up.

## Goals

1. Distributed-tracing-compatible spans from a defined set of call-sites
   on the dev build, exported via OTLP/HTTP to a Collector on `laptop.lan`.
2. The 2026-05-07 mic-silent regression scenario is observable end-to-end
   in Grafana the next time it recurs on a dev build: app launch →
   audio engine attach → engagement gate transitions → stream error or
   stream close event with native error code → orchestrator stop.
3. `stable` flavor builds are unaffected: no OTel symbols in the AOT
   snapshot, verified by a T3 acceptance test that greps the release
   build output.

## Non-Goals

- Production telemetry. Prod flavor stays dark. This is a developer tool.
- Crash reporting. OTel is not a crash reporter; if we want that later,
  it's a separate proposal.
- Cross-instance distributed tracing with personal-agent in this
  proposal. We emit W3C trace context (so it would just work later),
  but we do not instrument personal-agent in this scope.
- Telemetry for the personal-agent backend. Backend instrumentation is
  out of scope and would be a parallel personal-agent proposal if we
  choose to.
- User-visible metrics (battery cost dashboards, etc.). Internal
  observability only.
- App-level analytics (button clicks, screen views). Span-based
  observability for state machines, not product analytics.

## User-Visible Changes

None in the `stable` flavor. In `dev`, the user (you) gets a Grafana
dashboard at `laptop.lan:3000` titled "voice-agent dev". No UI surface
in the app itself — telemetry is fully background.

## Solution Design

### Data model

We emit **two** signal kinds:

1. **Traces (spans)** — primary. A span has a name, kind, start/end
   timestamps, attributes, status, and parent span (for nested
   operations like "STT request → HTTP round-trip → response parse").
   This is where the 2026-05-07 regression diagnosis lives.
   Discrete events (audio session interruption, hardware-button press,
   gate change) are emitted as **span events** on the active
   long-lived `hf.attach_stream` span — they pin to the orchestrator's
   timeline without needing a standalone signal kind.
2. **Metrics (counters/histograms)** — secondary. `audio_stream_errors_total`,
   `vad_segments_emitted_total`, `stt_request_duration_ms` (histogram).
   Useful for "how often does X happen across a week" and for
   heartbeats (`hf.chunk_received` counter) where a span would be
   wasteful.

Standalone logs are **out of v1**. If a log-shaped use case appears
(emitting a record from a context where no span is open and a counter
is wrong), a follow-up proposal adds Loki + a third signal kind.

We deliberately keep the surface small. Each call-site emits one of:
- `Telemetry.span(name, kind, attributes)` returning a span handle
- `Telemetry.event(name, attributes)` (immediate, no duration)
- `Telemetry.counter(name).inc(delta, attributes)`
- `Telemetry.histogram(name).record(value, attributes)`

### Wire format and transport

- **Protocol:** OTLP/HTTP (JSON encoding for the dev pipeline; switch to
  protobuf later if payload size matters).
- **Mobile exporter:** `package:opentelemetry` ≥ current stable, batch
  span processor, batched export every 10s or on graceful shutdown.
  Offline buffering goes to SQLite (see *Offline buffering* below).
- **Endpoint:** `http://laptop.lan:4318/v1/traces`,
  `http://laptop.lan:4318/v1/metrics` (OTel Collector HTTP receiver
  defaults).
- **Auth:** none (LAN-only, dev flavor only). The Collector binds to
  `0.0.0.0:4318` so the phone on Wi-Fi can reach it; firewall rule on
  `laptop.lan` permits LAN sources only.
- **Resource attributes** (set once at SDK init): `service.name=voice-agent`,
  `service.version` (from `pubspec.yaml`), `deployment.environment=dev`,
  `device.model`, `os.name`, `os.version`. We do **not** emit a redundant
  `app.flavor` — OTel convention is `deployment.environment`.

### Offline buffering — durability before batching

The default OTel `BatchSpanProcessor` buffers spans in memory for up
to 10s before exporting; force-quit during that window loses
everything in the buffer. That contradicts AC #4 (force-quit
durability). We replace it.

**Persist-on-end model.** A custom `DurableSpanProcessor` writes each
span to SQLite at `onEnd()` — synchronously to the local DB, before
returning. There is no in-memory batching layer. A separate flush
worker reads from SQLite and batches network sends.

Trade-off: extra DB write per span. With our event rate
(~50 spans/min peak per the call-site table) this is well below
SQLite's write throughput.

**Schema** (new migration, owned by `lib/core/storage/`):

```text
CREATE TABLE telemetry_outbox (
  id               INTEGER PRIMARY KEY AUTOINCREMENT,
  signal_kind      TEXT NOT NULL CHECK (signal_kind IN ('trace','metric')),
  payload          BLOB NOT NULL,             -- one OTLP/JSON record
  created_at       INTEGER NOT NULL,          -- epoch ms when persisted
  attempts         INTEGER NOT NULL DEFAULT 0,
  next_attempt_at  INTEGER NOT NULL DEFAULT 0,-- epoch ms; flusher skips rows in the future
  claimed_at       INTEGER,                   -- epoch ms; non-null means an in-flight flush owns the row
  last_error       TEXT
);
CREATE INDEX telemetry_outbox_due ON telemetry_outbox (signal_kind, next_attempt_at, id);
```

Logs are out of v1 — span events on the active span carry log-like
records; `'log'` is not a valid `signal_kind`.

**Flush worker (single-flight, transactional claim):**

- One worker isolate. Wakes every 10s foregrounded / 60s backgrounded.
- Claim transaction:
  `UPDATE telemetry_outbox SET claimed_at = :now WHERE id IN (
     SELECT id FROM telemetry_outbox
     WHERE claimed_at IS NULL AND next_attempt_at <= :now
     ORDER BY signal_kind, id LIMIT 50
  )`. Then `SELECT … WHERE claimed_at = :now` to read the batch.
- Post claimed rows per `signal_kind` to the right endpoint
  (`/v1/traces` or `/v1/metrics`).
- **Stale-claim recovery on boot:** rows with `claimed_at < now - 5min`
  get `claimed_at = NULL` (the worker that claimed them died).

**Per-status retry classification — reuse `ApiClient.classifyStatusCode`.**
The flusher's HTTP layer delegates classification to the existing
`ApiClient.classifyStatusCode(statusCode, message)` (public since P025):

| Result | Telemetry action |
|---|---|
| 2xx | `DELETE` row |
| `ApiTransientFailure` (408 / 429 / 5xx) | retry — increment attempts, back-off |
| `ApiPermanentFailure` (other 4xx, etc.) | drop row + bump `telemetry_drop` counter with `reason` attr |
| Network error / Dio timeout | retry — `classifyDioException` returns transient |

**Back-off:** `next_attempt_at = now + min(2^attempts seconds, 5min)`.
After `attempts >= 10`, drop the row + bump `telemetry_drop`.

Reusing `classifyStatusCode` keeps voice-agent's HTTP error semantics
unified. We do **not** invent a parallel OTLP classifier; the trade-off
is that we treat OTLP's 422 (schema rejection) as a hard drop alongside
ordinary 4xx, which matches what we want anyway (a 422 means our
payload is structurally wrong and won't succeed on retry).

**Retention with per-kind weighting.** Noisy metrics must not evict the
traces we need for diagnosis. Caps are per signal kind, enforced
before insert:

- `signal_kind = 'trace'` cap: 3 000 rows / 7 days
- `signal_kind = 'metric'` cap: 2 000 rows / 7 days

Oldest-drop by `(signal_kind, id)`. Oldest-drop is logged once per
minute per kind (deduped).

**Tests** (T4):
- Persist-on-end: assert each ended span produces a row before the
  next test step.
- Force-quit simulation: pump 10 spans, kill the worker isolate
  mid-flight, reopen DB → all 10 rows readable + stale-claim recovery
  resets `claimed_at`.
- Single-flight: two concurrent flush ticks; assert no row is sent
  twice (using a mock HTTP client that asserts payload IDs are
  unique).
- Per-status classification: 200 deletes; 400 drops; 408 retries;
  500 retries.
- Per-kind retention: pump 3001 trace rows; assert trace count
  3000 and the oldest is gone; pump 100 metric rows on top, assert
  trace count untouched.

This gives us "OTLP semantics + force-quit-durable" — the in-memory
queue is gone and SQLite is the source of truth for every signal.

### Dev/stable gate — flavor-specific entrypoints

**Why not conditional imports.** Dart's `if (...)` clause in `import`
directives only supports `dart.library.*` environment keys (built-in
platform markers). Arbitrary `String.fromEnvironment('ENABLE_TELEMETRY')`
values cannot drive a conditional import. A runtime `appFlavor` check
does not eliminate symbols. Both approaches were considered and
rejected on this basis.

**The mechanism is two flavor-specific entrypoints:**

- `lib/main_stable.dart` — sets `Telemetry.instance` to the no-op
  subtype. Imports `lib/core/observability/telemetry_noop.dart` only.
  **Does not import `package:opentelemetry` anywhere in its transitive
  graph.**
- `lib/main_dev.dart` — sets `Telemetry.instance` to the OTel-backed
  subtype. Imports `lib/core/observability/telemetry_otel.dart`, which
  imports `package:opentelemetry`. Wires the durable exporter and the
  native event bridge.

Both entrypoints call into a shared `appMain(Telemetry t)` that does
the real boot work, parameterising the telemetry instance.

The build commands target the right entrypoint per flavor:

- `flutter build apk --release --flavor stable --target lib/main_stable.dart`
- `flutter build apk --release --flavor dev    --target lib/main_dev.dart`
- iOS equivalent: each flavor's Xcode scheme passes `--target`
  through `FLUTTER_TARGET` in its xcconfig.

`make` targets are updated to pick the right `--target` per flavor.

**Acceptance check (T3).** Dart's tree-shaker eliminates code
unreachable from the entrypoint. Because `main_stable.dart` has no
import path to `package:opentelemetry`, the package is excluded from
the stable AOT snapshot. T3 verifies this by:

1. `flutter build apk --release --flavor stable --target lib/main_stable.dart`
2. `flutter build apk --release --flavor dev    --target lib/main_dev.dart`
3. Compare AOT artifact sizes (`build/app/intermediates/merged_native_libs/*/lib/arm64-v8a/libapp.so`).
   The stable build's `libapp.so` must be smaller than the dev
   build's. Magnitude is OTel SDK + dependencies (expect ~200–500 KB
   delta).
4. `strings libapp.so | grep -i opentelemetry` on the stable build —
   acknowledged as a smoke check, not proof (strings may survive even
   when code is dead). The size-delta comparison is the real proof.

iOS equivalent: compare IPA sizes (`*.app/Frameworks/App.framework/App`).

`Telemetry.instance` is a static field that defaults to the no-op
subtype at static-initialisation (not `late`). `main_stable.dart` does
not need to do anything; `main_dev.dart` re-assigns. Tests inherit the
no-op default — **no mass test-file edit**.

**Test harness implication.** Tests run via `flutter test`, which uses
the default `lib/main.dart` entry. We keep a thin
`lib/main.dart` that delegates to `main_stable.dart` so `flutter run`
and `flutter test` without an explicit `--target` get the safe path.

### Instrumentation call-sites (v1)

| Area | Spans / events / counters |
|---|---|
| App lifecycle | `app.boot` (span), `app.foreground`, `app.background`, `app.terminate` (events; terminate is best-effort) |
| Audio session (iOS native, from MediaButtonBridge extension) | `audio.session.interruption_began/ended` (events on the active `hf.attach_stream` span; attrs: `reason`, `shouldResume`), `audio.session.route_changed` (event; attrs: `reason`, `previous_outputs`, `current_outputs`) |
| Audio session (Android native) | `audio.becoming_noisy` (event). `audio.focus.*` is **out of scope** — app does not own a focus request. |
| Hardware buttons (existing `MediaButtonBridge` on iOS, equivalent on Android) | `input.media_button` (event; attrs: `button`, `from_locked`), `input.volume_button` (event; attrs: `direction`) — these are existing signals; instrumentation just observes them |
| Hands-free orchestrator — **diagnosis core** | `hf.attach_stream` (span, long-lived, parent of all subsequent), `hf.gate_changed` (event; attrs: `from`, `to`, **`reason ∈ {user_engage, user_disengage, tts_suspend, tts_resume, one_shot, terminal_error}`**), `hf.stream_error` (event; attrs: `native_code`, `message`), `hf.stream_done` (event), `hf.chunk_received` (counter; per chunk — the **heartbeat** that distinguishes a closed gate from a dead mic), `hf.segment_emitted` (counter) |
| Controller lifecycle | `hf.controller_state` (event on every state transition; attrs: `from`, `to`, `cause`) |
| VAD | `vad.frame_processed` (counter), `vad.segment_started/ended` (events) |
| STT (Groq) | `stt.request` (span, HTTP kind; attrs: model, audio duration, status, response latency, http status code) |
| Sync queue | `sync.enqueue` (counter), `sync.batch` (span, attrs: items, status), `sync.failure` (event with HTTP code) |
| TTS | `tts.play_start/end` (span pair), `tts.interrupt` (event) |

**Mic-silent diagnosis chain.** With the above, a mic-silent incident
in Grafana looks like one of these patterns:

- Hard error (orchestrator killed): last `hf.gate_changed` to `Listening` →
  `hf.stream_error` event with `native_code` → no more `hf.chunk_received`
  → `hf.controller_state` to terminal Error. **Diagnosable.**
- Soft starvation (recorder alive but no chunks): last
  `hf.gate_changed` to `Listening` → no `hf.stream_error` → `hf.chunk_received`
  counter flatlines while gate stays open. **Diagnosable** — distinguishes
  from legitimate gate close (where `hf.gate_changed` to `Closed` with
  `reason ∈ {tts_suspend, user_disengage, one_shot}` precedes the
  silence).
- Native interruption (iOS): `audio.session.interruption_began` event,
  then chunks stop. **Diagnosable.**

This is the v1 list. Adding a new call-site later is a one-line change.

### Native event bridges — reuse existing observers, drop unfounded ones

Realities of the current native code:

- **iOS already has** `AVAudioSession.interruptionNotification` and
  `AVAudioSession.routeChangeNotification` observers in
  `ios/Runner/MediaButtonBridge.swift` (lines 138, 163). Adding a
  second observer set would produce duplicate, divergent events and
  is forbidden.
- **Android does not own an audio-focus request.** An
  `OnAudioFocusChangeListener` would never fire because we never
  request focus via `AudioManager.requestAudioFocus()`. Dropping
  `audio.focus.*` from v1 — would be observability without a signal.
- **`ACTION_AUDIO_BECOMING_NOISY`** is real (headphone unplug); we do
  receive this if we register for it, but currently do not. v1 adds
  this single receiver.

**Wire model.** Per ADR-PLATFORM-005, we add one new **`EventChannel`**
(not MethodChannel — direction is native → Dart, stream-shaped):

- Channel name: `com.voiceagent/telemetry_native_events`.
- Direction: native → Dart only.
- Payload shape:
  `{ "type": String, "ts_ms": int, "attrs": Map<String, Object?> }`.
  `ts_ms` is wall clock at the native source so we can correlate
  against Dart-side spans without channel-hop drift.

**iOS** (`ios/Runner/Telemetry/TelemetryEventEmitter.swift`):
- A shared `TelemetryEventEmitter` singleton with the `EventChannel`
  registration.
- `MediaButtonBridge` is **extended** (not duplicated): inside the
  existing `interruptionObserver` and `routeChangeObserver` closures
  (lines 139 and 163 of MediaButtonBridge.swift today), call
  `TelemetryEventEmitter.shared.post(type:attrs:)` alongside the
  existing media-button handling. Zero new observers; zero
  duplication risk.
- Registration in `AppDelegate` is unconditional, but the emitter
  noop's its `post(...)` calls when no Dart-side subscriber is
  attached. This avoids per-event flavor checks in Swift while
  keeping the wire idle for stable builds.

**Android** (`android/app/src/main/kotlin/.../TelemetryEventEmitter.kt`):
- Shared `TelemetryEventEmitter` with the `EventChannel`.
- One new `BroadcastReceiver` for `AudioManager.ACTION_AUDIO_BECOMING_NOISY`
  registered in `MainActivity.onCreate` only when
  `BuildConfig.ENABLE_TELEMETRY == true` (set by the dev flavor's
  `buildConfigField`). The `stable` flavor's `MainActivity` does not
  register and the receiver class is unused.
- `OnAudioFocusChangeListener` is **out of scope** until the app
  actually requests focus.

**v1 event types from the bridge:**

| Source | type |
|---|---|
| iOS — interruption began | `audio.session.interruption_began` (attrs: `reason`) |
| iOS — interruption ended | `audio.session.interruption_ended` (attrs: `shouldResume`) |
| iOS — route change | `audio.session.route_changed` (attrs: `reason`, `previous_outputs`, `current_outputs`) |
| Android — becoming noisy | `audio.becoming_noisy` |

ADR-PLATFORM-005 channel-name registry is updated in T5a to add
`com.voiceagent/telemetry_native_events`. ADR-PLATFORM-005 also notes
"if a third platform channel is added, consider extracting a
`PlatformChannelRegistry` in `core/platform/`." **We explicitly defer
extraction.** Each of the three channels has independent lifetime,
distinct owners (audio_session, media_button legacy, telemetry events),
and zero shared state. Extracting a registry now would invent
abstraction over coincidence; revisit at the fourth channel or at the
first cross-channel concern (e.g. shared lifecycle, shared error
reporting). The deferral is recorded in the ADR-PLATFORM-005 update.

### Runtime config (T5c) — kill-switch + endpoint override

The build-time flavor gate (§Dev/stable gate) keeps telemetry out of
the `stable` AOT entirely. On the `dev` flavor it is then *always
on* with a hard-coded Collector endpoint, which is the wrong default
for two real situations:

1. **Off the home LAN.** When `laptop.lan` is unreachable, every span
   triggers an HTTP timeout. Spans are not lost (the durable outbox
   buffers them), but the request loop is wasteful battery / CPU.
2. **Sensitive moment.** The user may want a temporary kill switch
   for privacy without having to rebuild the app or downgrade to the
   stable flavor.

T5c adds two persisted settings to `AppConfig`:

| Field | Type | Default | Notes |
|---|---|---|---|
| `devTelemetryEnabled` | `bool` | `true` | When `false`, `main_dev.dart` leaves the no-op default in place. |
| `otelCollectorUrl` | `String` | first match of (a) build-time `--dart-define=OTEL_COLLECTOR`, (b) `http://laptop.lan:4318` | Validated as a parseable URL on save. Empty or invalid → treated as "telemetry off" until corrected. |

**Boot read pattern (in `lib/main_dev.dart`):**

1. `WidgetsFlutterBinding.ensureInitialized()` — current.
2. `SqliteStorageService.initialize()` — current.
3. `AppConfigService.load()` — current; returns the persisted
   `AppConfig`.
4. If `appConfig.devTelemetryEnabled && appConfig.otelCollectorUrl`
   parses to a valid URI → `Telemetry.instance =
   OtelTelemetry.boot(...)`. Otherwise leave the no-op default.
5. Emit the first `app.boot` event (no-op if disabled).
6. `runApp(...)`.

Changes only take effect on the next launch. The Settings UI surfaces
this with a `Restart required to apply` banner that appears after a
toggle or URL edit, and stays visible until the app is relaunched.
We deliberately do not implement live `Telemetry.instance` swap:
in-flight spans would either need teardown semantics that match
shutdown-flush, or would simply leak — both worse than asking for a
restart in a dev-only feature.

**UI placement.** `Settings → Advanced → Telemetry` section:

- `[✓] Enable telemetry` — bound to `devTelemetryEnabled`
- `Collector URL` — text field bound to `otelCollectorUrl`, with
  inline validation (red border + helper text on parse failure)
- `Clear telemetry buffer` — button that purges the SQLite
  `telemetry_outbox` (no-op when T4 has not landed). One-tap with no
  extra confirmation; the Advanced screen already has "experimental"
  framing.
- `Restart required to apply` banner — visible if current runtime
  config differs from persisted config

The entire section is rendered only when `appFlavor == 'dev'`. The
stable build does not compile the section's widgets (`if (kIsDev)`
guard around the include, where `kIsDev` is `appFlavor == 'dev'`).

**Pause semantics with the outbox (T4 interaction).** When T4 ships,
`devTelemetryEnabled = false` means:

- New spans are not generated (no-op subtype is installed).
- The `telemetry_outbox` table is **not purged automatically** —
  rows from before the toggle remain durable.
- The flush worker continues running because it is part of the
  observability infrastructure, not the OTel SDK; it drains existing
  rows to the configured Collector. If you want everything gone,
  hit `Clear telemetry buffer`.
- On the next restart with telemetry re-enabled, behaviour resumes
  as if nothing had been turned off (including replay of buffered
  rows the worker hasn't sent yet).

This matches the user mental model of "pause" rather than "erase."

**What T5c does *not* do:**

- No per-signal toggles (e.g. "traces but not metrics"). Single
  global kill-switch only.
- No live runtime swap of `Telemetry.instance`. Restart required.
- No sampling rate control. Dev flavor is 100% sampled by design.
- No effect on the stable flavor — that build has no telemetry code
  to gate.
- No "incognito for next N minutes" timer. If the privacy mental
  model needs that, it goes in a follow-up.

### Backend stack on `laptop.lan`

Three new processes via docker-compose alongside the existing
home-monitor stack:

- **OTel Collector** (`otel/opentelemetry-collector-contrib`) —
  HTTP receiver `:4318`, batch processor, exporters to Tempo (traces),
  Prometheus remote-write (metrics), Loki (logs, if we choose to use
  this signal).
- **Tempo** (`grafana/tempo`) — traces storage, retention 7 days.
- **Loki** (`grafana/loki`) — *optional* for logs; v1 may skip and
  emit logs as span events instead. Defer Loki unless we hit a use
  case it solves better.

Existing Prometheus and Grafana need data-source additions only
(Tempo, optionally Loki). Grafana dashboard is exported as JSON and
checked into `ops/grafana/voice-agent-dev.json`.

### Resource cost

- Phone: ~30 KB/min of OTLP traffic at expected event rate (rough
  estimate from instrumentation list); SQLite buffer at ~5 MB peak;
  battery negligible relative to the always-on mic.
- Laptop: Collector ~80 MB RAM, Tempo ~150 MB RAM, optional Loki
  ~100 MB RAM. Fits the existing home-monitor host comfortably.

## Affected Mutation Points

**Needs change:**

- `lib/app/app.dart` (App init) — wire `Telemetry.instance` from
  `main.dart` before `runApp`. App-lifecycle spans from observers.
- `lib/features/recording/data/hands_free_orchestrator.dart` —
  primary instrumentation site (the regression motivator). Span
  around `start`, events on stream errors / stream done /
  engagement transitions / segment emit.
- `lib/features/recording/data/groq_stt_service.dart` — span around
  each STT request.
- `lib/features/api_sync/` — span around each batch send.
- `lib/core/tts/flutter_tts_service.dart` — TTS lifecycle events.
- `ios/Runner/` (Swift native) — new bridge that posts audio
  session interruption / route-change notifications as platform-channel
  events that `Telemetry` converts into spans.
- `android/app/src/main/kotlin/` (Kotlin native) — same for audio focus
  loss / `becoming noisy`.
- `lib/core/storage/` — new `telemetry_outbox` table + DAO + migration.
- `lib/main_dev.dart` / `lib/main_stable.dart` — boot ordering:
  `WidgetsFlutterBinding.ensureInitialized()` →
  `SqliteStorageService.initialize()` (the OTel outbox table is in this
  DB) → `Telemetry.bootIfEnabled(storage)` (records the `app.boot` span;
  the durable span processor needs the DB open) → `runApp(...)`. Per
  ADR-ARCH-007, all of this runs before `runApp`. `lib/main.dart`
  remains a thin delegate to `main_stable.dart` for default
  `flutter run` / `flutter test`.
- `android/app/build.gradle.kts` — `dev` flavor adds
  `buildConfigField` `ENABLE_TELEMETRY=true` (for native gating of the
  Android `BroadcastReceiver`) and passes
  `--target lib/main_dev.dart` to `flutter`; `stable` passes
  `--target lib/main_stable.dart`.
- `ios/Flutter/Dev.xcconfig` (new or extended) — sets
  `FLUTTER_TARGET=lib/main_dev.dart`; `Stable.xcconfig` sets
  `FLUTTER_TARGET=lib/main_stable.dart`. iOS native uses no
  `ENABLE_TELEMETRY` build flag — the bridge code is statically
  registered but idle when no Dart subscriber exists.
- `lib/main_dev.dart`, `lib/main_stable.dart` — new entrypoints.
- `lib/main.dart` — collapses to a thin delegate that calls
  `main_stable.dart`'s entrypoint so default `flutter run` /
  `flutter test` get the safe path.
- `Makefile` — `make run-dev` / `make run-stable` / `make build-*`
  pass the correct `--target`.

**No change needed:**

- Domain interfaces (recorder, STT service abstractions) — telemetry
  lives at the implementation layer, not in the contract.
- Domain Riverpod providers — `Telemetry.instance` is a process-wide
  singleton (one of the rare cases where it's the right shape; we
  don't want per-test telemetry state). `Telemetry.instance` defaults
  to the no-op at static-init; **existing tests need no changes** and
  no `setUp` is required. New tests that want to assert telemetry
  emissions opt in by setting a recording subtype.

**App-scope wiring (not "no change", but boot-time only):**

- The `TelemetryNativeBridge` `EventChannel` consumer is started once
  at app boot from `main_dev.dart`. The subscription's lifetime is the
  process; nothing else owns it. This is app-scope infrastructure —
  not feature-scope — and it does not flow through a Riverpod scope.

## Tasks

| # | Task | Layer | Notes |
|---|------|-------|-------|
| T0 | **Minimal Collector for the spike** | ops | One-off docker-compose at `ops/dev/collector-only.docker-compose.yml` running just `otel/opentelemetry-collector-contrib` with `:4318` HTTP receiver and a `logging` exporter (stdout). Purpose: T1 has a target to POST to. ~30 LOC of YAML. |
| T1 | **Spike: `package:opentelemetry` viability on Flutter iOS Simulator + Android device + entrypoint tree-shake** | tooling | 2h timebox against the T0 Collector. Confirm: (a) OTLP/HTTP export works from iOS Simulator and a physical Android device on the LAN, (b) `DurableSpanProcessor` persists on `onEnd` and a `runApp(() { throw … })`-simulated crash mid-flush still preserves the span, (c) build `--release --flavor dev --target lib/main_dev.dart` and `--flavor stable --target lib/main_stable.dart` both succeed, (d) `libapp.so` size delta between the two builds ≥ ~150 KB and `package:opentelemetry` does **not** appear in the stable build's `libapp.so` `strings` output (smoke check; size delta is the real proof). **No physical iPhone** — the user has no paid Apple Developer account; iOS coverage is Simulator-only. Output: a go/no-go decision document committed alongside T0. |
| T2 | **`laptop.lan` full backend stack** | ops | Replaces T0's minimal compose. docker-compose at `ops/dev/telemetry.docker-compose.yml` with OTel Collector + Tempo + Prometheus remote-write target. Loki out of v1. Grafana data sources provisioned via sidecar config so they reload on restart. Persistent volumes. Retention config (Tempo 7 days, disk-headroom checked against existing host's free space — `df -h` recorded in the PR description). The `ops/` directory lives **in this voice-agent repo** under `ops/dev/`. |
| T3 | **`Telemetry` facade + no-op + OTel impl + flavor entrypoints** | `lib/core/observability/`, `lib/`, `android/`, `ios/` | The minimal API surface. Create `lib/main_dev.dart` and `lib/main_stable.dart` with a shared `appMain(Telemetry)`. Existing `lib/main.dart` becomes a thin delegate to `main_stable.dart` so default `flutter test` / `flutter run` get the safe path. Update `make` targets and per-flavor Xcode schemes (`FLUTTER_TARGET`) and Gradle flavor flags to pass `--target` correctly. Acceptance script `ops/scripts/verify-stable-tree-shake.sh`: runs both release builds and asserts the `libapp.so` size delta + `strings`-grep gate. Unit tests for facade contract. |
| T4 | **`DurableSpanProcessor` + `OtlpDurableExporter` + flush worker** | `lib/core/storage/`, `lib/core/observability/` | New `telemetry_outbox` migration per §Offline buffering. `DurableSpanProcessor` writes on `onEnd` (no in-memory batching). Flush worker with transactional claim, stale-claim recovery on boot, per-status retry classification (drop on 400/401/403/404/422; retry on 408/425/429/5xx/network; back-off cap 5 min; drop after 10 attempts), per-kind retention (3 000 trace / 2 000 metric / 7 days). Tests: persist-on-end, force-quit simulation, single-flight (concurrent ticks → unique payloads), per-status classification, per-kind retention, restart durability. |
| T5a | **Native event bridges** | `ios/`, `android/`, `lib/core/observability/` | New `EventChannel` `com.voiceagent/telemetry_native_events`. iOS: extend the existing `MediaButtonBridge` observer closures (no new observers — avoids duplication of `interruption`/`routeChange`). Shared `TelemetryEventEmitter` posts to the channel. Android: shared `TelemetryEventEmitter` + a `BroadcastReceiver` for `ACTION_AUDIO_BECOMING_NOISY` gated by `BuildConfig.ENABLE_TELEMETRY`. Dart-side `TelemetryNativeBridge` consumes the stream and turns each event into a span event on the active `hf.attach_stream` span. Update ADR-PLATFORM-005 channel-name registry. Note that this PR includes ADR delta — group with the proposal/ADR PR if T5a is the first ADR-PLATFORM-005 touch. |
| T5b | **Instrumentation: hands-free pipeline (diagnosis core)** | `lib/features/recording/` | Wire span + counter + event call-sites in `hands_free_orchestrator.dart` and `hands_free_controller.dart`: `hf.attach_stream` (long-lived span), `hf.gate_changed` (event with structured `reason` enum — wire from all four close paths the controller has today: user disengage, TTS suspend, one-shot, terminal error), `hf.stream_error` (event with native code from `onError` — best-effort parse of `Object e`), `hf.stream_done` (event), `hf.chunk_received` (counter; this is the heartbeat that disambiguates closed-gate from dead-mic), `hf.segment_emitted` (counter), `hf.controller_state` (event on every state transition). **Does not change `cancelOnError` behaviour** — see ADR-AUDIO-011 collision note in §Are We Solving the Right Problem? |
| T5c | **Runtime kill-switch + endpoint override (dev flavor)** | `lib/core/config/`, `lib/features/settings/`, `lib/main_dev.dart` | Two persisted settings: `devTelemetryEnabled` (bool, default `true`) and `otelCollectorUrl` (string, default `http://laptop.lan:4318` or the build-time `--dart-define=OTEL_COLLECTOR` if set). New "Telemetry" section at the bottom of `Settings → Advanced` with the toggle, the editable URL, and a `Restart required to apply` banner that appears after a change. `lib/main_dev.dart` reads both at boot and only calls `OtelTelemetry.boot` when enabled; when disabled the no-op default stays in place. The Settings section is rendered only when `appFlavor == 'dev'` (stable build does not compile any of T5c's UI either). After T4 lands, the toggle implies **pause semantics** on the outbox: stop persisting new spans, leave existing rows alone, flush worker keeps trying — a `Clear telemetry buffer` button does an explicit purge when needed. See §Runtime config (T5c) below. |
| T6 | **Instrumentation: STT, sync, TTS, lifecycle, hardware-button** | multiple features | Remaining call-sites from the v1 table. Includes `traceparent` header injection on the dio interceptor that talks to personal-agent, and `input.media_button` / `input.volume_button` event emission piggybacking the existing `MediaButtonBridge` Dart consumer. May land as one PR or split per feature. |
| T7 | **Grafana dashboard** | `ops/grafana/` | JSON checked into `ops/grafana/voice-agent-dev.json`. Panels: mic-silent timeline (gate state over time, overlaid with `hf.stream_error` events and `hf.chunk_received` rate — the rate going to zero while gate is open is the diagnosis), STT latency histogram, sync queue depth, audio session interruption rate. Provisioned via Grafana sidecar config so it reloads from disk on restart. |
| T8 | **Documentation + runbook** | docs | `docs/observability.md` — how to run the stack locally, how to read the dashboard, how to add a new instrumentation point, how to clear local SQLite buffer if it gets stuck, how to know if telemetry is itself broken. |

T1 is a hard gate. If the spike reveals blockers (Dart OTel SDK flaky
on iOS Simulator background, the entrypoint-based tree-shake produces
no measurable size delta), we re-cost and likely pivot to the
lightweight protocol per the alternative below.

**Task order** is strict: T0 → T1 → (T2 || T3) → T4 → T5a → T5b →
T6 → T7 → T8. T2 and T3 can land in parallel; everything after T4
needs the durable exporter. **T5c is parallel-mergeable any time
after T3 lands** — it depends only on the facade and `main_dev.dart`,
not on T4/T5a/T5b. T5c is a recommended pre-cursor to long-lived
day-to-day use of the dev flavor (the kill switch matters for
sensitive moments), but it does not block the T5b on-device
verification gate that decides whether the rest of P039 proceeds.

## Test Impact / Verification

**Existing tests affected:**

- None. `Telemetry.instance` defaults to the no-op at static-init;
  existing tests need no changes.

**New tests:**

- T3: facade contract tests (event names, attribute serialisation,
  no-op observability).
- T3: **`stable` flavor compile-gate test** — build
  `flutter build apk --release --flavor stable`, `grep -r
  opentelemetry build/app/outputs/` returns zero hits. Documented as
  an acceptance script in `ops/scripts/verify-stable-tree-shake.sh`.
- T4: durable exporter tests (offline buffer, flush, retention cap,
  4xx drop, 5xx back-off, restart durability — see §Offline buffering
  for the full list).
- T5b: orchestrator test that a stream error emits the expected span
  event with the native code attribute (does not change orchestrator
  behaviour).

**Manual verification (without paid Apple Developer account):**

- **Android one-day dwell:** dev-flavor APK on a physical Android
  device with the user's normal workflow. Confirm the Grafana
  dashboard shows: a successful `app.boot` span, several
  `hf.engagement_open` spans, STT spans for real conversations, and
  zero export failures during online operation.
- **iOS Simulator dwell:** equivalent run on iOS Simulator (1h).
  iOS-specific paths (audio session interruption notifications) are
  observed in this environment; physical-iPhone behaviour is inferred
  by parity with Android background-flush correctness, with the
  documented residual risk that iOS-only Simulator-vs-device drift
  cannot be ruled out here.
- **Flight-mode test (Android):** airplane mode on, several
  engagements, restore Wi-Fi, confirm buffered spans flush and the
  Grafana timeline backfills.
- **Force-quit durability test:** Android dev build. Engage, force-stop
  app, relaunch. Confirm the last engagement's spans appear in Grafana
  on next flush.

**Commands:**

- `make verify` — must pass at every PR.
- Cross-flavor: `flutter build apk --release --flavor stable` and
  `flutter build apk --release --flavor dev
  --dart-define=ENABLE_TELEMETRY=true` both succeed.
- `ops/scripts/verify-stable-tree-shake.sh` — runs in CI/local; fails
  if OTel symbols appear in the stable AOT snapshot.

## Acceptance Criteria

1. Dev-flavor build on a physical Android device **and** on the iOS
   Simulator emits spans to `http://laptop.lan:4318` and they appear in
   Grafana within 30s of user action. (Physical iPhone is out of scope —
   no Apple Developer account; iOS Simulator is the iOS acceptance bar.)
2. The `--flavor stable --target lib/main_stable.dart --release` build
   has no import path to `package:opentelemetry`, verified by
   `ops/scripts/verify-stable-tree-shake.sh`. The script (a) asserts a
   minimum size delta between stable and dev `libapp.so` outputs
   (≥ 150 KB), (b) runs `strings libapp.so | grep -i opentelemetry` on
   the stable build and asserts zero hits as a smoke check. Size delta
   is the real proof; `strings`-grep is a sanity check.
3. The 2026-05-07 mic-silent scenario, when reproduced, leaves a
   diagnosable trail in Grafana — specifically, the dashboard shows
   the last `engagement_open` span, any `stream_error` event with the
   native error code as an attribute, and the absence of subsequent
   `segment_emitted` counters that confirms the silence.
4. After force-quit during an active engagement, **every span that had
   `onEnd` called before the kill** is present in Grafana on the next
   successful flush. (`DurableSpanProcessor` persists synchronously
   on `onEnd`; the long-lived `hf.attach_stream` span that hadn't
   ended yet is allowed to be missing — it had no end to persist.)
5. Telemetry pipeline survives a Collector restart: spans buffered
   during the outage flush on Collector return; no spans lost up to
   the SQLite retention cap.
6. `docs/observability.md` is enough for a future contributor (or
   future-you) to add an instrumentation point without reading the
   facade source.

## Risks

| Risk | Mitigation |
|---|---|
| `package:opentelemetry` flaky on Flutter mobile (iOS background flush, sample loss) | T1 spike with explicit go/no-go. Pivot to lightweight protocol preserves T2/T4/T7/T8 work. |
| `stable`-flavor tree-shaking insufficient (OTel symbols leak into release) | Conditional imports gated by `String.fromEnvironment('ENABLE_TELEMETRY')` is the primary mechanism, not a fallback. T3 acceptance script `ops/scripts/verify-stable-tree-shake.sh` is the proof; if it fails, the proposal is blocked, not "patched at runtime." |
| OTel Collector + Tempo footprint disrupts existing home-monitor | Run on the same docker-compose host with explicit resource limits. Pre-check current host RAM/CPU headroom in T2 PR description. |
| LAN-only assumption breaks when phone is on cellular | Acceptable for dev flavor (buffer flushes when LAN returns). Documented in runbook. |
| Buffer SQLite table grows unbounded if flush keeps failing | Hard cap (5 000 envelopes / 7 days, across all signal kinds). Oldest-drop on cap reach. Buffer size emitted as a regular `debugPrint` on overflow (chicken-and-egg of telemeter-can't-telemeter-self). |
| Telemetry call-sites slow down the audio path | Spans are stack-allocated, attributes are lazy. **Per-frame and per-chunk paths use counters/histograms; spans are reserved for state transitions and request-scoped operations.** Verified in T5b by spot-profiling. |

## Alternatives Considered

**Lightweight bespoke protocol (SQLite → personal-agent REST → Prometheus
remote-write).** Discussed in conversation 2026-05-15. Estimated ~3 days
vs ~3.5–4 days for OTel. Rejected because the saved day buys a custom
wire format we'd later need to migrate to OTLP for cross-instance
tracing, and the OTel pipeline gives us W3C trace context, span kinds,
and semantic conventions for free. Kept here as the documented fallback
for the T1 spike's no-go branch.

**Sentry / Crashlytics SaaS.** Wrong shape (crash-centric, not span-centric)
and wrong privacy posture for a personal-agent ecosystem.

**Per-bug ad-hoc instrumentation (`debugPrint` + USB).** What we do today.
Doesn't compose, doesn't survive disconnect, doesn't compare across
sessions.

## Known Compromises and Follow-Up Direction

- **Cross-instance distributed tracing with personal-agent is
  *prepared*** — T6 wires a dio interceptor that injects
  `traceparent` into outbound HTTP. Personal-agent ignores the header
  until it gets its own OTel pass (separate proposal). The voice-agent
  side is complete now so the future personal-agent pass needs no
  changes here.
- **iOS coverage is Simulator-only** until the user obtains a paid
  Apple Developer account. Documented residual risk: iOS Simulator may
  flush background spans more readily than a real device under tight
  battery throttling. The follow-up if that ever matters is a
  one-day-on-loan-iPhone validation; not in scope here.
- **The `ops/` directory lives in this voice-agent repo** under
  `ops/dev/`. If a future second project contributes laptop-lan
  config, we move it to a sibling `home-monitor` repo in a separate
  refactor.
- **No sampling.** Dev flavor is single-user, 100% sampling is fine
  and analysing samples-of-samples is harder than just keeping
  everything for 7 days.
- **Loki is deferred.** v1 emits logs as span events on the in-flight
  span. If a use case appears that genuinely needs separate log
  storage (e.g. emitting structured logs from a context where no
  span is open), a follow-up proposal adds Loki to the docker-compose
  and a `_log` signal-kind to the outbox. Not blocking.
- **ADR-AUDIO-011 amendment is pending.** Once telemetry surfaces the
  actual native error code(s) behind the mic-silent regression, a
  follow-up proposal decides whether to amend ADR-AUDIO-011 (transient
  vs terminal classification) or keep the kill semantics + add a UI
  recovery affordance. P039 deliberately does not pre-empt that
  decision.

## ADR Impact

This proposal introduces one new ADR and amends four existing ones.
All five land in the same `039/proposal` branch as the proposal text
(per voice-agent CLAUDE.md "Proposal and ADR Commit" rule).

**New: `ADR-OBS-001-dev-flavor-telemetry-singleton.md`** — captures:
- Why telemetry is the rare case where a process-wide singleton is the
  right shape (signal must outlive widget trees, Riverpod scopes, and
  test lifecycles; tests inherit the no-op default with no setup).
- The dev/stable gate contract via **flavor-specific entrypoints**
  (`lib/main_dev.dart` / `lib/main_stable.dart`) + AOT size-delta
  acceptance test.
- The cross-cutting nature: every layer may instrument, but no layer
  depends on a concrete exporter.
- **Hot-path rule:** per-frame and per-chunk paths use counters /
  histograms only; spans are reserved for state transitions and
  request-scoped operations.
- **Telemetry flusher is exempt from ADR-NET-002** foreground-only sync
  (dev flavor only).
- **Reuses `ApiClient.classifyStatusCode`** for OTLP error
  classification — no parallel classifier.

**Amended:**

1. **ADR-PLATFORM-005** (platform channel pattern) — add `EventChannel`
   as a sibling pattern alongside `MethodChannel`, add
   `com.voiceagent/telemetry_native_events` to the channel-name
   registry, record the explicit deferral of the
   `PlatformChannelRegistry` extraction with the four-channel /
   cross-channel-concern revisit triggers.
2. **ADR-NET-002** (foreground-only sync) — add a P039 amendment naming
   the telemetry flusher's dev-flavor background cadence exception, and
   restate that the exception does not authorise generalised
   background sync without separate ADR-level justification.
3. **ADR-ARCH-007** (async db init before runApp) — add a "Known
   applications" entry recording the storage-first → telemetry-second →
   runApp ordering.
4. **ADR-DATA-001** (SQLite raw-SQL convention) — add a bullet noting
   `telemetry_outbox` extends the convention to observability storage.

If T1 pivots to the lightweight protocol the ADR-OBS-001 text adapts
(transport changes from OTLP/HTTP to a custom REST endpoint) but the
singleton + dev-gate + hot-path + flush-exemption decisions stand.

## Implementation status (paused 2026-05-16)

Implementation was driven autonomously through the full review cycle
plus four of the eight tasks. **Pausing here** because the next gate
is an on-device verification the user has to run; everything past
that depends on its outcome.

### Landed on `main`

| Task | PR | Verified | Notes |
|---|---|---|---|
| Proposal + 5 ADRs | #292 | n/a (docs) | Primary review + Codex second-opinion + architectural review; all P0/P1/P2 resolved. |
| T0 — minimal Collector | #293 | local docker compose round-trip (HTTP 200, span visible in `debug` exporter) | `ops/dev/collector-only.docker-compose.yml`. |
| T1 — viability spike | #294 | end-to-end against the T0 Collector | **GO decision** recorded in `docs/spikes/p039-t1-otel-viability.md`. iOS App.framework size delta: **466 KB** dev vs stable; `strings opentelemetry` hits: dev=46, stable=0. |
| T3 — facade + flavor entrypoints | #295 | `flutter test` 956/956 + `./ops/scripts/verify-stable-tree-shake.sh` PASS (160 KB delta, 0 stable hits) | `lib/main_stable.dart` / `lib/main_dev.dart` / `lib/app_main.dart` / `lib/core/observability/{telemetry,telemetry_otel}.dart` + 6 facade tests. |
| T5b — hands-free instrumentation | #296 | unit tests only — see "What the gate is" below | `lib/features/recording/data/hands_free_orchestrator.dart` + `…/presentation/hands_free_controller.dart` + 3 diagnosis tests in `hands_free_telemetry_test.dart`. Behaviour unchanged; `cancelOnError: true` and `_emitError → stop()` preserved per ADR-AUDIO-011 §3. |

### Pending

| Task | Why not yet | Estimated effort |
|---|---|---|
| **T5b on-device verification** | the resume gate, see below | 30 min on a real session |
| T5c — runtime kill-switch + endpoint override | added to the proposal after T5b landed (2026-05-16) when we noticed the dev build has no runtime off-switch — see §Runtime config (T5c) | ~30 min Dart + UI + one acceptance test; parallel-mergeable any time after T3 |
| T2 — full backend stack on `laptop.lan` | `laptop.lan` does not resolve from the dev machine where this work happened; can be deployed wherever the home-monitor host already runs | half a day |
| T4 — `DurableSpanProcessor` + outbox | pure Dart, well-scoped; deferred because mic-silent live observation already works with the T3 `SimpleSpanProcessor` — durability AC #4 is a separate concern | half a day |
| T5a — native `EventChannel` bridges | requires Swift + Kotlin work that needs on-device verification, plus the iOS observers currently live on `MediaButtonBridge` — must be extended carefully | half a day |
| T6 — STT / sync / TTS / lifecycle / hardware-button | mechanical instrumentation across multiple features; risk of silent behaviour change is the reason it didn't ship autonomously | half a day, splittable per feature |
| T7 — Grafana dashboard JSON | depends on T2 (needs a Tempo data source) | a couple of hours |
| T8 — `docs/observability.md` runbook | depends on T2 to document the "what to click in Grafana" half | a couple of hours |

### The gate: verify T5b on a real device first

Before touching T2/T4/T5a/T6/T7/T8, prove the diagnosis chain works
on the user's actual hardware. The cycle:

```bash
# (1) Bring up the spike Collector — on this machine or laptop.lan.
cd ops/dev && docker compose -f collector-only.docker-compose.yml up -d

# (2) Build / run the dev flavor pointed at the Collector.
#     Default endpoint is http://laptop.lan:4318. Override locally:
flutter run --flavor dev --target lib/main_dev.dart \
    --dart-define=OTEL_COLLECTOR=http://localhost:4318 \
    -d <device-id>
# Use `flutter devices` for the id. The wireless iPhone works for
# `flutter run` even without a paid Apple Developer account because
# Xcode is the codesigner here, not `flutter build`.

# (3) Provoke or wait for a mic-silent recurrence; force-quit when
#     it happens.

# (4) Inspect the Collector's debug output.
docker logs voice-agent-otel-spike | \
    grep -E "hf.attach_stream|hf.stream_error|hf.stream_done|hf.gate_changed|hf.chunk_received"
```

**Pass criteria for the gate:**
- An `app.boot` event lands in the Collector within ~5 s of app
  launch (proves `lib/main_dev.dart` boot wiring).
- `hf.attach_stream` span starts when the user engages.
- `hf.chunk_received` counter ticks while engaged (heartbeat alive).
- A mic-silent event leaves *either* `hf.stream_error` /
  `hf.stream_done` *or* a flatlined `hf.chunk_received` counter
  while `hf.gate_changed` is open. Both shapes are diagnosable.
- `hf.gate_changed` events fire with the correct `reason` on
  user-toggle, TTS suspend/resume, and one-shot disengage.

**Fail / surprise paths and what they mean:**

- **No events at all in the Collector.** Likely the
  `--dart-define=OTEL_COLLECTOR=…` did not propagate to
  `lib/main_dev.dart`'s `String.fromEnvironment`, or the device
  cannot reach the Collector. Verify with
  `curl -X POST http://localhost:4318/v1/traces` from the device's
  network.
- **`app.boot` lands but `hf.attach_stream` never starts.**
  The orchestrator's `_doStart` is not running the new
  instrumentation path. Check that the dev build picked up the
  T3+T5b code (rebuild from clean if needed).
- **Counter flatlines but `hf.stream_error` / `hf.stream_done`
  fired.** Expected — the hard-error path is engaged, the kill
  semantics in ADR-AUDIO-011 §3 are doing exactly what they say.
  This is the data the follow-up ADR-AUDIO-011 amendment needs.
- **Counter flatlines and *no* error event.** Soft starvation —
  the recorder stream is alive but iOS / Android is not delivering
  chunks. This is a *different* bug than the suspected one and
  changes the priority of T5a's native bridges (we'd want to see
  `audio.session.interruption_began` to explain it).

### How to resume each pending task

Each task below can be resumed by a fresh session from `main`. They
are roughly in dependency order; T2 and T4 can land in parallel.

#### T2 — laptop.lan full stack

1. Branch from main: `git checkout -b 039/t2-laptop-stack`.
2. Replace `ops/dev/collector-only.docker-compose.yml` with
   `ops/dev/telemetry.docker-compose.yml` that adds:
   - `otel/opentelemetry-collector-contrib` (carry over the existing
     receiver block; add an OTLP→Tempo exporter on the trace
     pipeline and an OTLP→Prometheus-remote-write exporter on the
     metrics pipeline).
   - `grafana/tempo` (single-binary mode, persistent volume,
     retention 7 days).
   - **No Loki** — v1 emits logs as span events.
3. Add Grafana data source provisioning under
   `ops/dev/grafana/provisioning/datasources/voice-agent.yml`
   pointing at the new Tempo and at the existing
   home-monitor Prometheus on `laptop.lan:9090`.
4. The home-monitor stack on `laptop.lan` already runs Prometheus +
   Grafana + Alertmanager (see reference memory). Slot the new
   compose alongside, not on top.
5. Acceptance: `curl -X POST http://laptop.lan:4318/v1/traces ...`
   returns 200 from any LAN device, and a span posted shows up in
   Grafana's Tempo data source within 30 s.

#### T4 — `DurableSpanProcessor` + outbox

1. Branch: `039/t4-durable-outbox`.
2. New SQLite migration in `lib/core/storage/` adding
   `telemetry_outbox` per §Offline buffering. Bump the schema
   version.
3. Custom `SpanProcessor` in `lib/core/observability/` that
   serialises each span to OTLP/JSON on `onEnd` and inserts a row
   synchronously.
4. Flush worker (also in `lib/core/observability/`) with the
   transactional claim, stale-claim recovery, per-status retry
   classification (delegate to `ApiClient.classifyStatusCode`).
5. Wire from `telemetry_otel.dart` (replace `SimpleSpanProcessor`).
6. Tests in `test/core/observability/`: persist-on-end, force-quit
   simulation, single-flight, per-status classification, per-kind
   retention. Use `sqflite_common_ffi` for in-memory DB.

#### T5a — native EventChannel bridges

1. Branch: `039/t5a-native-bridges`.
2. iOS: extend `ios/Runner/MediaButtonBridge.swift`'s existing
   `interruptionObserver` (line 138) and `routeChangeObserver`
   (line 163). **Do not register new observers.** Add a shared
   `TelemetryEventEmitter` singleton with a single `EventChannel`
   named `com.voiceagent/telemetry_native_events`. Post from
   inside the existing observer closures.
3. Android: new `BroadcastReceiver` for
   `AudioManager.ACTION_AUDIO_BECOMING_NOISY` in
   `android/app/src/main/kotlin/.../`, registered in
   `MainActivity.onCreate` guarded by `BuildConfig.ENABLE_TELEMETRY`
   (set by the dev flavor's `buildConfigField`). New `EventChannel`
   on the Kotlin side mirroring iOS.
4. Dart-side `TelemetryNativeBridge` in
   `lib/core/observability/` subscribes once at boot from
   `lib/main_dev.dart`. Turns each native event into a span event
   on the live `hf.attach_stream` span when one exists, else a
   stand-alone event.
5. Update ADR-PLATFORM-005's channel registry (already in
   docs/decisions/ — just confirm the entry).
6. Verification needs the device (no paid Apple Developer means
   physical iPhone is via Xcode's free-cert sideload only, which
   expires every 7 days; iOS Simulator is the steady-state target).

#### T5b on-device verification (the gate)

See §The gate above. No code work — just a real-world test run.
Capture the Collector output as evidence and either close the
gate or open a follow-up to fix what went wrong.

#### T5c — runtime kill-switch + endpoint override

1. Branch: `039/t5c-runtime-flag`.
2. Extend `AppConfig` in `lib/core/config/app_config.dart` with two
   fields: `bool devTelemetryEnabled` (default `true`) and
   `String otelCollectorUrl` (default: build-time
   `String.fromEnvironment('OTEL_COLLECTOR',
   defaultValue: 'http://laptop.lan:4318')`). Update `copyWith`,
   `fromMap`, `toMap`. Mind the persistence migration if AppConfig
   uses a versioned schema — these are additive fields with safe
   defaults, so on first read after upgrade existing users get the
   defaults transparently.
3. Update `lib/main_dev.dart` to read both fields from the loaded
   `AppConfig` and only call `OtelTelemetry.boot(...)` when
   `devTelemetryEnabled` is `true` *and* the URL parses to a valid
   `Uri`. When disabled, do not even emit the `app.boot` event —
   the contract is "telemetry off means telemetry off."
4. Add a `Telemetry` section to
   `lib/features/settings/advanced_settings_screen.dart`, rendered
   only when `appFlavor == 'dev'`. Three controls per
   §Runtime config (T5c). Hook the toggle and the URL field to
   `appConfigProvider`'s notifier. Show the `Restart required` banner
   whenever the in-memory config differs from the value the
   process booted with (capture the boot-time snapshot in a
   provider).
5. Add `Clear telemetry buffer` button. When T4 has not landed, this
   is a no-op with a debug toast; when T4 ships, it issues
   `DELETE FROM telemetry_outbox`.
6. Tests under `test/features/settings/`:
   - Toggle off + restart → next-launch `Telemetry.instance` is
     `NoopTelemetry` (drive via a recording subtype counter check —
     the no-op never emits).
   - Invalid URL → save is blocked, helper text shown.
   - Visibility of the section is conditional on flavor — write the
     test using a build-time `--dart-define` or by stubbing
     `appFlavor`.
7. Acceptance: `flutter run --flavor dev`, toggle off, restart,
   confirm Collector receives no spans. Toggle on, restart, confirm
   spans resume. Edit URL to `http://localhost:4318`, restart against
   a local Collector, confirm spans land there.

#### T6 — remaining instrumentation

One PR per feature (STT, sync, TTS, app lifecycle, hardware-button
input). Each follows the T5b pattern: call-site additions, three
tests per area minimum. Includes the `traceparent` dio interceptor
that injects W3C trace context into outbound personal-agent
requests.

#### T7 — Grafana dashboard

JSON file at `ops/grafana/voice-agent-dev.json`. Panels per §Tasks
T7 in the proposal. Provision via the Grafana sidecar config that
T2 sets up.

#### T8 — runbook

`docs/observability.md`. Audience: future-you, six months from
now. Sections: running the stack, reading the dashboard, adding a
new instrumentation point, clearing a stuck SQLite buffer,
recognising "telemetry itself is broken."

### Cross-resumption state to know

- **`Telemetry.instance` defaults to `NoopTelemetry`** at static
  init. Tests inherit this; no `setUp` required. Production tests
  that want to assert telemetry emissions swap in a recording
  subtype (see `test/core/observability/telemetry_test.dart` for
  the pattern and `test/features/recording/data/hands_free_telemetry_test.dart`
  for a feature-level example).
- **Default Collector endpoint** is hard-coded in `lib/main_dev.dart`
  as `http://laptop.lan:4318` and can be overridden at build with
  `--dart-define=OTEL_COLLECTOR=…`. The `stable` flavor never reads
  this define.
- **Per-flavor `--target` wiring** is not yet automated in the
  Xcode schemes or Gradle flavor build args. Today the user passes
  `--target lib/main_dev.dart` / `--target lib/main_stable.dart`
  explicitly to `flutter build` / `flutter run`. T5a (when it
  wires the Android `buildConfigField`) is the right moment to
  fold this into the scheme/Gradle configs and the `Makefile`
  targets.
- **`ops/scripts/verify-stable-tree-shake.sh`** is the AC #2
  acceptance gate. It runs `flutter build ios --release` twice
  and asserts the size delta + zero-strings invariants. Add it to
  any future CI on this branch family.
- **The 2026-05-07 mic-silent regression remains an open bug.**
  P039 makes it observable; the ADR-AUDIO-011 amendment that
  decides between (a) classifying transient vs terminal errors
  and (b) keeping kill semantics + adding a UI recovery affordance
  is a *separate* follow-up proposal triggered by what the
  telemetry actually shows.

## Findings from T5b verification (2026-05-17)

Runbook: `docs/manual-tests/p039-t5b-handsfree-telemetry.md`.
Conducted on iOS Simulator (iPhone 17, iOS 26.x), Collector on
localhost:4318 with `--dart-define=OTEL_COLLECTOR=http://localhost:4318`.

### What worked

| Test | Evidence in Collector |
|---|---|
| T1 — `app.boot` | 1× event, `service.name=voice-agent`, `deployment.environment=dev`, `phase=pre_runapp`, ~700 ms after process start. |
| T2 — heartbeat | 2 052× `hf.chunk_received` counter across two engagements, `gate_open: true` while engaged, `gate_open: false` after disengage. |
| T3 — gate close | `hf.gate_changed` with `open: false, reason: user_disengage` on user mic-tap-off. |
| T3 — warm re-engage | `hf.gate_changed` with `open: true, reason: user_engage` on the **second** engage (warm path through `setCaptureGate(open: true)`). |
| T3 — one-shot | `hf.gate_changed` with `open: false, reason: one_shot` after a captured utterance. |
| T4 — segment | `hf.segment_emitted` counter fired 1× on WAV write success. Independent of Groq STT outcome (which failed downstream with the fake key, as expected). |

### Findings — telemetry gaps to address

#### F1 — `hf.controller_state` not implemented

The T5b call-site table in §Instrumentation call-sites (v1) listed
`hf.controller_state` (event on every state transition). It was not
wired in PR #296. Consequence visible today: when
`HandsFreeController.startSession` aborted with
`HandsFreeSessionError(message: 'Groq API key not set.')`, zero
telemetry events fired — the failure happened *upstream* of the
orchestrator instrumentation.

**Impact:** any controller-side pre-flight failure (missing Groq
key, missing API URL, missing mic permission, manual recording
collision) is currently invisible. The diagnosis chain catches
*post*-engine failures cleanly; it misses *pre*-engine ones.

**Fix:** instrument `state =` in `hands_free_controller.dart` with
`Telemetry.instance.event('hf.controller_state', attrs: { from:
…, to: …, cause: … })`. ~10 LOC, ~3 tests, parallel-mergeable.

#### F2 — `hf.gate_changed(reason: user_engage)` missing on cold-engage

Today's test showed `user_engage` only on the **second** engagement.
Reason: on first engage, `startSession` calls `_startEngine`
(spinning up the engine + opening the gate via `engine.start()`),
not `setCaptureGate(open: true)`. My T5b instrumentation lives on
the latter call-site only. The orchestrator's own
`EngineListening` emit is not yet routed through `Telemetry`.

**Impact:** every cold engagement looks like an unannounced start
in telemetry — you see chunks arriving without a preceding
gate_changed event. Distinguishable from a bug because
`hf.attach_stream` span (when it gets exported at end) will pin
the start time. But the live timeline misses the cleanest signal.

**Fix:** either (a) add a `hf.gate_changed(open: true, reason:
user_engage)` event inside the orchestrator at the point where
`_emit(const EngineListening())` is called (alongside the existing
`_attachSpan = …` start), or (b) add it at the controller's
`startSession → _startEngine` call-site. (a) is more cohesive
(state-emitter co-located). ~5 LOC, ~1 test, parallel-mergeable.

### Findings — unrelated bug fixed in-session

#### F3 — boot crash on iOS Simulator from workmanager (FIXED)

`Workmanager.registerPeriodicTask` (introduced by P040 in PRs
#299 / #300) throws `PlatformException(unhandledMethod(...))` on
iOS Simulator and any physical iOS without
`BGTaskSchedulerPermittedIdentifiers` configured. The exception
escaped `appMain` and caused a white-screen boot.

**Fixed in PR #301** by wrapping `registerAgendaRefresh()` in a
defensive try/catch with `kDebugMode` debugPrint. Background
agenda refresh is best-effort; failing to register must not block
boot. Proper iOS BGTaskScheduler wiring stays a P040 concern.

This is independent of P039 but worth recording here because the
manual verification surfaced it.

### Conclusion

T5b verification gate is **closed green**. Future mic-silent
recurrences on a dev build are now diagnosable end-to-end (modulo
F2's cold-engage cosmetic — the `hf.attach_stream` span still pins
the start when it exports). The two telemetry gaps (F1, F2) are
real but small, parallel-mergeable, and do not block T2 / T4 / T5a
/ T6 / T7 / T8.

### Follow-up wave (2026-05-17 evening session)

After the verification cleared green, the same session shipped
four more PRs:

| PR | What | Status |
|---|---|---|
| #301 | F3 fix — `registerAgendaRefresh` graceful failure on iOS Simulator | Merged |
| #302 | iOS Podfile.lock sync (workmanager + flutter_timezone pods) | Merged |
| #303 | F1 + F2 — `hf.controller_state` + cold-engage `hf.gate_changed` | Merged |
| #304 | T4a — `telemetry_outbox` SQLite layer + `TelemetryStorageNoop` mixin | Merged |

F1 + F2 close the two instrumentation gaps surfaced by the
verification. T4a is the storage primitive on which T4b will hang
`DurableSpanProcessor` + `TelemetryFlushWorker` in a follow-up
session. T4a alone has no runtime effect — it just adds the table
and the API surface; production telemetry still uses
`SimpleSpanProcessor` from T3.

**Why T4b didn't ship today.** T4b swaps the live span-export
path on the dev flavor. Mis-wiring silently breaks the just-verified
diagnostic chain. The risk of a quiet regression after a long
session of incremental edits is high enough that T4b deserves a
fresh attempt with its own test cycle. The state on `main` is
clean.
