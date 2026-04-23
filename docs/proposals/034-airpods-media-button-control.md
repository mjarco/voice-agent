# Proposal 034 — AirPods / Media Button Pause & Resume

## Status: Draft (seed)

## Origin

Conversation 2026-04-23. The user wants to pause and resume both hands-free
listening and manual dictation via AirPods media button (play/pause). This
extends to any Bluetooth headset or wired headphones with a media button.

## Prerequisites

- 012-hands-free-local-vad — VAD engine and session model
- 014-recording-mode-overhaul — recording lifecycle, gesture table, state guards
- 001-audio-capture — RecordingService and RecordingServiceImpl

All are implemented.

**No cross-project dependency.** This is entirely client-side.

## Scope

- Risk: Medium — touches platform-native audio session integration on both iOS
  and Android, adds a new platform channel, and introduces a new suspension
  reason in the hands-free controller
- Layers: `core/media_button/` (new — port + service), `ios/Runner/` (native
  Swift), `android/app/.../` (native Kotlin), `features/recording/domain/`
  (RecordingService + RecordingState), `features/recording/presentation/`
  (controllers + screen wiring)
- Expected PRs: 2 (core platform channel + recording integration)

## Problem Statement

The user operates the app hands-free while walking, cooking, or driving. The
phone is in a pocket or on a counter. The only way to pause listening or
dictation is to look at the screen and tap a button.

AirPods (and most Bluetooth headsets) have a physical play/pause button that
iOS and Android surface as media button events. Mapping this button to
pause/resume would let the user control the app without touching the phone.

### Current pause/resume landscape

**Hands-free listening:**
- `suspendForManualRecording()` / `resumeAfterManualRecording()` — used when
  the user taps the mic button to start manual recording. Stops VAD, releases
  mic, preserves job backlog.
- `suspendForTts()` / `resumeAfterTts()` — used when TTS is speaking. Same
  pattern: stop VAD, preserve backlog, resume after.
- **No user-initiated pause** — the user can only fully stop the session
  (`stopSession()`), which tears down the foreground service and clears all
  state. There is no "pause" that keeps the session alive but mutes the mic.

**Manual dictation:**
- `RecordingService` wraps the `record` package's `AudioRecorder`.
- `record` v6 supports `pause()` and `resume()` natively. The app does NOT
  expose these — the only options are start, stop, and cancel.
- `RecordingState` has no `RecordingPaused` variant.

## Proposed Solution

### Platform Layer — Media Button Events

**New platform channel:** `com.voiceagent/media_button` per ADR-PLATFORM-005.

**Dart port (abstract interface) in `core/media_button/`:**

```dart
abstract class MediaButtonPort {
  Stream<MediaButtonEvent> get events;
  Future<void> activate();
  Future<void> deactivate();
}

enum MediaButtonEvent { togglePlayPause }
```

Only `togglePlayPause` in v1. Future events (next, previous, long press)
reserved for later proposals.

**Why `activate()` / `deactivate()`:** On iOS, `MPRemoteCommandCenter` requires
an active `MPNowPlayingInfoCenter` session to receive events. On Android,
`MediaSessionCompat` must be set active. These should only be active when the
app is in a recording mode (hands-free or manual) — not always, to avoid
interfering with music apps.

#### iOS (Swift)

Extend `ios/Runner/` with a new `MediaButtonBridge.swift`:

- Register `MPRemoteCommandCenter.shared().togglePlayPauseCommand` handler
- On `activate()`: set `MPNowPlayingInfoCenter.default().nowPlayingInfo` to a
  minimal dict (app name, no artwork) and enable the toggle command
- On `deactivate()`: remove the command handler and clear now-playing info
- Forward toggle events to Dart via `EventChannel`

The `.playAndRecord` audio session category (already set by
`AudioSessionBridge` during hands-free) is required for `MPRemoteCommandCenter`
to work. When in `.ambient` category (idle state), media button events go to
the system music player — this is the correct behavior (we don't want to
intercept media buttons when the app isn't actively recording).

#### Android (Kotlin)

Add `MediaButtonBridge.kt` in `android/app/src/main/kotlin/com/voiceagent/voice_agent/`:

- Create `MediaSessionCompat` with a `MediaSessionCompat.Callback` that
  overrides `onPlay()`, `onPause()`, and `onMediaButtonEvent()`
- On `activate()`: set `isActive = true`
- On `deactivate()`: set `isActive = false`, release session
- Forward events to Dart via `EventChannel`

Android's `AudioManager` routes media button events to the active
`MediaSession`. Since the app already runs a foreground service during
hands-free mode, the media session will receive events reliably.

### Dart Service — `MediaButtonService`

```
core/media_button/
  media_button_port.dart       -- abstract interface (Stream<MediaButtonEvent>)
  media_button_service.dart    -- implementation wrapping platform EventChannel
  media_button_provider.dart   -- Riverpod provider
```

`MediaButtonService implements MediaButtonPort`:
- `activate()`: sends `activate` to the native side via MethodChannel
- `deactivate()`: sends `deactivate`
- `events`: exposes the EventChannel stream as `Stream<MediaButtonEvent>`

The provider is a simple `Provider<MediaButtonPort>` — no state management
needed, just event forwarding.

### Recording Layer — Pause/Resume for Manual Dictation

**RecordingService interface changes:**

```dart
abstract class RecordingService {
  // ... existing methods ...
  Future<void> pause();
  Future<void> resume();
}
```

**RecordingServiceImpl:** Delegates to `AudioRecorder.pause()` and
`AudioRecorder.resume()` from the `record` package (v6 supports this
natively).

**Elapsed timer during pause:** The current implementation uses
`DateTime.now().difference(_startTime!)` which would continue advancing during
pause. On `pause()`: cancel the periodic timer, store the accumulated elapsed
duration. On `resume()`: reset `_startTime` to `DateTime.now()` and restart the
periodic timer, adding the accumulated duration to each new emission. This
keeps the elapsed display frozen during pause and accurate after resume.

**RecordingState changes:**

```dart
sealed class RecordingState {
  // ... existing variants ...
  const factory RecordingState.paused() = RecordingPaused;
}

class RecordingPaused extends RecordingState {
  const RecordingPaused();
}
```

**RecordingController changes:**

```dart
Future<void> pauseRecording() async {
  if (state is! RecordingActive) return;
  await _service.pause();
  state = const RecordingState.paused();
}

Future<void> resumeRecording() async {
  if (state is! RecordingPaused) return;
  await _service.resume();
  state = const RecordingState.recording();
}
```

### Recording Layer — Pause/Resume for Hands-Free Listening

**HandsFreeSessionState changes — new `HandsFreeSuspendedByUser` variant:**

```dart
class HandsFreeSuspendedByUser extends HandsFreeSessionState {
  const HandsFreeSuspendedByUser(this.jobs);
  final List<SegmentJob> jobs;
}
```

This is a distinct state (not `HandsFreeListening`) so the UI can render a
"Paused" indicator and `RecordingScreen` can dispatch resume on the next
media button press without inspecting private controller state.

**HandsFreeController changes:**

Add a new suspension reason alongside the existing ones:

```dart
bool _suspendedByUser = false;
```

```dart
/// Toggles user-initiated suspension. Called by media button dispatch.
/// Returns true if the session is now suspended, false if resumed.
Future<bool> toggleUserSuspend() async {
  if (_suspendedByUser) {
    await resumeByUser();
    return false;
  } else {
    await suspendByUser();
    return true;
  }
}

Future<void> suspendByUser() async {
  if (_suspendedByUser) return;
  if (state is HandsFreeIdle || state is HandsFreeSessionError) return;

  // Fast path: if already suspended for TTS, the engine is already stopped.
  // Just set the flag — resumeAfterTts() will check it and skip restart.
  if (_suspendedForTts || _suspendedForManualRecording) {
    _suspendedByUser = true;
    state = HandsFreeSuspendedByUser(List<SegmentJob>.unmodifiable(_jobs));
    return;
  }

  if (state is HandsFreeCapturing) {
    await _engine?.interruptCapture();
  } else {
    await _engineSub?.cancel();
    await _engine?.stop();
  }
  _engineSub = null;
  _engine = null;
  _suspendedByUser = true;
  state = HandsFreeSuspendedByUser(List<SegmentJob>.unmodifiable(_jobs));
}

Future<void> resumeByUser() async {
  if (!_suspendedByUser) return;
  _suspendedByUser = false;
  if (_suspendedForManualRecording || _suspendedForTts) {
    state = _listeningOrBacklog();
    return;
  }
  _startEngine(_ref.read(appConfigProvider).vadConfig);
  state = _listeningOrBacklog();
}
```

**Suspension priority:** If the user pauses via media button while TTS is
playing, the user pause takes precedence — `resumeAfterTts()` should NOT
resume if `_suspendedByUser` is true. Similarly, `resumeAfterManualRecording()`
should NOT resume if `_suspendedByUser` is true.

This means existing resume methods need a guard:

```dart
Future<void> resumeAfterTts() async {
  if (!_suspendedForTts) return;
  _suspendedForTts = false;
  if (_suspendedForManualRecording || _suspendedByUser) return; // added guard
  _startEngine(...);
}
```

Same pattern for `resumeAfterManualRecording()`.

**`reloadVadConfig()` guard:** Add `if (_suspendedByUser) return;` alongside
the existing `if (_suspendedForManualRecording) return;` guard, so VAD config
changes don't restart the engine while the user has explicitly paused.

### Wiring — RecordingScreen Listener

A `ref.listen` on `mediaButtonProvider.events` in `RecordingScreen` dispatches
the toggle based on current state:

```
Media button toggle received:
  1. RecordingActive       → pauseRecording()
  2. RecordingPaused       → resumeRecording()
  3. HandsFreeListening / HandsFreeWithBacklog / HandsFreeCapturing
                           → toggleUserSuspend() + toast "Paused" + haptic
  4. HandsFreeSuspendedByUser
                           → toggleUserSuspend() + toast "Resumed" + haptic
  5. HandsFreeIdle         → no-op (session not started)
  6. RecordingTranscribing → no-op (can't interrupt STT)
  7. HandsFreeStopping     → no-op (draining in-flight jobs)
```

The `HandsFreeSuspendedByUser` state variant (distinct from `HandsFreeListening`)
makes rules 3 and 4 distinguishable without inspecting private controller state.

**Mic button tap handler (`_onTap`) updates:**
- Add `RecordingPaused` case: calls `resumeRecording()` (same as media button)
- Existing `RecordingIdle` and `RecordingActive` cases unchanged

**New conversation button guard:** Add `recState is RecordingPaused` to the
disable condition alongside `RecordingActive` and `RecordingTranscribing` —
a paused recording is still in-progress.

**App lifecycle guard:** Update `RecordingController.didChangeAppLifecycleState`
to cancel on `RecordingPaused` in addition to `RecordingActive` — a paused
recording should not survive app backgrounding.

**Activation lifecycle:** Activate the media button service when the recording
screen mounts (the hands-free session auto-starts on mount, so the media button
is available immediately). Deactivate when the screen unmounts. This is simpler
than tracking individual session starts — the screen mount/unmount lifecycle
already aligns with the recording session lifecycle.

For the edge case where hands-free is not active (session stopped or error),
the dispatch table maps to no-op (rule 5), so capturing media buttons while
idle on the recording screen is harmless.

### UI Feedback

**Hands-free paused state:** The recording screen should show a visual
indicator that listening is paused (e.g., a pulsing pause icon overlay on the
mic button, or a subtle banner "Listening paused"). The existing mic button
animation (which shows listening state) will naturally stop when VAD is
suspended.

**Manual recording paused state:** The mic button should show a paused
indicator (e.g., pause icon instead of stop icon). The elapsed timer freezes.
Tapping the mic button while paused should resume (same as media button).

Toast and haptic feedback on pause/resume via `Toaster` and `HapticService`
from `core/session_control/` (introduced by P029).

## Acceptance Criteria

1. Pressing the AirPods play/pause button while hands-free is listening
   suspends VAD. Pressing again resumes VAD. The foreground service stays
   alive. Job backlog is preserved.
2. Pressing the AirPods play/pause button while manually recording pauses
   the recording. Pressing again resumes. The elapsed timer pauses/resumes.
3. If TTS finishes while the user has manually paused hands-free, VAD does
   NOT auto-resume — the user pause takes precedence.
4. Media button events are only captured when the app has an active
   recording/listening session. When idle, media buttons control system
   music as normal.
5. Works with AirPods, AirPods Pro, and any Bluetooth headset that sends
   standard media button events.
6. Works on both iOS 16+ and Android SDK 24+.
7. `RecordingState.paused()` is a new sealed class variant. UI renders a
   pause indicator. Screen tap resumes (same as media button).
8. No cross-feature imports. `core/media_button/` imports only from `core/`.
   `features/recording/` uses `core/media_button/` providers.
9. `make verify` passes. `flutter analyze` passes with zero issues.

## Tasks

| # | Task | Layer | Notes |
|---|------|-------|-------|
| T1 | **Platform channel + Dart port.** `MediaButtonPort` interface, `MediaButtonService` implementation, iOS `MediaButtonBridge.swift` (MPRemoteCommandCenter), Android `MediaButtonBridge.kt` (MediaSessionCompat), `EventChannel` stream, Riverpod provider. Unit tests with mocked platform channel. | core/media_button, ios/Runner, android/app | Mergeable alone (no UI change). |
| T2 | **Recording pause/resume.** Add `pause()` / `resume()` to `RecordingService` + impl (with elapsed timer pause tracking). Add `RecordingPaused` state. Add `pauseRecording()` / `resumeRecording()` to `RecordingController`. Add `HandsFreeSuspendedByUser` state variant. Add `toggleUserSuspend()` / `suspendByUser()` / `resumeByUser()` to `HandsFreeController` with suspension priority guards. Update `reloadVadConfig()` guard. Update `_onTap` for `RecordingPaused`. Update new-conversation-button and app-lifecycle guards. Wire media button listener in `RecordingScreen`. Toast + haptic. UI indicators for both paused states. Widget tests for all pause/resume/dispatch/priority paths. | features/recording | Depends on T1. |

## Test Impact

**New test files:**
- `test/core/media_button/media_button_service_test.dart` — platform channel
  mock, activate/deactivate, event stream, activate failure handling
- `test/features/recording/presentation/recording_controller_pause_test.dart` —
  pause/resume state transitions, elapsed timer freeze/resume, app lifecycle
  cancellation from paused state
- `test/features/recording/presentation/hands_free_controller_pause_test.dart` —
  toggleUserSuspend/suspendByUser/resumeByUser, suspension priority matrix
  (user+TTS, user+manual, all three), capturing-to-suspended transition
  (verifies in-progress segment is discarded), reloadVadConfig guard
- `test/features/recording/presentation/recording_screen_media_button_test.dart` —
  widget test: media button event dispatches correct action per state,
  _onTap handles RecordingPaused, new-conversation-button disabled when paused

**Modified tests:**
- Existing `recording_controller_test.dart` — mock gains `pause()` / `resume()`
- Existing `hands_free_controller_test.dart` — verify existing suspend/resume
  methods respect `_suspendedByUser` guard
- Existing `recording_screen_test.dart` — exhaustive switch on `RecordingState`
  must handle `RecordingPaused` (compile-time enforcement via sealed class)

## Risks

| Risk | Mitigation |
|------|------------|
| `MPRemoteCommandCenter` requires now-playing info to be set — if not set correctly, events go to the music app instead of our app | Test on device during T1. The key is setting `MPNowPlayingInfoCenter` with minimal info when activating. Known pattern used by podcast and voice memo apps. |
| Android `MediaSessionCompat` may conflict with other media apps if not properly activated/deactivated | Strict activate/deactivate lifecycle tied to recording session start/stop. When deactivated, media buttons go back to the system. |
| `record` package `pause()` on iOS may not work with `.playAndRecord` category | The `record` package uses `AVAudioRecorder` which supports pause natively. `.playAndRecord` category doesn't restrict this. Verify on device in T2. |
| Suspension priority bugs — user pauses, TTS finishes, manual recording starts — complex state interactions | Explicit boolean flags (`_suspendedByUser`, `_suspendedForTts`, `_suspendedForManualRecording`) with clear priority: user pause always wins. Unit tests for all combinations. |
| AirPods double-tap / squeeze gesture sends different events on different models | We only handle `togglePlayPauseCommand` which is the standard single-press event. Double-tap and squeeze are mapped to different `MPRemoteCommand` targets (next/previous) and are out of scope. |

## Dependencies

| Dependency | Status | Blocking? |
|---|---|---|
| 012-hands-free-local-vad | Implemented | No |
| 014-recording-mode-overhaul | Implemented | No |
| 001-audio-capture | Implemented | No |
| ADR-PLATFORM-005 (platform channel pattern) | Accepted | Pattern to follow |
| ADR-AUDIO-009 (conditional audio session) | Accepted | `.playAndRecord` already set during hands-free |

## When to Address

Can start immediately. No external dependencies. T1 (platform channel) can be
developed and tested on device independently.

## Related

- 012-hands-free-local-vad (VAD session lifecycle)
- 014-recording-mode-overhaul (gesture table, state guards)
- 029-honor-session-control-signals (Toaster, HapticService for feedback)
- ADR-PLATFORM-005 (platform channel naming and placement)
- ADR-AUDIO-009 (conditional audio session switch)
