# Proposal 014 — Recording Mode Overhaul

## Status: Draft

## Prerequisites
- P012 (HandsFreeOrchestrator + VAD) — merged ✓
- P013 (VadConfig) — merged ✓

## Scope
- Tasks: ~4 (T2 depends on T1; T3 depends on T2; T4 depends on T3)
- Layers: domain, presentation, app
- Risk: Medium — fundamental UX change to recording, removal of review screen

---

## Problem Statement

The app requires the user to manually enable hands-free mode via a `SwitchListTile`,
which is unintentional — the target UX assumes the app is ready to listen immediately.
The review screen (`/record/review`) exists solely as a development scaffold and was
never intended for end users. The app also lacks intuitive manual recording modes:
quick recording via press-and-hold and a tap-to-record mode for longer utterances.

---

## Are We Solving the Right Problem?

**Root cause:** The app was built incrementally — hands-free as an option rather than
the default state, and the review screen as a temporary scaffold for testing. Neither
element reflects the intended UX.

**Alternatives dismissed:**
- *Keep SwitchListTile but default it to ON:* does not match the expected UX — one fewer
  toggle means one fewer step for the user.
- *Keep the review screen as an opt-in:* there is no use case for manual editing before
  sending in the current flow; it hinders hands-free UX.

**Smallest change?** No — this is a deliberate UX refactor, not a bug fix. The scope is
minimal: remove what is unnecessary, add two gestures to an existing button.

---

## Goals

- The app enters hands-free mode automatically on navigating to /record
- The user can tap the icon to start manual recording (tap-to-record)
- The user can hold the icon to record only while held (press-and-hold)
- After each manual recording the transcript goes directly to storage + sync, with no review step
- A spinner on the icon signals transcription in progress

## Non-goals

- No transcript editing before saving — intent: history is the source of truth
- No cancellation after releasing the button (press-and-hold always finalises the recording)
- We do not change VAD job queue logic (P012) beyond interrupting the active segment

---

## User-Visible Changes

The /record screen always shows a green mic icon (hands-free active).
Tap → red icon (recording manually) → tap again → spinner → back to green.
Press-and-hold → orange icon → release → spinner → back to green.
On `HandsFreeSessionError` (e.g. permission denied): an error message is shown
with a "Retry" button that restarts the session.
`SwitchListTile` is removed. The review screen (`/record/review`) is removed from the app.

Bottom section layout after T2 (top to bottom):
1. `_HfStatusStrip` — status text / error strip (always visible when HF is active)
2. `_SegmentList` — job list when non-empty
3. `_VadParamsStrip` — always visible, link to Advanced Settings

---

## Solution Design

### Three modes as screen states

The /record screen manages a single coordinated state:

| State | Colour | Managed by |
|-------|--------|------------|
| Hands-free (default) | green | `HandsFreeController` |
| Hands-free Stopping | green (gestures blocked) | `HandsFreeController` |
| Tap-to-record | red | `RecordingController` |
| Press-and-hold | orange | `RecordingController` (flag in screen state) |
| Transcribing (spinner) | spinner over last colour | `RecordingController` |
| Error | red message + Retry | `HandsFreeController` |

### Auto-start hands-free

`RecordingScreen` becomes a `ConsumerStatefulWidget`. In `initState`:

```dart
WidgetsBinding.instance.addPostFrameCallback((_) {
  if (mounted) ref.read(handsFreeControllerProvider.notifier).startSession();
});
```

`addPostFrameCallback` guarantees the widget is fully mounted before the async
permission check begins. Errors from `startSession()` land in `HandsFreeSessionError` —
a "Retry" button calls `startSession()` again, replacing the removed `SwitchListTile`
as the error-recovery mechanism.

### New HandsFreeEngine interface: `interruptCapture()`

The existing `stop()` in `HandsFreeOrchestrator` waits for the async WAV write to
complete (`_wavWriteCompleter`), which can take hundreds of milliseconds. Blocking
on a user gesture is unacceptable.

We add to `HandsFreeEngine`:

```dart
Future<void> interruptCapture();
```

**Lifecycle contract:** `interruptCapture()` is a full engine stop — it closes the
stream, discards the current WAV segment, and releases the microphone, identical to
`stop()` but without waiting for the WAV write to finish. After `interruptCapture()`
the engine is in `stopped` state (stream closed). `resumeAfterManualRecording()` then
calls `engine.start()` on the same instance — `HandsFreeOrchestrator` handles this
like any other `start()` (creates a new `StreamController`, calls `_doStart()`,
re-initialises VadService). There is no "paused" state — only stop + start.

Implementation in `HandsFreeOrchestrator.interruptCapture()`:
- Set `_phase = _Phase.idle` first — `_afterWavWrite` checks phase and no-ops when idle
- Cancel `_audioSub` (stops audio flow)
- Call `_audioRecorder.stop()` (releases microphone)
- Do not await `_wavWriteCompleter` — the fire-and-forget `_writeWav` will finish on
  its own, but `_afterWavWrite` will check `_phase == idle` and not emit any event
- WAV file cleanup: `_afterWavWrite` when `_phase == idle` and `wavPath != null` MUST
  delete the file (`File(wavPath).deleteSync(recursive: false)`) before returning —
  otherwise the partial file stays on disk permanently (the file is already written by
  `_writeWav`; the early-return alone does not remove it)
- Close the `_controller` stream and call `_vadService.dispose()` — identical to `stop()`
  but without `await _wavWriteCompleter` (IMPORTANT: the stream must be closed, otherwise
  `resumeAfterManualRecording()` creates a new stream in `start()` while the old
  `_controller` leaks)

Verification: `VadServiceImpl.init()` is safe to call after `dispose()` — it creates a
new `VadIterator` each time, so re-init inside `_doStart()` is safe.

### Suspending VAD for manual recording

New method signatures on `HandsFreeController`:

```dart
/// Interrupts the active VAD segment and releases the microphone.
/// The job backlog is preserved.
/// Returns when the microphone is free and RecordingController can start.
Future<void> suspendForManualRecording() async {
  if (state is HandsFreeCapturing) {
    await _engine?.interruptCapture();   // full stop without WAV wait, current segment discarded
  } else if (state is HandsFreeListening || state is HandsFreeWithBacklog) {
    await _engineSub?.cancel();
    await _engine?.stop();
  } else if (state is HandsFreeStopping) {
    // HandsFreeStopping: WAV write IS in progress (_wavWriteCompleter not yet complete).
    // stop() blocks on _wavWriteCompleter (~100-500ms). This segment will enter the backlog.
    // We accept this latency — HandsFreeStopping is rare and the segment is worth keeping.
    await _engineSub?.cancel();
    await _engine?.stop();
  }
  _engineSub = null;
  _engine = null;
  _suspendedForManualRecording = true;
  // Emit transition state using the existing _listeningOrBacklog() predicate.
  // Do NOT use _jobs.isEmpty — the correct predicate is active (Queued/Transcribing/Persisting)
  // jobs, not list size (terminal jobs do not count as backlog).
  state = _listeningOrBacklog();
}

/// Restarts the VAD engine after manual recording completes.
/// IMPORTANT: does NOT clear _jobs or _jobCounter — backlog is preserved.
/// Unlike startSession(), this method ONLY recreates the engine/subscription
/// and emits state based on existing _jobs.
Future<void> resumeAfterManualRecording() async {
  _suspendedForManualRecording = false;
  final config = _ref.read(appConfigProvider).vadConfig;
  _engine = _ref.read(handsFreeEngineProvider);
  final stream = _engine!.start(config: config);
  _engineSub = stream.listen(_onEngineEvent, ...);
  // _jobs and _jobCounter are NOT reset — unlike startSession()
  // Use existing predicate _listeningOrBacklog() (active jobs, not isEmpty)
  state = _listeningOrBacklog();
}
```

Call sequence in `RecordingScreen`:

```
1. await hfCtrl.suspendForManualRecording()  // microphone free
2. recCtrl.startRecording()                  // manual recording
3. (user finishes recording)
4. await recCtrl.stopAndTranscribe()         // transcription + save
5. await hfCtrl.resumeAfterManualRecording() // VAD resumes
```

### Lifecycle: app backgrounded during manual recording

`RecordingController.cancelRecording()` (called by `didChangeAppLifecycleState`)
emits `RecordingIdle`. `RecordingScreen` observes this state via `ref.listen`
and when it detects a transition to `RecordingIdle` while HF is suspended — calls
`resumeAfterManualRecording()`. This prevents a HF suspension deadlock.

The "suspended" state is tracked as bool `_suspendedForManualRecording` in
`HandsFreeController` — set in `suspendForManualRecording()`, cleared in
`resumeAfterManualRecording()`.

### Gesture guard table

All `(recordingState, gesture)` combinations must be handled:

| recordingState | HF state | gesture | action |
|---|---|---|---|
| `RecordingIdle` | `HandsFreeListening/Capturing/WithBacklog` | tap | suspend → startRecording |
| `RecordingIdle` | `HandsFreeStopping` | tap | **no-op** (wait for Stopping to finish) |
| `RecordingActive` | suspended | tap | stopAndTranscribe |
| `RecordingTranscribing` | suspended | tap | **no-op** |
| `RecordingIdle` | `HandsFreeListening/Capturing/WithBacklog` | longPressStart | suspend → startRecording |
| `RecordingIdle` | `HandsFreeStopping` | longPressStart | **no-op** |
| `RecordingActive` | suspended | longPressEnd | stopAndTranscribe(silentOnEmpty: true) |
| `RecordingActive` | suspended | longPressStart | **no-op** |
| `RecordingTranscribing` | suspended | longPressStart | **no-op** |
| `RecordingError` | any | tap | resetToIdle (→ RecordingIdle → ref.listen → resumeAfterManualRecording() when suspended) |

`RecordingError` row: `resetToIdle()` emits `RecordingIdle`, which triggers `ref.listen`
in `RecordingScreen`. `ref.listen` checks `isSuspendedForManualRecording` and calls
`resumeAfterManualRecording()` — HF resumes automatically. No separate row needed for
"RecordingError + HF suspended + tap → resume".

### Empty transcription result — press-and-hold mode

A press-and-hold with an empty result (`text.isEmpty`) is treated as a silent no-op:
emit `RecordingIdle` + `resumeAfterManualRecording()` without showing an error.
Tap-to-record preserves the current behaviour (emit `RecordingError`).

Implementation: add `bool silentOnEmpty = false` to `stopAndTranscribe()`.

### Mic button — widget structure

`_IdleView` and `_HfMicIndicator` are removed. They are replaced by a single
`_MicButton` widget using a `GestureDetector` wrapping a `Container` with `InkWell`
(not `IconButton.filled` — disabled buttons do not respond to `GestureDetector`).

**GestureDetector tap vs longPress conflict:** Flutter fires `onTap` after `onLongPressEnd`
by default. To eliminate the double-action risk, `_MicButton` tracks a `_longPressActive`
bool (setState):
- `onLongPressStart` → `_longPressActive = true`
- `onLongPressEnd` → action + `_longPressActive = false`
- `onTap` → if `_longPressActive` was `true` at the time of the call → **no-op** (long press already handled)

`onTap` checks `_longPressActive` BEFORE executing any logic.
We do not rely on state update timing — the explicit bool is deterministic.

```dart
GestureDetector(
  onTap: _onTap,
  onLongPressStart: _onLongPressStart,
  onLongPressEnd: _onLongPressEnd,
  child: AnimatedContainer(
    decoration: BoxDecoration(
      color: _iconColor,   // green / red / orange / grey
      shape: BoxShape.circle,
    ),
    child: _isTranscribing
        ? CircularProgressIndicator()
        : Icon(Icons.mic),
  ),
)
```

### Removing the review screen

`RecordingController.stopAndTranscribe()` injects `StorageService` and after
transcription executes the same sequence as `HandsFreeController._processJob`:
`saveTranscript` + `enqueue`. The `RecordingCompleted` state is removed.
`TranscriptReviewScreen` is deleted from the codebase. The `/record/review`
route is removed from the router.

---

## Affected Mutation Points

**Needs change:**
- `HandsFreeEngine` interface — add `Future<void> interruptCapture()`
- `HandsFreeOrchestrator` — implement `interruptCapture()` (abort WAV write, release mic,
  close stream; add file cleanup in `_afterWavWrite` when phase == idle and wavPath != null)
- `HandsFreeController` — add `suspendForManualRecording()`, `resumeAfterManualRecording()`,
  bool `_suspendedForManualRecording`, public getter `isSuspendedForManualRecording`;
  remove the `RecordingActive` guard in `startSession()`;
  `didChangeAppLifecycleState` — add guard: `if (_suspendedForManualRecording) return;`
  before `_terminateWithError(...)` to avoid destroying suspended HF during backgrounding
  (RecordingController handles background cancel and triggers `resumeAfterManualRecording()` via ref.listen)
- `RecordingController` constructor — inject `StorageService`
- `RecordingController.stopAndTranscribe()` — add `bool silentOnEmpty`, after transcription:
  save + enqueue, emit `RecordingIdle`; remove emit `RecordingCompleted`
- `RecordingController.didChangeAppLifecycleState` — no logic change, but `RecordingScreen`
  must react to `RecordingIdle` when HF is suspended
- `RecordingState` — remove `RecordingCompleted`
- `RecordingScreen` — `ConsumerStatefulWidget`; auto-start via `addPostFrameCallback`;
  `ref.listen` for `RecordingIdle` → `resumeAfterManualRecording()` when suspended;
  new `_MicButton` widget with `GestureDetector`; remove `_IdleView`, `_HfMicIndicator`,
  `SwitchListTile`; bottom section layout per specification above
- `recording_providers.dart` — inject `StorageService` into `RecordingController` provider
- `router.dart` — remove `/record/review` route

**No change needed:**
- `HandsFreeOrchestrator._processJob()` — unchanged
- `SyncWorker` — unchanged
- `_VadParamsStrip` — unchanged
- `AdvancedSettingsScreen` — unchanged

**Deleted:**
- `lib/features/transcript/transcript_review_screen.dart`
- `lib/features/recording/presentation/recording_screen.dart` → `_IdleView`
- `lib/features/recording/presentation/recording_screen.dart` → `_HfMicIndicator`
- `test/features/transcript/transcript_review_screen_test.dart`
- (some routes in) `test/app/router_test.dart` — remove `/record/review` tests

---

## Tasks

| # | Task | Depends on | Layer |
|---|------|------------|-------|
| T1 | Remove review screen: delete `TranscriptReviewScreen` + test, remove `/record/review` from router, inject `StorageService` into `RecordingController`, change `stopAndTranscribe()` to save+enqueue+idle, remove `RecordingCompleted`, update tests | — | domain, presentation, app |
| T2 | Auto-start hands-free: `RecordingScreen` → `ConsumerStatefulWidget`, auto-start via `addPostFrameCallback`, Retry button on error, remove `SwitchListTile`, new bottom section layout, tests | T1 | presentation |
| T3 | Tap-to-record: `HandsFreeEngine.interruptCapture()` + impl in Orchestrator (with WAV cleanup), `suspendForManualRecording()` + `resumeAfterManualRecording()` in `HandsFreeController`, `ref.listen` deadlock guard, `_MicButton` with tap gesture, red icon, gesture guard table, tests | T2 | domain, presentation |
| T4 | Press-and-hold: `onLongPressStart`/`End` in `_MicButton`, orange icon, `_longPressActive` guard, `silentOnEmpty` for empty transcription, tests | T3 | presentation |

### T1 details

- `RecordingController` accepts `StorageService` (injected via `recording_providers.dart`)
- `stopAndTranscribe({bool silentOnEmpty = false})`:
  1. `_service.stop()` → `recordingResult`
  2. `state = RecordingTranscribing`
  3. `_sttService.transcribe(path)` → `result`
  4. If `result.text.isEmpty`: `silentOnEmpty ? emit idle : emit error`
  5. If OK: `storage.getDeviceId()` → `Transcript(...)` → `saveTranscript(transcript)`
  6. Then `enqueue(transcript.id)`:
     - success → `emit RecordingIdle`
     - error → rollback: `deleteTranscript(transcript.id)` → `emit RecordingError`
     (identical contract to `HandsFreeController._processJob` line ~290)
- Remove `RecordingState.completed` and the `RecordingCompleted` class
- Remove the `ref.listen` that navigates to `/record/review` from `RecordingScreen`
- Tests in `recording_controller_test.dart`:
  - Replace `isA<RecordingCompleted>()` assertions with `isA<RecordingIdle>()`
  - Add `storageServiceProvider.overrideWithValue(mockStorage)` to `_makeContainer`
  - Verify: `mockStorage.saveTranscript()` called once after successful transcription
  - Verify: `mockStorage.enqueue()` called with the correct transcriptId
  - Remove or update the `RecordingCompleted` exhaustiveness test to reflect the new sealed class
- Delete `test/features/transcript/transcript_review_screen_test.dart`
- Update `test/app/router_test.dart`: remove `/record/review` navigation tests

### T2 details

- `RecordingScreen extends ConsumerStatefulWidget`
- `initState`: `WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) ref.read(handsFreeControllerProvider.notifier).startSession(); })`
- `ref.listen` in `build()`:
  ```dart
  ref.listen<RecordingState>(recordingControllerProvider, (_, next) {
    if (next is RecordingIdle &&
        ref.read(handsFreeControllerProvider.notifier).isSuspendedForManualRecording) {
      ref.read(handsFreeControllerProvider.notifier).resumeAfterManualRecording();
    }
  });
  ```
  `_suspendedForManualRecording` is private — `HandsFreeController` exposes
  `bool get isSuspendedForManualRecording => _suspendedForManualRecording;` (public getter
  required because `RecordingScreen` is in a separate file — Dart file-private does not
  cross file boundaries).
  Note: `ref.listen` fires on both `RecordingIdle` after a normal stop and after
  `RecordingError` + `resetToIdle()` — the `isSuspendedForManualRecording` guard ensures
  `resumeAfterManualRecording()` is only called when HF is actually suspended.
- On `HandsFreeSessionError`: show error message + `OutlinedButton('Retry', onPressed: startSession)`
- Remove `_IdleView`, `_HfMicIndicator`, `SwitchListTile`
- New `_MicButton` — `GestureDetector` wrapping `AnimatedContainer` (see Solution Design)
- Bottom section layout: `_HfStatusStrip` → `_SegmentList` (when jobs exist) → `_VadParamsStrip`

### T3 details

- `HandsFreeEngine` interface: add `Future<void> interruptCapture()`
- `_IdleHfEngine` (test stub): `interruptCapture()` → no-op async
- `HandsFreeOrchestrator.interruptCapture()`:
  - `_phase = _Phase.idle` first — `_afterWavWrite` checks phase and no-ops
  - `await _audioSub?.cancel()`
  - `await _audioRecorder.stop()` (releases microphone)
  - Current partial WAV is discarded — file cleanup delegated to `_afterWavWrite`:
    when `_phase == idle` and `wavPath != null` → `File(wavPath).deleteSync()` before returning
  - Close `_controller` stream and call `_vadService.dispose()` (like `stop()`, without `await _wavWriteCompleter`)
  - No `await _wavWriteCompleter` — fire-and-forget `_writeWav` no-ops (+ cleanup) in `_afterWavWrite` when phase == idle
- `HandsFreeController.suspendForManualRecording()`:
  - If `HandsFreeCapturing`: `await _engine!.interruptCapture()` (discards current segment)
  - If `HandsFreeListening`/`WithBacklog`: `await _engineSub?.cancel(); await _engine?.stop()`
  - If `HandsFreeStopping`: `await _engineSub?.cancel(); await _engine?.stop()` (blocks ~100-500ms on WAV write)
  - `_engineSub = null; _engine = null; _suspendedForManualRecording = true`
  - Emit new state: `state = _listeningOrBacklog()` (IMPORTANT: state must not remain
    HandsFreeCapturing/Stopping when the engine is already null)
- `HandsFreeController.resumeAfterManualRecording()`:
  - `_suspendedForManualRecording = false`
  - Recreate engine + sub (like `startSession()` but WITHOUT clearing `_jobs`/`_jobCounter` and WITHOUT guards)
  - Emit `_listeningOrBacklog()` — uses the existing predicate (active jobs), not `_jobs.isEmpty`
- `_MicButton.onTap`: gesture guard table (see Solution Design)
- Tests: `HandsFreeController` — verify backlog intact after `suspendForManualRecording()`;
  verify `RecordingIdle` → `resumeAfterManualRecording()` via `ref.listen`

### T4 details

- `GestureDetector.onLongPressStart` in `_MicButton` → if `RecordingIdle` and HF not Stopping: suspend + `startRecording()`
- `GestureDetector.onLongPressEnd` → if `RecordingActive`: `stopAndTranscribe(silentOnEmpty: true)`
- Orange colour: `_isPressAndHold` flag in `RecordingScreen` setState set on `onLongPressStart`;
  cleared on `RecordingIdle` AND on `RecordingError` (in ref.listen) — prevents orange showing
  after `resetToIdle()` when transcription failed
- `_longPressActive` bool: set to `true` in `onLongPressStart`, reset to `false` after
  `onLongPressEnd` action, checked at the top of `onTap` to suppress the trailing tap event
- Guard table: `onLongPressStart` when `RecordingActive` or `RecordingTranscribing` = no-op
- Tests: widget test long press start → orange; release → spinner → green;
  widget test empty transcription → no error shown

---

## Test Impact

### Existing tests affected
- `test/features/recording/presentation/recording_controller_test.dart` — inject `StorageService` mock, replace `RecordingCompleted` assertions with `RecordingIdle` + verify save/enqueue
- `test/features/recording/presentation/recording_screen_test.dart` — remove review navigation tests; add auto-start HF and Retry button tests
- `test/features/recording/presentation/recording_screen_hands_free_test.dart` — remove SwitchListTile tests; update stubs with `interruptCapture()` no-op
- `test/features/recording/presentation/hands_free_controller_test.dart` — add tests for `suspendForManualRecording()`, `resumeAfterManualRecording()`, `isSuspendedForManualRecording` getter, `didChangeAppLifecycleState` guard; update `_IdleHfEngine` stub with `interruptCapture()` no-op
- `test/features/recording/data/hands_free_orchestrator_test.dart` — add tests for `interruptCapture()` + verify file cleanup in `_afterWavWrite` when phase == idle
- `test/app/router_test.dart` — remove `/record/review` route tests
- `test/features/settings/advanced_settings_screen_test.dart` — no change (uses `_pumpAdvanced` with its own router)

### New tests
- `HandsFreeController.suspendForManualRecording()`: active segment cancelled, backlog intact, `_suspendedForManualRecording == true`
- `HandsFreeController.resumeAfterManualRecording()`: engine restarted, `_suspendedForManualRecording == false`, `_jobs` preserved
- `RecordingController.stopAndTranscribe(silentOnEmpty: true)` with empty transcription: emits `RecordingIdle`, no error
- `RecordingScreen` widget: tap → red → tap → spinner → green
- `RecordingScreen` widget: long press → orange → release → spinner → green
- `RecordingScreen` widget: backgrounded during tap-to-record → `RecordingIdle` → `resumeAfterManualRecording()` called
- `RecordingScreen` widget: `HandsFreeSessionError` → Retry button visible → tap Retry → `startSession()` called

---

## Acceptance Criteria

1. Navigating to `/record` automatically starts hands-free mode (green icon) without user interaction.
2. Tapping the icon while hands-free suspends VAD and starts manual recording (red icon). The microphone is guaranteed to be free before recording starts.
3. A second tap stops recording; a spinner appears during transcription; after completion the icon returns to green.
4. Holding the icon while hands-free starts press-and-hold (orange); releasing ends the recording.
5. After press-and-hold: spinner → transcript saved to storage + enqueued → green icon.
6. An empty press-and-hold result returns silently to the green icon with no error message.
7. An active VAD segment (`EngineCapturing`) is interrupted by `interruptCapture()` on tap/press-hold; the backlog is preserved.
8. App backgrounded during manual recording: `cancelRecording()` → `RecordingIdle` → `resumeAfterManualRecording()` called automatically.
9. `HandsFreeSessionError` (e.g. permission denied): Retry button is visible; tapping it restarts the session.
10. The `/record/review` screen does not exist — the app never navigates to it.
11. `flutter test` and `flutter analyze` pass.

---

## Risks

| Risk | Mitigation |
|------|------------|
| `interruptCapture()` does not release the microphone atomically | Platform audio APIs guarantee release after `stop()` — verify on device |
| `VadServiceImpl.init()` after `dispose()` may be unsafe | Verified: `VadIterator.create()` creates a new object each time; re-init is safe |
| `ref.listen` deadlock guard fires on a normal `RecordingIdle` (not after suspend) | Guard checks `_suspendedForManualRecording == true` before calling `resumeAfterManualRecording()` |
| VAD segment backlog grows during press-and-hold | The `_maxJobs` limit (4) already exists in HandsFreeController |

---

## Alternatives Considered

**Unified state machine instead of two controllers:** A single `RecordingModeController`
managing all modes. Rejected — too large an architectural change for the current scope;
the two controllers have different lifecycles and dependencies.

---

## Known Compromises and Follow-Up Direction

### No cancellation during press-and-hold (V1 pragmatism)
Releasing the button always finalises the recording. There is no way to cancel
while holding (e.g. sliding the finger off the icon). Can be added in P017.

### Spinner without audio feedback (V1 pragmatism)
A visual spinner is sufficient for T3/T4; P016 will add audio feedback for transcription.

### `_suspendedForManualRecording` as an internal bool (V1 pragmatism)
Exposed via a getter only for `ref.listen` in RecordingScreen. If more widgets need
this state in the future, promote it into the `HandsFreeSessionState` sealed hierarchy.
