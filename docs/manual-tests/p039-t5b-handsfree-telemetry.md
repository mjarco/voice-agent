# Manual test: P039 T5b — hands-free telemetry chain

**Proposal:** [`docs/proposals/039-otel-dev-telemetry.md`](../proposals/039-otel-dev-telemetry.md) — T5b verification gate.
**Overall status:** **passed** — all setup + 4 test cases executed green on iOS Simulator. T5b gate cleared; T2 / T4 / T5a / T6 / T7 / T8 unblocked (and most have since landed on main).
**Why now:** This gate must clear before T2 / T4 / T5a / T6 / T7 / T8 proceed.
**Time budget:** ~20 min.
**What we are testing:** that the telemetry *plumbing* works on real Flutter — events, counters, spans reach the Collector. We are **not** trying to reproduce the mic-silent regression itself (that's iOS-device-specific and may not even fire today). If the plumbing works, we have an instrument that will catch the regression when it next happens.

## Status legend

Each step below has a `**Status:** ...` line. Allowed values: `pending` / `in-progress` / `passed (YYYY-MM-DD, <device + OS>)` / `failed (YYYY-MM-DD, <device + OS>): <reason>` / `skipped (<reason>)`. See [`p040-agenda-notifications.md`](p040-agenda-notifications.md#status-legend) for the canonical definition.

## Status summary

| # | Case | Status |
|---|---|---|
| S1 | Bring up the Collector locally | passed |
| S2 | Run the dev flavor on iOS Simulator | passed |
| T1 | `app.boot` lands within seconds | passed |
| T2 | `hf.attach_stream` span + `hf.chunk_received` ticks | passed |
| T3 | `hf.gate_changed` events with structured `reason` | passed |
| T4 | `hf.segment_emitted` / no spurious errors | passed |
| S3 | Re-run on the real iPhone (stretch) | skipped (iOS Simulator pass sufficient; real-device session deferred) |

---

## Setup (2 commands, ~2 min)

### S1 — Bring up the Collector locally

**Status:** passed

**Do:**
```bash
cd ops/dev && docker compose -f collector-only.docker-compose.yml up -d
```

**Why:** the dev build POSTs OTLP to a Collector. We run one locally; no `laptop.lan` needed for this test.

**Expected:** `docker ps` shows `voice-agent-otel-spike` as `Up`. `curl -X POST -o /dev/null -w "%{http_code}" http://localhost:4318/v1/traces -H 'Content-Type: application/json' -d '{}'` returns `200`.

### S2 — Run the dev flavor on iOS Simulator

**Status:** passed

**Do:**
```bash
# Pick a booted Simulator id from: flutter devices
flutter run --flavor dev \
  --target lib/main_dev.dart \
  --dart-define=OTEL_COLLECTOR=http://localhost:4318 \
  -d <simulator-id>
```

**Why:** Simulator gives us a real Flutter runtime without signing friction. We override the default `http://laptop.lan:4318` to our local Collector so events land where we can see them.

**Expected:** app launches with the **DEV branding** (orange theme, "Voice Agent DEV" title). If you see blue + "Voice Agent" you picked the wrong flavor.

---

## Tests (4 steps, ~10 min)

Keep a third terminal tailing the Collector. Each test step has a verifying grep:

```bash
docker logs -f voice-agent-otel-spike
```

### T1 — `app.boot` lands within seconds of launch

**Status:** passed

**Do:** nothing — this fires automatically on app start.

**Why:** confirms `lib/main_dev.dart` wired `Telemetry.instance = OtelTelemetry.boot(...)` and the OTLP/HTTP pipeline reaches the Collector.

**Note (after T4b-2):** spans now land in the Collector with up to ~10 s delay (the flush worker's foreground interval) instead of synchronously. T1's "~5 s" target holds for foreground operation; backgrounded launches may take up to a minute.

**Expected (in Collector logs within ~5 s of launch):**
```
Name           : app.boot
     -> phase: Str(pre_runapp)
     -> service.name: Str(voice-agent)
     -> deployment.environment: Str(dev)
```

**If missing:** the dev entrypoint isn't running, or the network override didn't take. Verify the dev branding is visible (S2), confirm Collector port is reachable from the Simulator (it shares the Mac's loopback).

### T2 — Engage hands-free → `hf.attach_stream` span starts + `hf.chunk_received` counter ticks

**Status:** passed

**Do:** in the Record tab, tap to engage hands-free. Let the mic run for ~5 s.

**Why:** verifies the orchestrator-level instrumentation (T5b's diagnosis core). The long-lived attach span is the parent of every subsequent diagnosis event; the chunk counter is the heartbeat that, if it ever flatlines while the gate is open, means a dead mic.

**Expected:**
- One `Name : hf.attach_stream` line (span start)
- Many `Name : hf.chunk_received` lines (one per audio chunk, ~30/s)
- Each `hf.chunk_received` has attribute `gate_open: Bool(true)`

**If `hf.attach_stream` is missing:** the dev build isn't picking up T5b code — rebuild from clean.
**If chunks have `gate_open: false`:** capture failed; check microphone permissions in Simulator's Settings.

### T3 — Toggle the gate → `hf.gate_changed` events with structured `reason`

**Status:** passed

**Do:** while engaged, suspend by user (mic button tap to disengage), then re-engage.

**Why:** verifies the controller-level instrumentation at one of the five gate-change call-sites. The structured `reason` enum is what lets a future Grafana panel distinguish *legitimate* gate closes from a dead-mic incident.

**Expected (in order):**
```
Name : hf.gate_changed
  -> open: Bool(false)
  -> reason: Str(user_disengage)
...
Name : hf.gate_changed
  -> open: Bool(true)
  -> reason: Str(user_engage)
```

**Bonus check:** trigger a TTS reply (any agent response that plays audio). You should see a paired `tts_suspend` / `tts_resume` (or `tts_resume` then `user_engage`, depending on `_pendingConversationResume` state).

### T4 — Provoke a teardown → segment_emitted counter / no spurious errors

**Status:** passed

**Do:** speak a short utterance, wait for it to be captured (you'll hear the audio-feedback chirp / see the segment in the UI). Then disengage cleanly.

**Why:** confirms the happy-path emitters and that we are **not** producing `hf.stream_error` events during normal operation (false-positives would make the dashboard useless).

**Expected:**
- One `Name : hf.segment_emitted` counter line per captured utterance
- **Zero** `hf.stream_error` or `hf.stream_done` events during this run
- The `hf.attach_stream` span ends with `SpanStatus.ok` when you fully stop the session

**If `hf.stream_error` shows up during the happy path:** something on the audio stream is misbehaving even on Simulator — capture the full Collector output and stop.

---

## Stretch (~5 min, only if everything above is green)

### S3 — Re-run on the real iPhone if Xcode signing works

**Status:** skipped (iOS Simulator pass sufficient; real-device session deferred)

**Do:** disconnect Simulator, plug in the wireless iPhone, accept any Xcode trust dialogs, re-run S2's flutter command with `-d 00008101-00025D103606001E` (the iPhone's id). On a fresh dev cert provisioning may need an Xcode "Run" first.

**Why:** Simulator validates plumbing; only the real device can reproduce the actual mic-silent regression. Even one short session on-device buys us a sanity check that the platform-specific code paths (`record` plugin's iOS implementation, audio session) emit the expected counters.

**Expected:** same shape as T1–T4. The interesting question — "does mic-silent happen?" — only gets answered if it triggers naturally during this session. Don't force it.

---

## What to capture if anything goes wrong

For each failed step, save:
```bash
docker logs voice-agent-otel-spike > /tmp/p039-t5b-collector.log
```

…plus the `flutter run` console output (Cmd+C from the terminal). Drop both into a new GitHub issue titled `P039 T5b — manual verification failure` and reference this file. Future-me will not have your in-the-moment context.

---

## When you're done

### All green
Update the proposal's Status line — change "T5b is unverified" to "T5b verified on iOS Simulator on YYYY-MM-DD" (and "+ real iPhone" if S3 worked). After that, T2 / T4 / T5a / T6 / T7 / T8 are unblocked; pick whichever next step fits your day.

### Partial / red
Don't tear down. Save the logs, file the issue, and stop. The instrumentation should either work or stay broken in a known way until we fix it — silently re-running and hoping isn't a strategy here.

### Teardown

```bash
cd ops/dev && docker compose -f collector-only.docker-compose.yml down
# Cmd+C the flutter run terminal
```
