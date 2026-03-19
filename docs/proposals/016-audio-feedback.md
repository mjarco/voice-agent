# Proposal 016 — Audio Feedback During Processing

## Status: Draft

## Prerequisites
- P014 (Recording Mode Overhaul) — integration points in RecordingController
- P012 (HandsFreeOrchestrator) — integration points in HandsFreeController

## Scope
- Tasks: ~2
- Layers: core (new service), features/recording, features/api_sync, features/settings
- Risk: Low — additive, does not change business logic

---

## Problem Statement

When the app is processing speech (Groq transcription) or sending to the API, the user
has no audio signal that anything is happening. In hands-free mode the phone may be in
a pocket — without feedback there is no way to know whether the app is working.

---

## Are We Solving the Right Problem?

**Root cause:** The app has no audio feedback layer at all. The visual spinner
(P014) only works when the user is looking at the screen.

**Alternatives dismissed:**
- *Vibration:* does not work when the phone is in a pocket/bag; annoying with
  repeated VAD segments.
- *System notifications:* too intrusive for operations lasting less than 2 seconds.

**Smallest change?** Yes — `AudioFeedbackService` as a thin layer over
`audioplayers`, injected into existing state transition points.

---

## Goals

- The user hears a subtle signal when the app starts processing
- A looping sound signals that processing is ongoing
- Different signals for success and error
- Device silent mode is respected
- Toggle in settings

## Non-goals

- No user-customisable sounds
- No separate sounds for Groq vs API — one set of sounds for everything
- No synchronisation with UI animations

---

## User-Visible Changes

During transcription or API submission: a subtle looping sound. On completion:
a short success or error jingle. When the device is silenced — silence.
New toggle in Settings → General: "Audio feedback".

---

## Solution Design

### Audio file set

```
assets/audio/
  processing_start.mp3   — short (< 300ms), played once on start
  processing_loop.mp3    — looped for the entire wait (~1-2s, quiet loop)
  processing_success.mp3 — short (< 500ms)
  processing_error.mp3   — short (< 500ms), slightly different tone
```

Source: CC0 files (freesound.org or synthetically generated as tones).
Sound selection: subtle, non-distracting, unambiguously distinct from each other.

### AudioFeedbackService port

New abstraction in `core/`:

```
AudioFeedbackService {
  Future<void> playStart()       — one-shot start signal
  Future<void> startLoop()       — begins the waiting loop
  Future<void> stopLoop()        — stops the loop
  Future<void> playSuccess()     — success signal (stops loop)
  Future<void> playError()       — error signal (stops loop)
  void dispose()
}
```

`playSuccess()` and `playError()` automatically stop the loop before playing
the final signal.

### Silent mode

**iOS:** `AudioPlayer` configured with `AudioContext` set to
`AVAudioSessionCategory.ambient` — sounds do not play when the ringer is
silenced (hardware silent switch). This is the default behaviour for the
ambient category.

**Android:** `AudioContextAndroid` with `contentType: AudioContentType.sonification`
and `usageType: AudioUsageType.assistanceSonification` — respects DND and
notification muting.

### Integration points

Groq and API share the same methods — one set of sounds for everything:

| Moment | Call |
|--------|------|
| Transcription start (HF segment / manual) | `playStart()` + `startLoop()` |
| Transcription OK | loop stopped by `playSuccess()` (P016 T2) |
| Transcription error | loop stopped by `playError()` |
| API send start | `playStart()` + `startLoop()` |
| API success | `playSuccess()` |
| API failure | `playError()` |

---

## Affected Mutation Points

**Needs change:**
- `HandsFreeController._processJob()` — on `Transcribing`: `playStart()` +
  `startLoop()`; on `Completed`: `playSuccess()`; on `JobFailed`: `playError()`
- `HandsFreeController` constructor — inject `AudioFeedbackService`
- `RecordingController.stopAndTranscribe()` (after P014 T1) — on `transcribing`:
  `playStart()` + `startLoop()`; on save OK: `playSuccess()`; on error: `playError()`
- `RecordingController` constructor — inject `AudioFeedbackService`
- `SyncWorker._drain()` — on `markSending`: `playStart()` + `startLoop()`;
  on `ApiSuccess`: `playSuccess()`; on failure: `playError()`
- `SyncWorker` constructor — inject `AudioFeedbackService`
- `AppConfig` — add `audioFeedbackEnabled: bool` (default `true`)
- `AppConfigService.load()` / `saveAudioFeedbackEnabled()` — new
- `AppConfigNotifier.updateAudioFeedbackEnabled()` — new method
- `SettingsScreen` — new `SwitchListTile` in General section
- `pubspec.yaml` — add `audioplayers` dependency + `assets/audio/` section

**No change needed:**
- `HandsFreeOrchestrator` — unchanged
- `ApiClient` — unchanged

---

## Tasks

| # | Task | Layer |
|---|------|-------|
| T1 | `AudioFeedbackService` interface + `AudioplayersAudioFeedbackService` impl + provider; download/generate audio files + `assets/audio/`; `AppConfig.audioFeedbackEnabled` + `AppConfigService` + `AppConfigNotifier`; toggle in Settings; iOS/Android audio session config; tests | core, features/settings |
| T2 | Integration at all points: `HandsFreeController._processJob()`, `RecordingController.stopAndTranscribe()` (P014), `SyncWorker._drain()`; all calls wrapped in `audioFeedbackEnabled` guard; tests | features/recording, features/api_sync |

### T1 details

- `core/audio/audio_feedback_service.dart` — abstraction
- `core/audio/audioplayers_audio_feedback_service.dart` — implementation
- `core/audio/audio_feedback_provider.dart` — `Provider<AudioFeedbackService>`
- `AudioContext` configuration:
  - iOS: `AudioContextIOS(category: AVAudioSessionCategory.ambient)`
  - Android: `AudioContextAndroid(contentType: AudioContentType.sonification, usageType: AudioUsageType.assistanceSonification)`
- `startLoop()` implementation: `setReleaseMode(ReleaseMode.loop)` + `play()`
- `stopLoop()` implementation: `stop()` or `pause()` depending on the audioplayers API
- Guard: `if (!enabled) return;` at the entry of every method (enabled read from provider)

### T2 details

- `audioFeedbackEnabled` guard read via `ref.read(appConfigProvider).audioFeedbackEnabled`
  or via constructor injection in `SyncWorker`
- `HandsFreeController._processJob()`: entering Transcribing → `unawaited(afs.playStart())` +
  `unawaited(afs.startLoop())`; Completed → `unawaited(afs.playSuccess())`; JobFailed → `unawaited(afs.playError())`
- `SyncWorker._drain()`: after `markSending` → `unawaited(afs.playStart())` + `unawaited(afs.startLoop())`;
  ApiSuccess → `unawaited(afs.playSuccess())`; failures → `unawaited(afs.playError())`
- All calls are `unawaited` — feedback does not block the main flow

---

## Test Impact

### Existing tests affected
- `test/features/recording/presentation/hands_free_controller_test.dart` —
  add `AudioFeedbackService` mock to overrides (no-op stub)
- `test/features/api_sync/sync_worker_test.dart` — add mock to constructor
- `test/features/recording/presentation/recording_controller_test.dart` — same

### New tests
- Unit: `AudioplayersAudioFeedbackService.playStart()` plays `processing_start.mp3`
- Unit: `startLoop()` sets `ReleaseMode.loop`
- Unit: `playSuccess()` stops loop before playing success
- Unit: all methods are no-ops when `enabled == false`
- Widget: toggle in Settings saves `audioFeedbackEnabled`
- Integration: `HandsFreeController` with mocked AFS — verify `playStart()` + `startLoop()`
  when a segment transitions to `Transcribing`

---

## Acceptance Criteria

1. During VAD segment transcription the app plays the start jingle + loop.
2. After successful transcription and save: loop stops, success jingle plays.
3. After transcription error: loop stops, error jingle plays.
4. During API submission: identical behaviour to transcription (points 1-3).
5. When the device is silenced (iOS hardware switch / Android DND): no sound plays.
6. The "Audio feedback" toggle in Settings disables all sounds.
7. `flutter test` and `flutter analyze` pass.

---

## Risks

| Risk | Mitigation |
|------|------------|
| audioplayers vs AVAudioSession conflicts with the microphone | Category `ambient` does not take exclusive audio session ownership; test on device |
| Loop does not stop if the controller is disposed during processing | `dispose()` in `AudioFeedbackService` calls `stop()` |
| Delay on loop start (buffering) | Preload assets at app startup |

---

## Alternatives Considered

**System sounds (AudioServices.playSystemSound on iOS):** simpler, no custom assets.
Rejected — limited choice of tones, no loop support, no control on Android.

---

## Known Compromises and Follow-Up Direction

### No asset preloading (V1 pragmatism)
The first playback may have ~100ms latency from loading the file.
Sufficient for MVP — subtle feedback. Preload in a future proposal if noticeable.

### One set of sounds (V1 pragmatism)
Groq and API share the same files. If a need to distinguish them arises in the
future, it is sufficient to add new files and methods to the interface.
