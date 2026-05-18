# Observability runbook (dev flavor)

How to run, read, and extend the P039 dev-flavor telemetry pipeline.
Six months from now this is what saves you re-deriving the
architecture from the proposal.

The actual design decisions live in [`proposals/039-otel-dev-telemetry.md`](proposals/039-otel-dev-telemetry.md)
and [`decisions/ADR-OBS-001-dev-flavor-telemetry-singleton.md`](decisions/ADR-OBS-001-dev-flavor-telemetry-singleton.md);
this document is operational only.

## What the pipeline looks like

```
┌──────────────┐  OTLP/HTTP   ┌────────────────┐  OTLP   ┌────────┐
│  voice-agent │ ───────────▶ │ OTel Collector │ ──────▶ │ Tempo  │  ← traces
│  (dev flavor)│              │  (laptop.lan)  │         └────────┘
└──────────────┘              │                │  remote-write
                              │                │ ────────────────▶  Home Prometheus  ← metrics
                              └────────────────┘
                                       │
                                       ▼ (debug exporter)
                                   docker logs
                                       │
                                       ▼
                                   Grafana (home)
                                   ┌────────────┐
                                   │ Tempo DS    │
                                   │ Prom DS     │
                                   │ Dashboard   │ ← `voice-agent-dev.json`
                                   └────────────┘
```

The dev-flavor app POSTs OTLP/HTTP to the Collector at
`http://laptop.lan:4318`. The Collector forwards traces to Tempo and
metrics to the existing home Prometheus via remote-write. Grafana
gets a new Tempo data source and a new dashboard; existing Prometheus
data sources keep working untouched.

## Running the stack

### One-time setup on the home host (laptop.lan)

1. **Clone the repo** to wherever the home-monitor stack lives:
   ```bash
   cd /opt/home-monitor   # or wherever
   git clone <voice-agent-repo> voice-agent
   ```

2. **Bring up the telemetry stack** alongside the existing
   home-monitor compose:
   ```bash
   cd voice-agent/ops/dev
   docker compose -f telemetry.docker-compose.yml up -d
   ```
   Two containers: `voice-agent-otel-collector` (`:4317`/`:4318`)
   and `voice-agent-tempo` (`:3200`).

3. **Provision the Grafana data sources.** Copy
   `voice-agent/ops/dev/grafana/provisioning/datasources/voice-agent.yml`
   into the home Grafana's `/etc/grafana/provisioning/datasources/`
   directory (or its bind-mount equivalent). Restart Grafana once.
   Existing data sources keep their config; the merge is by uid.

4. **Provision the dashboard.** Two options:
   - **Provisioning** (kept in sync with the repo): copy
     `voice-agent/ops/dev/grafana/provisioning/dashboards/voice-agent.yml`
     into Grafana's `/etc/grafana/provisioning/dashboards/`, then
     bind-mount `voice-agent/ops/grafana/` to
     `/var/lib/grafana/dashboards/voice-agent` inside the Grafana
     container. Restart Grafana.
   - **Manual import**: Grafana UI → Dashboards → New → Import →
     paste the contents of `ops/grafana/voice-agent-dev.json`.

5. **Verify the stack** with smoke tests:
   ```bash
   curl -s -o /dev/null -w "Collector %{http_code}\n" \
       -X POST http://laptop.lan:4318/v1/traces \
       -H 'Content-Type: application/json' -d '{}'
   # expect: Collector 200

   curl -s -o /dev/null -w "Tempo %{http_code}\n" http://laptop.lan:3200/ready
   # expect: Tempo 200
   ```

### Every dev session

The home stack stays up. Your only step is launching the dev flavor
of the app pointing at the Collector:

```bash
flutter run --flavor dev --target lib/main_dev.dart \
    -d <your-device-or-simulator>
```

The default Collector endpoint baked into the dev build is
`http://laptop.lan:4318`. Override via
`--dart-define=OTEL_COLLECTOR=http://other.host:4318` when working
from a different LAN.

## Reading the dashboard

Open Grafana → Dashboards → "Voice Agent" folder → "voice-agent dev".
Four sections:

### Mic-silent diagnosis (the original goal of P039)

- **`hf.chunk_received` rate** split by `gate_open`. The diagnostic
  signature of mic-silent is a flatline on `gate_open=true` —
  meaning the gate is open but no audio chunks are arriving.
- **`hf.stream_error` / `hf.stream_done` events** as a table. Any row
  in `hf.stream_error` is the immediate smoking gun. Click through
  to the parent `hf.attach_stream` span for the full timeline.
- **`hf.gate_changed` transitions**. The `reason` attribute
  distinguishes legitimate closes (`user_disengage` / `tts_suspend`
  / `one_shot`) from anything unexpected near a mic-silent event.

### STT + sync + TTS

- **`stt.request` latency** (p50/p95) derived from Tempo's
  span-metrics generator. A regression in Groq response time
  surfaces here long before any user complaint.
- **`sync.failure` count** with `kind` attr. Persistent transient
  failures point at network flakiness; persistent permanent
  failures point at an API contract mismatch with personal-agent.
- **`tts.speak` rate by status_code**. SpanStatus.error counts
  bumping is the leading indicator of TTS plugin instability.

### App lifecycle + hardware buttons

- **App foreground timeline** — cross-reference with the
  `hf.chunk_received` rate. If chunks flatlined while the app was
  in the foreground, that's a real regression (not a legitimate
  background-and-pause).
- **Hardware-button presses** — what the user pressed when. Helpful
  for reproducing UX bug reports where the user says "I tapped X
  and Y happened" — the table tells you what actually happened.

## Adding a new instrumentation point

1. **Pick a stable name.** Convention: `<area>.<verb>` for events
   (`hf.gate_changed`, `sync.failure`) and `<area>.<noun>` for
   spans (`stt.request`, `hf.attach_stream`). Names are durable;
   attributes can move.
2. **Pick the signal shape.** Per ADR-OBS-001 §4, per-frame and
   per-chunk paths use counters; spans are for state transitions
   and request-scoped operations. If the path runs at >10 Hz, do
   not make it a span.
3. **Call the facade.** All emissions go through
   `Telemetry.instance` (`event`, `span`, `counter`, `histogram`).
   Never reach into `package:opentelemetry` directly — that's the
   point of the facade.
4. **Use attributes for cardinality you'd want to slice by.** Avoid
   high-cardinality values (user ids, free-form strings, timestamps);
   they explode the metrics generator's label space.
5. **Add a test using a recording subtype** of `Telemetry` (see
   `test/core/observability/telemetry_test.dart` for the pattern,
   `test/features/recording/data/hands_free_telemetry_test.dart`
   for a feature-level example).
6. **Verify on-device** if the path is platform-sensitive (audio
   session lifecycle, background isolate, native bridge).

## Clearing the local SQLite buffer

The dev build buffers spans in `telemetry_outbox` if the Collector is
unreachable. Cap is 3 000 traces / 2 000 metrics, 7-day age — but
sometimes you want a clean slate (e.g. after a long offline period).

- **From the app UI:** Settings → Advanced → Telemetry → "Clear
  telemetry buffer".
- **From the database directly** (Simulator):
  ```bash
  xcrun simctl listapps booted | grep -i "voice agent"
  # find the Container path
  sqlite3 <container>/Documents/voice_agent.db \
      'DELETE FROM telemetry_outbox;'
  ```

## How to know if telemetry is itself broken

A few patterns to watch for:

| Pattern | Likely cause |
|---|---|
| No `app.boot` event in Collector within ~5s of launch | Dev build did not boot OTel (telemetry disabled in Settings, invalid Collector URL, or network unreachable). Check the in-app banner if any. |
| `app.boot` appears but no `hf.*` events on engagement | Either the engagement never reached `_doStart` (controller-side validator failed → see `hf.controller_state` event), or the build does not include the T5b instrumentation (rebuild from clean). |
| Spans arrive in batches with multi-minute delays | Flush worker is on the background cadence (60s) instead of foreground (10s). Either the app was actually backgrounded, or `WidgetsBindingObserver.didChangeAppLifecycleState` is not firing — both ADR-AUDIO-011-relevant. |
| Stable build produces telemetry traffic at all | This is a regression of ADR-OBS-001's tree-shake invariant. Run `ops/scripts/verify-stable-tree-shake.sh` immediately. |
| Collector debug logs show malformed payloads | OTLP encoder regression — see `lib/core/observability/otlp_encoder.dart` and the round-trip test in `durable_span_processor_test.dart`. |
| Sustained `5xx` from the Collector to the app | Tempo or the home Prometheus is down. Check both with the smoke curls from the §Running section. |

## Limits worth knowing

- Single-user pipeline. 100% sampling. No per-trace rate limits.
- Tempo retention: 7 days. Bump in `ops/dev/tempo/tempo.yaml` →
  `compactor.compaction.block_retention` if needed.
- Outbox retention: 3 000 trace rows / 2 000 metric rows / 7 days
  per ADR-OBS-001 §Schema. Whichever is hit first; oldest drop.
- Collector is unauthenticated. LAN-only. Do not expose `:4318`
  to the public internet.
- Stable flavor produces zero traffic by construction
  (`ops/scripts/verify-stable-tree-shake.sh` is the enforcement).

## When something doesn't fit

If you find yourself wanting:
- **Logs (not span events)** — see ADR-OBS-001 Consequences;
  promoting Loki from "deferred" to "in scope" is a separate
  proposal.
- **Cross-instance distributed tracing** with personal-agent — the
  Dart side already injects `traceparent` (T6); enabling the
  personal-agent receiving side is its own proposal.
- **Production telemetry** — superseding ADR-OBS-001 with a new
  ADR (privacy + sampling) is the right path. Today's pipeline is
  dev-flavor only by build construction.
