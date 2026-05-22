# Proposal 041 — Suppress spurious volume events during audio-session transitions

## Status: Implemented (lightweight; manual device verification pending). Hotfix follow-up to P038.

## Problem

Tapping the mic button to start a hands-free conversation is flaky: the
screen flips green → orange and the recording indicator appears (the
session engages), then the session immediately disengages back to idle
(green, no indicator). It works sometimes, fails more often.

This is a device-blocking bug — the primary "start a conversation"
gesture is unreliable.

## Research notes — root cause

P038 introduced `VolumeButtonBridge.swift`, which detects hardware
volume-button presses via KVO on `AVAudioSession.outputVolume`. Volume
Down while engaged maps to `HandsFreeController.suspendByUser()`
(`recording_screen.dart` `_onVolumeButtonEvent`).

`AVAudioSession.outputVolume` is **tracked per audio-session category
context** — iOS reports a different value once the category switches.
Starting a session changes the category:

1. `_onTap()` → `HandsFreeController.startSession()` →
   `BackgroundService.startService()` (`hands_free_controller.dart`).
2. On iOS, `startService()` invokes `setPlayAndRecord`
   (`flutter_foreground_task_service.dart`).
3. `AudioSessionBridge` runs `setCategory(.playAndRecord)` +
   `setActive(true)` (`AudioSessionBridge.swift`).
4. iOS reports a new `outputVolume` for the `.playAndRecord` context.
   The KVO observer in `VolumeButtonBridge.observeValue` fires.
5. `_stepThreshold` (0.001) is far below a real category-switch delta
   (~0.06+), so the change is **not** filtered. If the new value is
   lower than the old one, the bridge emits `"down"`.
6. `_onVolumeButtonEvent(down)` sees `hfState is HandsFreeListening`
   and calls `suspendByUser()` → the freshly engaged session is torn
   back down to idle.

`VolumeButtonBridge` has no way to distinguish a real button press from
an `outputVolume` change caused by an audio-session category or route
change.

### Why it is flaky

- **Delta direction**: the `.playAndRecord` context volume may be lower
  than the prior media volume (→ `"down"` → `suspendByUser` → **fails**),
  higher (→ `"up"` → `up-noop` while listening → **works**), or equal
  (→ no event → **works**). It depends on the device's volume state.
- **Delivery timing**: if the spurious event arrives before the state
  reaches `HandsFreeListening`, it hits the `down-noop (not engaged)`
  branch — harmless. If it arrives after, it triggers `suspendByUser`.

The same class of spurious event also fires on AirPods connect/disconnect
and on the `.playback` ⇄ `.playAndRecord` transitions around TTS.

## Scope

- **In scope**: stop audio-session category/route changes from being
  misread as hardware volume-button presses.
- **Out of scope**: programmatic volume restore after a real press
  (P038 *Known Compromises*); the `_stepThreshold` value (left as-is —
  a real category-switch delta can equal one genuine step, so a
  threshold alone cannot fix this).

## Approach

Native-only fix, in the two iOS bridges. A short suppression window
gates volume-button detection during any audio-session transition.

1. **`VolumeButtonBridge.swift`**
   - Add a `suppressUntil` timestamp and a public `suppressVolumeEvents()`
     method that arms a short window (`suppressionWindow = 0.6 s`).
   - In `observeValue`, while inside the window, update the running
     baseline (`lastVolume`) but emit **no** direction event.
   - Observe `AVAudioSession.routeChangeNotification` and call
     `suppressVolumeEvents()` on every route change. This catches
     category changes made outside `AudioSessionBridge` (e.g. the
     `record` plugin's own session setup, AirPods route changes).

2. **`AudioSessionBridge.swift`**
   - Before any category-mutating method (`setPlayAndRecord`,
     `setPlayback`, `setPlaybackOnly`, `restoreAudioSession`,
     `setAmbient`), call `VolumeButtonBridge.shared.suppressVolumeEvents()`.
   - This pre-arms the window *before* the KVO fires, covering the case
     where the `outputVolume` KVO is delivered synchronously inside
     `setActive(true)` — earlier than the route-change notification.

A Dart-side debounce was considered and rejected: the correct layer to
distinguish a real press from a context shift is the native bridge that
owns the KVO observer; a second guard in Dart would be redundant.

## Tasks

- [x] T1 — `VolumeButtonBridge`: suppression window + `suppressVolumeEvents()`
      + route-change observer.
- [x] T2 — `AudioSessionBridge`: pre-arm suppression before every
      category mutation.
- [x] T3 — Manual test plan (`docs/manual-tests/p041-volume-button-suppression.md`).

## Acceptance criteria

1. Tapping the green mic button engages a session that **stays** engaged
   (orange + recording indicator) — no immediate disengage.
2. A real Volume Down press while engaged still suspends the session.
3. A real Volume Up press while idle still engages a session.
4. Interrupting TTS with Volume Down still works (no regression).

## Verification

- `make verify` — Dart analyzer + tests (no Dart code changed; confirms
  no regression).
- Native Swift changes are device-only contracts — see the manual test
  plan `docs/manual-tests/p041-volume-button-suppression.md`. The
  proposal stays `manual device verification pending` until the
  must-pass cases there are green.
