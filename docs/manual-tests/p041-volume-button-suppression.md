# Manual test: P041 — Suppress spurious volume events during audio-session transitions

**Proposal:** [`docs/proposals/041-volume-button-spurious-event-on-session-start.md`](../proposals/041-volume-button-spurious-event-on-session-start.md)
**Overall status:** **pending** — no case yet executed on a physical device.
**Why now:** P041 fixes a flaky disengage caused by `AVAudioSession.outputVolume` KVO firing on category changes. The fix is native Swift (`VolumeButtonBridge` / `AudioSessionBridge`) and cannot be exercised by `flutter test` — KVO, audio-session category transitions and hardware volume buttons are device-only.
**Time budget:** ~15 min, iPhone only (the bridge is iOS-only).
**What we are testing:** that an audio-session category/route change no longer produces a phantom volume-button event, while real volume-button presses still work.

## Status legend

See the canonical legend in [`p040-agenda-notifications.md`](p040-agenda-notifications.md#status-legend).

## Status summary

| # | Case | Status |
|---|---|---|
| S1 | Install on iPhone | pending |
| T1 | Tap mic → session stays engaged | pending |
| T2 | Real Volume Down while engaged still suspends | pending |
| T3 | Real Volume Up while idle still engages | pending |
| T4 | Volume Down interrupts TTS (no regression) | pending |

---

## Setup

### S1 — Install on iPhone

**Status:** pending

**Do:** install on a physical iPhone (per [[no_apple_developer_account]], personal cert + real device — the bridge is iOS-only, Simulator has no hardware volume buttons).

```bash
flutter run --flavor dev --target lib/main_dev.dart \
  --dart-define=API_URL=https://<your-personal-agent>/api/v1 \
  --dart-define=API_TOKEN=<token> \
  --dart-define=GROQ_API_KEY=<groq-key> \
  -d <ios-device-id>
```

Make sure mic permission, Groq key and API URL are all configured — otherwise `startSession()` lands in an error state instead of engaging.

Keep a console attached: `[VolumeBtnDbg]` lines show raw KVO and suppression decisions; `[AudioSessionDbg]` lines show category switches.

---

## Tests

### T1 — Tap mic → session stays engaged (~4 min)

**Status:** pending

**Do:**
1. Launch the app; land on the Record tab (green mic).
2. Tap the mic button once.
3. Watch the button colour and the status strip for the next ~3 s.
4. Repeat the tap-and-watch cycle ~10 times, varying the device media
   volume (low / mid / high) between attempts.

**Why:** verifies the P041 core fix — the `.playAndRecord` category
switch on `startSession()` no longer emits a phantom `"down"` that
`_onVolumeButtonEvent` turns into `suspendByUser()`.

**Expected:** every tap engages and **stays** engaged — button goes
green → orange and the "Listening..." strip remains visible. Console
shows `[VolumeBtnDbg] volume change suppressed (audio-session
transition)` around each engage, and no `branch=suspend` line. The
pre-fix flaky disengage (orange flashes, then back to green) must not
occur in any of the ~10 attempts.

**On failure:** check the console ordering — if a `[VolumeBtnDbg] volume
down` line appears *without* a preceding suppression window, the
`AudioSessionBridge` pre-arm did not run before the KVO fired, or the
KVO came from a route change whose notification arrived after the KVO.
Consider widening `suppressionWindow` in `VolumeButtonBridge.swift`.

---

### T2 — Real Volume Down while engaged still suspends (~3 min)

**Status:** pending

**Do:**
1. Tap the mic to engage (button orange, "Listening...").
2. Wait ~2 s so any audio-session transition has settled.
3. Press the hardware **Volume Down** button once.

**Why:** confirms the suppression window does not swallow genuine
presses — `suspendByUser()` must still fire.

**Expected:** session suspends — button returns to green, "Paused"
toast, light haptic. Console shows `[VolumeBtnDbg] volume down` and
`branch=suspend`.

**On failure:** if nothing happens, the suppression window is too long
or is being re-armed by an unrelated route change — inspect the
`[VolumeBtnDbg]` timestamps.

---

### T3 — Real Volume Up while idle still engages (~2 min)

**Status:** pending

**Do:**
1. With the session idle (green mic), press hardware **Volume Up** once.

**Why:** confirms the Volume Up engage gesture (P038) is unaffected.

**Expected:** session engages — "Listening" toast, button orange.

**On failure:** check the press was outside any suppression window —
an idle screen should have no recent category change, so suppression
should not be active.

---

### T4 — Volume Down interrupts TTS (no regression) (~3 min)

**Status:** pending

**Do:**
1. Engage, speak a short utterance, wait for the agent's TTS reply.
2. While the agent is speaking, press **Volume Down**.

**Why:** TTS playback goes through `setPlayback` / `restoreAudioSession`,
which also pre-arm the suppression window. The Volume-Down-interrupts-TTS
path must still fire.

**Expected:** TTS stops immediately on the press. Console shows
`[VolumeBtnDbg] branch=stopTts`.

**On failure:** the `setPlayback` pre-arm window overlapped the press —
verify the press happened well after TTS audio actually started.

---

## When this plan is "done"

- **T1, T2, T3 must PASS** — they are the core fix plus its two
  no-regression guarantees. Any failure blocks shipping.
- **T4** should PASS; a failure scoped to a tight press-during-transition
  race may be documented in the proposal §Risks rather than blocking.

Once the must-pass cases are green, P041 drops the
`manual device verification pending` disclaimer.
