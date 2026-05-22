# Manual test: P042 — recover hands-free capture across audio route changes

**Proposal:** [`docs/proposals/042-recover-hands-free-capture-across-route-changes.md`](../proposals/042-recover-hands-free-capture-across-route-changes.md)
**Overall status:** **pending** — no case yet executed on a physical device.
**Why now:** P042 makes the hands-free pipeline re-acquire the microphone when the iOS audio route changes. Route changes, `AVAudioSession` behaviour and the `record` plugin's stream lifecycle are device-only — `flutter test` cannot exercise them.
**Time budget:** ~15 min, iPhone only.
**What we are testing:** that removing/adding an audio device while a session is engaged keeps capture working — and never leaves the app in `HandsFreeListening` (orange) with a dead mic.

## Status legend

See the canonical legend in [`p040-agenda-notifications.md`](p040-agenda-notifications.md#status-legend).

## Status summary

| # | Case | Status |
|---|---|---|
| S1 | Install on iPhone | pending |
| T1 | AirPod removal → capture continues on built-in mic | pending |
| T2 | AirPod re-insertion → capture continues | pending |
| T3 | Wired headphone un/plug → capture continues | pending |
| T4 | Never stuck orange with a dead mic | pending |
| T5 | Watchdog recovers a silent mic | pending |

---

## Setup

### S1 — Install on iPhone

**Status:** pending

**Do:** install the dev flavour on a physical iPhone (route changes and
`AVAudioSession` cannot be exercised on Simulator).

```bash
flutter run --flavor dev --target lib/main_dev.dart \
  --dart-define-from-file=.env.mobile -d <ios-device-id>
```

Confirm mic permission, Groq key and API URL are configured. Keep a
console attached — `[AudioRouteDbg]` (native route changes) and `[HFO]`
(orchestrator restart) lines confirm the path.

---

## Tests

### T1 — AirPod removal → capture continues (~3 min)

**Status:** pending

**Do:**
1. With AirPods connected, tap the mic to engage (orange "Listening...").
2. Remove one AirPod from your ear. Keep watching the screen.
3. Speak a short sentence into the iPhone.

**Why:** verifies the P042 core fix — `oldDeviceUnavailable` route change
triggers `_restartCapture()`, re-acquiring the mic on the built-in route.

**Expected:** the session stays engaged; speaking still produces a
segment/transcript. Console shows `[AudioRouteDbg] route change:
oldDeviceUnavailable` then `[HFO] restarting capture`. The pre-fix
behaviour (orange button, no recording indicator, voice not captured)
must not occur.

**On failure:** if capture stays dead, check the console — no
`[AudioRouteDbg]` line means the native EventChannel is not wired
(`AudioSessionBridge.configure`); a `[AudioRouteDbg]` line without a
following `[HFO] restarting capture` means the reason was not treated as
input-affecting, or the orchestrator's route subscription is not active.

---

### T2 — AirPod re-insertion → capture continues (~2 min)

**Status:** pending

**Do:**
1. Continuing from T1 (engaged, capturing on built-in mic), put the
   AirPod back in.
2. Speak again.

**Why:** `newDeviceAvailable` must also re-acquire capture.

**Expected:** capture continues; speaking produces a segment. Console
shows a route change + restart.

---

### T3 — Wired headphone un/plug → capture continues (~3 min)

**Status:** pending

**Do:**
1. Engage a session. Plug in wired headphones (or a Lightning/USB-C
   adapter). Speak.
2. Unplug them. Speak again.

**Why:** verifies the fix is route-agnostic, not AirPods-specific.

**Expected:** capture survives both transitions.

**On failure:** if `startStream()` re-acquisition fails, the controller
must show `HandsFreeSessionError` (red, with Retry) — a visible error,
never a silent dead mic.

---

### T4 — Never stuck orange with a dead mic (~2 min)

**Status:** pending

**Do:** repeat T1–T3 a few times, quickly. After each, check the iOS
recording indicator (orange dot / pill in the status bar).

**Why:** the central P042 guarantee — app state must match reality.

**Expected:** whenever the mic button is orange (`HandsFreeListening`),
the iOS recording indicator is present and speaking is captured. The two
never diverge.

---

### T5 — Watchdog recovers a silent mic (~3 min)

**Status:** pending

**Do:** this is hard to trigger deliberately — the watchdog is a safety
net for silent-mic causes the route-change path misses. If during normal
use the mic ever goes silent while engaged, wait ~3–6 s without
navigating away.

**Why:** verifies the silent-mic watchdog (`hf.watchdog_restart`).

**Expected:** capture recovers within ~6 s without a tab switch. Console
shows `[HFO] watchdog: no audio ... restarting`.

**On failure:** if a silent mic never recovers, the watchdog timer is not
running — check it is started in `_doStart` and not cancelled early.

---

## When this plan is "done"

- **T1, T2, T3, T4 must PASS** — the core route-change recovery and the
  state-consistency guarantee. Any failure blocks shipping.
- **T5** is opportunistic; mark `skipped (not reproduced)` if the silent
  mic never occurs during the session.

Once the must-pass cases are green, P042 drops the
`manual device verification pending` disclaimer.
