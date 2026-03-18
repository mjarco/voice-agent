# 010 — iOS Debug Session: Recording, Permissions & Sync

**Type**: Post-mortem / debug log
**Date**: 2026-03-18
**PR**: #69 `fix(ios): fix recording, permissions and sync worker startup`

---

## Context

First run of the app on iOS Simulator (iPhone 17 Pro, iOS 18). Six distinct bugs
surfaced in sequence — each one revealing the next. This document records what
broke, why, and how it was fixed.

---

## Bug 1 — Build failure: `record_linux` incompatible with `record_platform_interface 1.5.0`

**Symptom**: `flutter run -d iPhone` failed with a compile error:

```
record_linux-0.7.2: missing implementation for startStream
record_linux-0.7.2: hasPermission has fewer named arguments than overridden method
```

**Root cause**: `record 5.2.1` depends on `record_linux 0.7.2`. The pub resolver
picked `record_platform_interface 1.5.0` (newest compatible version), which added
`startStream` and a `{bool request}` parameter to `hasPermission`. `record_linux 0.7.2`
implements the old interface and doesn't satisfy the new one.

Flutter compiles all platform implementations during the kernel snapshot step —
even Linux when building for iOS — which is why the error appeared on an iOS build.

**Fix**: Upgraded `record` to `^6.2.0` (which ships `record_linux 1.3.0`).
Later rolled back to `^5.2.0` with `dependency_overrides: record_linux: ^1.3.0`
(see Bug 4).

---

## Bug 2 — Microphone permission: `permanently denied` without a dialog ever appearing

**Symptom**: Tapping the mic button immediately showed the error state
"Microphone permission permanently denied" with no iOS dialog.
Settings → Voice Agent showed only Siri & Search — no Microphone toggle.

**Root cause**: The controller was using `Permission.microphone.request()` from
`permission_handler 11.4.0`. On iOS 17+, Apple replaced `AVAudioSession.recordPermission`
with `AVAudioApplication.recordPermission`. `permission_handler 11.x` uses the old API,
which returns `denied` immediately on newer simulators without ever showing the
system dialog.

Because the dialog never appeared, iOS never registered the app as a microphone
consumer — hence no Microphone toggle in Settings.

**Fix**:
- Upgraded `permission_handler` to `^12.0.1` (supports `AVAudioApplication`).
- Replaced `Permission.microphone.request()` in `RecordingController` with
  `_service.requestPermission()` — a new method on the `RecordingService` interface
  backed by `AudioRecorder.hasPermission()` from the `record` package, which uses
  the platform's own native permission flow.

**Side fix**: Added `requiresSettings: bool` to `RecordingError` and an
"Open Settings" button in `RecordingScreen` for the permanently-denied case.

---

## Bug 3 — `SttException: Model not loaded. Call loadModel() first`

**Symptom**: After granting microphone permission and stopping a recording,
the error "Transcription failed: SttException: Model not loaded" appeared.

**Root cause**: `WhisperSttService.transcribe()` guards against `_whisper == null`
and throws if `loadModel()` was never called. `loadModel()` was never called anywhere
in the production code path — only in tests via the `SttService` interface.

**Fix**: Added a `loadModel()` call in `RecordingController.startRecording()`,
guarded by `isModelLoaded()` to avoid re-initialising on every recording session.

---

## Bug 4 — Recording produces only `[END]` (silent WAV)

**Symptom**: Transcription ran successfully but the result was only `[END]` —
Whisper's output for silent or empty audio. The macOS menubar microphone indicator
never appeared, confirming the simulator was not capturing audio.

**Root cause**: `record 6.x` switched the iOS implementation from `AVAudioRecorder`
to `AVAudioEngine`. `AVAudioEngine` has a known issue on iOS 17/18 simulators where
the input node does not receive audio from the Mac's microphone, silently producing
an all-zeros WAV file.

Various workarounds were attempted (configuring `AVAudioSession` in `AppDelegate.swift`,
upgrading `permission_handler`) — none resolved the simulator mic input.

**Fix**: Downgraded `record` back to `^5.2.0` (which uses `AVAudioRecorder` via
`record_darwin 1.2.2`). Kept `dependency_overrides: record_linux: ^1.3.0` to prevent
the original build failure from returning. The `record 5.x` implementation works
correctly on the simulator.

Note: `record_darwin 1.2.2` already satisfied `record_platform_interface 1.5.0`
(it was only `record_linux 0.7.2` that didn't), so no further changes were needed.

---

## Bug 5 — Sync worker exists but never sends anything

**Symptom**: Connection test in Settings succeeded, logs showed the server was
reachable, but no POST request for the transcript was ever made.

**Root cause**: `syncWorkerProvider` creates a `SyncWorker` but never called
`worker.start()`. The worker object existed in the provider graph but its polling
timer was never started, so `_drain()` was never called.

**Fix**: Moved `worker.start()` into `syncWorkerProvider` itself, immediately after
construction. Also added `ref.watch(syncWorkerProvider)` in `AppShellScaffold.build`
to force eager provider initialization (Riverpod providers are lazy — without a
watcher the provider body never runs).

---

## Bug 6 — Worker doesn't restart after API URL is configured

**Symptom**: Even with Bug 5 fixed (via `initState`), saving the API URL in Settings
didn't cause the worker to start sending. Items queued before the URL was set also
weren't retried.

**Root cause**: `syncWorkerProvider` uses `ref.watch(apiConfigProvider)`. When the
user saves a URL, `apiConfigProvider` changes, which causes `syncWorkerProvider` to
rebuild — stopping the old worker and creating a new one. But `start()` was only
called once in `AppShellScaffold.initState`, not for the newly created worker.

**Fix**: With `start()` in the provider body (Bug 5 fix) and `ref.watch` in the
widget, this became self-correcting: every provider rebuild creates a worker that
immediately calls `start()`. The widget's `ref.watch` ensures the rebuild propagates.

---

## Summary of changes (PR #69)

| File | Change |
|------|--------|
| `pubspec.yaml` | `record ^5.2.0`, `permission_handler ^12.0.1`, `dependency_overrides: record_linux ^1.3.0` |
| `recording_service.dart` | Added `requestPermission()` to interface |
| `recording_service_impl.dart` | Implemented via `AudioRecorder.hasPermission()` |
| `recording_state.dart` | Added `requiresSettings` to `RecordingError` |
| `recording_controller.dart` | Use `requestPermission()`, call `loadModel()`, fix subscription leak on error |
| `recording_screen.dart` | Show "Open Settings" button when `requiresSettings` |
| `sync_provider.dart` | Call `worker.start()` inside provider body |
| `app_shell_scaffold.dart` | `ref.watch(syncWorkerProvider)` to force eager init |
| `app_test.dart`, `recording_screen_test.dart` | Override `connectivityServiceProvider` with no-op to prevent `UnimplementedError` from platform channels in tests |
| `ios/Podfile`, `ios/Podfile.lock` | CocoaPods setup (was missing from repo) |
