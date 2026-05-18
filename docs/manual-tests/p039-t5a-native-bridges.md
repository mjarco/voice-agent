# Manual test: P039 T5a — native EventChannel bridges

**Proposal:** [`docs/proposals/039-otel-dev-telemetry.md`](../proposals/039-otel-dev-telemetry.md) — T5a (Native event bridges).
**Run after:** the T5a PR has landed and you can build dev flavor (Android NDK fixed if testing Android).
**Time budget:** ~25 min for the iOS Simulator path; +15 min if you also exercise Android or physical iPhone.
**What we are testing:** that each native event the proposal lists (`audio.session.interruption_began/ended`, `audio.session.route_changed`, `audio.becoming_noisy`) emerges in the Collector with the right attributes and pins to the active `hf.attach_stream` span — *and* that we did not silently duplicate the existing `MediaButtonBridge` observers.

---

## Setup (~3 min)

### S1 — Collector up

```bash
cd ops/dev && docker compose -f collector-only.docker-compose.yml up -d
```

**Expected:** `voice-agent-otel-spike` container Up, `curl -X POST http://localhost:4318/v1/traces -d '{}'` returns 200.

### S2 — Run dev flavor on iOS Simulator

```bash
flutter run --flavor dev \
  --target lib/main_dev.dart \
  --dart-define=OTEL_COLLECTOR=http://localhost:4318 \
  -d <booted-simulator-id>
```

**Expected:** app boots, orange "Voice Agent DEV" branding, `app.boot` in Collector logs within ~5 s.

### S3 — Engage hands-free

In the Record tab, tap mic to engage. **Expected:** `hf.gate_changed(reason=user_engage)` lands and `hf.chunk_received` starts ticking. Keep this session engaged — every test below pins its event onto this session's `hf.attach_stream` span.

---

## Tests

Keep a third terminal tailing:

```bash
docker logs -f voice-agent-otel-spike | grep -E "audio\.|input\."
```

### T1 — Bridge attaches without errors at boot

**Do:** nothing — the `EventChannel` consumer wires up during `appMain`'s post-storage hook.

**Why:** ADR-PLATFORM-005 channel-name registry now includes `com.voiceagent/telemetry_native_events`. If the channel was registered with the wrong name or the consumer threw, you'd see a `MissingPluginException` in the `flutter run` terminal — which would cascade to a swallowed `app.boot` follow-up.

**Expected:** no exception in `flutter run` logs after `app.boot`. No `[MediaButtonDbg]` errors. The dev build keeps running.

**Failure capture:** the relevant lines from `flutter run` console — anything matching `MissingPluginException`, `EventChannel`, or `TelemetryNativeBridge` is the smoking gun.

### T2 — iOS audio session interruption (Simulator)

**Do:**
1. With hands-free engaged, in the Simulator's menu: **Device → Trigger Phone Call** (Xcode 26.x) *or* **Hardware → Audio → Trigger Interruption** depending on version.
2. After ~3 seconds, end the call / resume audio.

**Why:** Tests that we extended the existing `MediaButtonBridge.interruptionObserver` rather than registering a second one. The fact that telemetry fires AND the existing media-button behavior is unaffected is the key signal.

**Expected (in this order):**
```
Name : audio.session.interruption_began
  -> reason: Str(...)
Name : audio.session.interruption_ended
  -> shouldResume: Bool(true)
```

Plus: `hf.chunk_received` counter pauses during the interruption (the recorder loses the I/O unit) and resumes after.

**Failure modes:**
- Two `interruption_began` events for the same interruption → we duplicated the iOS observer. Revert and extend the existing closure instead.
- No event at all → the channel isn't routing native → Dart. Check the EventChannel name matches in both Swift and Dart.
- Event fires but no `hf.chunk_received` pause → instrumentation is firing on a fake/stale notification. Investigate the observer's notification source.

### T3 — iOS route change

**Simulator caveat:** Bluetooth pairing is not available in iOS Simulator. The cleanest route-change simulation is the **Audio output picker** in the Simulator's Hardware menu, or programmatically via:

```bash
# On macOS host, while the Simulator is foregrounded:
sudo killall coreaudiod   # forces an audio engine restart; iOS picks up as route_change
```

**Better path:** if you have a physical iPhone paired via Xcode free signing, plug it in, run `flutter run -d <physical-iphone-id>`, then pair / unpair AirPods. The 7-day cert expiry from a free Apple ID is fine for a 15-min test.

**Do:** trigger one route change (BT connect, BT disconnect, or `coreaudiod` restart).

**Expected:**
```
Name : audio.session.route_changed
  -> reason: Str(newDeviceAvailable | oldDeviceUnavailable | categoryChange | ...)
  -> previous_outputs: <list of strings>
  -> current_outputs: <list of strings>
```

The `reason` enum is from `AVAudioSession.RouteChangeReason`. Don't be surprised by `categoryChange` events fired by our own `setActive(.playAndRecord)` at boot — those are real events and worth keeping (proves the wire works).

**Failure modes:**
- Event fires once per `setCategory` we issue (we make several at startup) → annoying noise. Consider gating on `reason != categoryChange` in T5a code or just filtering in Grafana later.

### T4 — Android `ACTION_AUDIO_BECOMING_NOISY`

**Prereq:** Android NDK is working on the host. From the project root:

```bash
ls "$HOME/Library/Android/sdk/ndk/" 2>&1
flutter doctor 2>&1 | grep -i android
```

If NDK is corrupt, fix it first (delete the malformed dir, let Gradle re-download) — that was the F3 finding from the 2026-05-17 session.

**Do:**

```bash
# Build dev flavor for Android emulator
flutter run --flavor dev --target lib/main_dev.dart \
  --dart-define=OTEL_COLLECTOR=http://localhost:4318 \
  -d <android-emulator-id>
# In Record tab, tap mic to engage.
# Then, from the host:
adb shell am broadcast -a android.media.AUDIO_BECOMING_NOISY
```

**Why:** iOS doesn't have this concept; this is Android-specific. Lets you reproduce a headphone-unplug-like event without physical headphones.

**Expected:**
```
Name : audio.becoming_noisy
```

(No attributes — the broadcast itself carries no payload of interest.)

**Failure modes:**
- Event doesn't fire → the receiver was not registered. Check that `BuildConfig.ENABLE_TELEMETRY` was true in the dev build (run `adb shell dumpsys package com.voiceagent.voice_agent.dev | grep -i flavor` and confirm the dev variant is installed).
- Event fires but no other audio.* events ever appear on the Android side → expected (we did not add focus listeners; the proposal explicitly dropped `audio.focus.*`).

### T5 — Span pinning

**Do:** with hands-free engaged through T2/T3/T4, disengage. The long-lived `hf.attach_stream` span ends and exports.

**Why:** Per the proposal, native bridge events are added as **span events** on the active `hf.attach_stream` span. Verifying this end-to-end means the Grafana trace view (once T2/T7 land) will show audio interruptions inline on the engagement timeline, not as orphaned standalone events.

**Expected:** in the exported `hf.attach_stream` span block, the events list should include the interruption/route-change/becoming-noisy entries with the same timestamps you observed live in T2/T3/T4.

```bash
docker logs voice-agent-otel-spike | awk '/Name +: hf.attach_stream/,/^Span #|^ScopeSpans|^ResourceSpans/'
```

**Failure modes:**
- Native events appear as standalone spans (not as events on `hf.attach_stream`) → the consumer didn't route via `Telemetry.instance.addEventToActiveSpan` (or equivalent). Pinning was the whole point of the long-lived span design from T5b — fix in T5a before merging.

### T6 — Existing media-button behavior unchanged

**Do:** press the physical media button or use the Simulator's media controls. Compare `[MediaButtonDbg]` and `[VolumeBtnDbg]` debug logs with the pre-T5a baseline (you can pull from any commit before T5a in git history).

**Why:** T5a extends `MediaButtonBridge` rather than replacing it. Behavior of the existing media-button → TTS-stop / engagement-toggle path must be byte-identical.

**Expected:** identical debug print sequences. Same toaster messages ("Listening" / "Paused"). Same haptic feedback.

**Failure modes:**
- Any difference in `[MediaButtonDbg]` log shape vs baseline → the extension touched the wrong closure or added a duplicate. Revert the bridge changes and reapply minimally.

---

## What to capture on failure

```bash
docker logs voice-agent-otel-spike > /tmp/p039-t5a-collector.log
# Plus the flutter run console output (Cmd+C from the terminal).
# Plus, for Android: adb logcat -d -t 200 > /tmp/p039-t5a-logcat.txt
```

File an issue titled `P039 T5a — manual verification failure` with both logs and reference this file.

---

## When you're done

### All green
Update `docs/proposals/039-otel-dev-telemetry.md` Status — change "T5a — pending" to "T5a verified on iOS Simulator + Android emulator on YYYY-MM-DD". T2/T7/T8 are then the remaining tracks.

### Partial / red
Don't paper over. Save the logs, file the issue, stop. The bridge either works or stays broken in a known way until the fix lands.

### Teardown

```bash
cd ops/dev && docker compose -f collector-only.docker-compose.yml down
# Cmd+C the flutter run terminal
# adb kill-server  # optional, if you exercised Android
```
