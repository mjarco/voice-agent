# Manual test: P039 T5a — native EventChannel bridges

**Proposal:** [`docs/proposals/039-otel-dev-telemetry.md`](../proposals/039-otel-dev-telemetry.md) — T5a (Native event bridges).
**Overall status:** **pending** — Dart bridge + iOS code landed on main; iOS Simulator + physical iPhone verification still to run. Android scaffolding deferred (NDK on the dev host is broken — see F3 from 2026-05-17).
**Why now:** T5a is the last code track of P039; everything else either landed or is deployment ops. iOS verification today closes the loop.
**Time budget:** ~25 min for iOS Simulator + physical iPhone combined.
**What we are testing:** native audio-session interruption + route-change events flow through the new `com.voiceagent/telemetry_native_events` EventChannel → `TelemetryNativeBridge` → Collector with the right `type` + `attrs`, and that the extension of the existing `MediaButtonBridge` observer closures did not duplicate any observer (T5a's #1 risk per the proposal).

## Status legend

Each step below has a `**Status:**` line. Allowed values: `pending` / `in-progress` / `passed (YYYY-MM-DD, <device + OS>)` / `failed (YYYY-MM-DD, <device + OS>): <reason>` / `skipped (<reason>)`. See [`p040-agenda-notifications.md`](p040-agenda-notifications.md#status-legend) for the canonical definition.

## Status summary

| # | Case | Status |
|---|---|---|
| S1 | Bring up the Collector locally | pending |
| S2 | Run the dev flavor on iOS Simulator | pending |
| S3 | Engage hands-free so the diagnosis context is "live" | pending |
| T1 | Bridge attaches without errors at boot | pending |
| T2 | iOS audio session interruption (Simulator menu) | pending |
| T3 | iOS route change (physical iPhone, AirPods unplug) | pending |
| T4 | No duplicate `audio.session.interruption_began` (regression gate) | pending |
| T5 | Existing media-button behaviour unchanged (regression gate) | pending |
| T6 | Android `ACTION_AUDIO_BECOMING_NOISY` | skipped (Android NDK broken on the dev host; deferred to a future fix) |

---

## Setup

### S1 — Bring up the Collector locally

**Status:** pending

**Do:**

```bash
cd ops/dev && docker compose -f collector-only.docker-compose.yml up -d
```

**Why:** the dev build POSTs OTLP to a Collector. We use the spike compose (debug exporter only) so we can `docker logs -f` and read events live, without standing up the full Tempo stack.

**Expected:** `voice-agent-otel-spike` container `Up`. `curl -X POST -o /dev/null -w "%{http_code}" http://localhost:4318/v1/traces -H 'Content-Type: application/json' -d '{}'` returns `200`.

**On failure:** if the container won't start, check `docker logs voice-agent-otel-spike` for a YAML parse error in `otel-collector-config.yml`.

### S2 — Run the dev flavor on iOS Simulator

**Status:** pending

**Do:**

```bash
xcrun simctl list devices booted     # find a booted simulator id
flutter run --flavor dev \
  --target lib/main_dev.dart \
  --dart-define=OTEL_COLLECTOR=http://localhost:4318 \
  -d <simulator-id>
```

**Why:** Simulator boots fast and has the audio interruption trigger in its menu. Physical iPhone is the stretch path for route-change in T3.

**Expected:** app launches with orange "Voice Agent DEV" branding. `app.boot` appears in Collector logs within ~5 s.

**On failure:** if the dev branding doesn't appear, the `--flavor` / `--target` flags didn't match (check there's no typo on `lib/main_dev.dart`).

### S3 — Engage hands-free so the diagnosis context is "live"

**Status:** pending

**Do:** In the Record tab, tap mic to engage. Confirm `hf.gate_changed(reason=user_engage)` shows up and `hf.chunk_received` starts ticking.

**Why:** T5a v1 emits standalone events (per the proposal's "Option B" path); we don't actually need an active span to pin to. But keeping the hands-free session live makes the timeline more realistic when reading the Collector log.

**Expected:** `hf.attach_stream` span open (logged at end on disengage), `hf.chunk_received` ticking with `gate_open: true`.

**On failure:** see `docs/manual-tests/p039-t5b-handsfree-telemetry.md` for the diagnosis — same plumbing.

---

## Tests

Keep a third terminal tailing:

```bash
docker logs -f voice-agent-otel-spike | grep -E "audio\.|input\."
```

### T1 — Bridge attaches without errors at boot

**Status:** pending

**Do:** nothing. The `EventChannel` consumer wires up inside the `afterStorageInit` hook in `lib/main_dev.dart` before `runApp`. If the channel name is wrong on either side, you'd see a `MissingPluginException` in the `flutter run` terminal within the first second after `app.boot`.

**Why:** ADR-PLATFORM-005 channel-name registry was updated for T5a. A mismatch between Swift (`TelemetryEventEmitter.swift` line ~38) and Dart (`telemetry_native_bridge.dart` line ~17) would silently degrade T5a to no-op.

**Expected:** no `MissingPluginException`, no `PlatformException` in `flutter run` output after `app.boot`. The dev build keeps running.

**On failure:** the channel name diverged between platforms. Both should read `com.voiceagent/telemetry_native_events` exactly.

### T2 — iOS audio session interruption (Simulator)

**Status:** pending

**Do:**

1. With hands-free engaged (S3), in the Simulator menu choose **Device → Trigger Phone Call** (or **Hardware → Audio → Interrupt** on older Xcode versions).
2. Wait ~3 s, then end the call to resume audio.

**Why:** Verifies the extension of `MediaButtonBridge`'s existing `interruptionObserver` (line 138) — both `.began` and `.ended` branches now post to `TelemetryEventEmitter`.

**Expected (in this order, within ~10 s):**

```
Name : audio.session.interruption_began
  -> reason: Int(<0 or higher>)
Name : audio.session.interruption_ended
  -> shouldResume: Bool(true)
```

Plus: `hf.chunk_received` pauses during the interruption and resumes after.

**On failure:**
- No `interruption_began` at all → channel name mismatch (see T1), OR the `TelemetryEventEmitter.shared.post(...)` call inside the existing observer never ran. Check the simulator console for `[MediaButtonDbg] interruption began` — that's the existing log and confirms the observer fired.
- `interruption_began` but no `interruption_ended` → the simulator's "end call" didn't fire the matching `AVAudioSession.interruptionNotification`. Try again from the menu.

### T3 — iOS route change (physical iPhone preferred)

**Status:** pending

**Do (Simulator-only fallback path):** force an audio engine restart from the host:

```bash
sudo killall coreaudiod
```

iOS picks this up as a route change. Single attempt — repeated kills make iOS angry.

**Do (physical iPhone path — preferred for meaningful coverage):**

1. Disconnect Simulator.
2. Plug in the wireless iPhone; run `flutter run -d <iphone-id> --flavor dev --target lib/main_dev.dart --dart-define=OTEL_COLLECTOR=http://localhost:4318`. (Xcode free signing — the cert is good for 7 days.)
3. Engage hands-free.
4. Pair or unpair AirPods. Just one transition.

**Why:** Verifies the extension of `MediaButtonBridge`'s `routeChangeObserver` (line 163). Route changes are the realistic source of mid-session audio reroutes that have historically tripped the lock-screen recording path.

**Expected:**

```
Name : audio.session.route_changed
  -> reason: Int(<reason enum value>)
  -> previous_outputs: <e.g. ["Speaker"] or ["AirPods Pro"]>
  -> current_outputs: <e.g. ["AirPods Pro"] or ["Speaker"]>
```

`reason` is from `AVAudioSession.RouteChangeReason` (`newDeviceAvailable=1`, `oldDeviceUnavailable=2`, `categoryChange=3`, etc.).

**On failure:**
- Event fires repeatedly with `reason=3 (categoryChange)` at boot → our own `setActive(.playAndRecord)` triggers categoryChange route notifications. Either filter in T5a code or downstream in Grafana. Not a bug per se but worth noting.
- Event never fires on AirPods unplug → check that the iPhone actually heard the BT disconnect (audio should re-route to the speaker — if it didn't, the route change didn't happen at the OS level either).

### T4 — No duplicate `audio.session.interruption_began` (regression gate)

**Status:** pending

**Do:** trigger one interruption (T2 step 1). Count occurrences in the Collector log:

```bash
docker logs voice-agent-otel-spike | grep -c "audio.session.interruption_began"
```

**Why:** This was the #1 risk in the T5a design — duplicating the iOS observer instead of extending the existing one. The proposal explicitly chose the extension path; T4 enforces it.

**Expected:** exactly `1` per triggered interruption. Two means we registered a second observer somewhere.

**On failure:** examine `MediaButtonBridge.installLifecycleObservers()` — there should be exactly one `addObserver(forName: AVAudioSession.interruptionNotification, ...)` block in the entire codebase. `grep -rn "interruptionNotification" ios/Runner/` confirms.

### T5 — Existing media-button behaviour unchanged (regression gate)

**Status:** pending

**Do:** play any TTS reply, then press the play/pause button (Simulator: media controls in macOS menu bar; iPhone: AirPods button or Siri Remote / play-pause control). Compare `[MediaButtonDbg]` lines in `flutter run` with the pre-T5a baseline (check git log against any commit before this PR).

**Why:** T5a extended `MediaButtonBridge.handleInterruption(...)` and the `routeChangeObserver` closure. Media-button behaviour (TTS stop / engagement toggle) must remain byte-identical.

**Expected:** identical `[MediaButtonDbg]` lines, identical toaster messages ("Listening" / "Paused"), identical haptic feedback.

**On failure:** if anything in the `[MediaButtonDbg]` shape differs, telemetry emission accidentally changed the closure's control flow. Telemetry emissions must be additive — `TelemetryEventEmitter.shared.post(...)` should never short-circuit, throw, or change the observer's return value.

### T6 — Android `ACTION_AUDIO_BECOMING_NOISY`

**Status:** skipped (Android NDK broken on the dev host; deferred to a future fix)

**Do (when NDK is fixed):**

```bash
flutter run --flavor dev --target lib/main_dev.dart \
  --dart-define=OTEL_COLLECTOR=http://localhost:4318 \
  -d <android-emulator-or-device-id>
# In Record tab, engage hands-free.
adb shell am broadcast -a android.media.AUDIO_BECOMING_NOISY
```

**Why:** Android has no audio-session interruption concept; `ACTION_AUDIO_BECOMING_NOISY` is the closest analogue (headphone-unplug-like event). Confirms the Android-side `TelemetryEventEmitter.kt` + `BroadcastReceiver` registration are gated correctly by `BuildConfig.ENABLE_TELEMETRY` (dev flavor only).

**Expected:** `Name : audio.becoming_noisy` in the Collector log within ~5 s.

**On failure:** check `adb shell dumpsys package com.voiceagent.voice_agent.dev | grep flavor` to confirm the dev variant is installed.

---

## When this plan is done

**Must-pass:** S1, S2, S3, T1, T2, T4, T5. These cover the iOS happy path + both regression gates. Any failure here blocks declaring T5a verified.

**Stretch / OEM-conditional:**
- T3 on physical iPhone — high signal but requires Xcode signing flow that may not be available; the `coreaudiod` killall fallback on Simulator is acceptable if BT pairing isn't reachable.
- T6 on Android — entirely separate platform; failures here do not block iOS verification.

When all must-pass cases are `passed`, update `docs/proposals/039-otel-dev-telemetry.md` Status to remove T5a from "Remaining tracks" and reference the verification date + device.

## What to capture if anything goes wrong

```bash
docker logs voice-agent-otel-spike > /tmp/p039-t5a-collector.log
# Plus the `flutter run` console output.
# Plus, if iPhone-side: device console via `idevicesyslog` or Console.app.
```

File a GitHub issue titled `P039 T5a — manual verification failure`, link both logs and this file, set the relevant `T#` status to `failed (...)`.

## Teardown

```bash
cd ops/dev && docker compose -f collector-only.docker-compose.yml down
# Cmd+C the flutter run terminal.
```
