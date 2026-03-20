# Proposal 016 — Audio Feedback During Processing

## Status: Draft

## Prerequisites
- P014 (Recording Mode Overhaul) — `RecordingController.stopAndTranscribe()` must exist (T1/T2)
- P012 (Hands-Free Local VAD) — `HandsFreeController._processJob()` must exist
- P005 (API Sync) — `SyncWorker._drain()` must exist

## Scope
- Tasks: 2
- Layers: core (new service + assets), features/recording, features/api_sync, features/settings
- Risk: Low — additive, does not change business logic

---

## Problem Statement

When the app is processing speech (Groq transcription) or sending to the API, the user
has no audio signal that anything is happening. In hands-free mode the phone may be in
a pocket — without feedback there is no way to know whether the app is working or
whether a segment was captured at all.

---

## Are We Solving the Right Problem?

**Root cause:** The app has no audio feedback layer at all. The visual spinner
only works when the user is looking at the screen.

**Alternatives dismissed:**
- *Vibration:* does not work when the phone is in a pocket or bag; becomes
  annoying with repeated VAD segments.
- *System notifications:* too intrusive for operations lasting less than 2 seconds;
  requires notification permissions.

**Smallest change?** Yes — `AudioFeedbackService` as a thin layer over
`audioplayers`, injected into existing state-transition points. No UI changes
beyond the Settings toggle. No changes to the domain layer.

---

## Goals

- The user hears a subtle signal when the app starts processing
- A looping sound signals that processing is ongoing
- Different signals for success and error outcomes
- Device silent mode is respected (iOS hardware switch, Android DND)
- Toggle in Settings disables all sounds

## Non-goals

- No user-customisable sounds
- No separate sounds for Groq vs API — one set for everything
- No synchronisation with UI animations
- No volume control (uses system media volume)

---

## User-Visible Changes

During transcription or API submission: a subtle looping sound. On completion:
a short success or error jingle. When the device is silenced — silence.
New toggle in Settings → General: **"Audio feedback"**.

---

## Solution Design

### Audio file set

```
assets/audio/
  processing_start.mp3   — short (< 300 ms), played once on processing start
  processing_loop.mp3    — looped during the entire wait (~1–2 s, quiet loop)
  processing_success.mp3 — short (< 500 ms), distinct positive tone
  processing_error.mp3   — short (< 500 ms), distinct negative tone
```

Source: CC0 files (freesound.org or synthetically generated tones).
Sound selection: subtle, non-distracting, unambiguously distinct from each other.

### AudioFeedbackService port

New abstraction in `core/audio/`:

```
abstract class AudioFeedbackService {
  Future<void> startProcessingFeedback()  — sequences start jingle then loop (single-call entry point)
  Future<void> stopLoop()                 — stops the loop
  Future<void> playSuccess()             — stops loop + plays success signal
  Future<void> playError()               — stops loop + plays error signal
  void dispose()
}
```

`startProcessingFeedback()` sequences the start jingle followed by the loop
internally, using a single `AudioPlayer`. This avoids the race condition that
arises when callers do `unawaited(playStart()); unawaited(startLoop())` — with
one player the second `play()` would immediately interrupt the first.

`playSuccess()` and `playError()` always call `stop()` on the player first
**before** checking `getEnabled()`. This ensures the loop is always terminated
even if the user toggled feedback off mid-processing. Only the jingle is
conditionally gated by `getEnabled()`. See guard pattern below.

### AudioplayersAudioFeedbackService implementation

Located at `core/audio/audioplayers_audio_feedback_service.dart`.

Constructor:

```dart
AudioplayersAudioFeedbackService({
  AudioPlayer? player,
  required bool Function() getEnabled,
});
```

- `AudioPlayer` is injectable for unit tests (same pattern as `FlutterTts` in P015).
- `getEnabled` is a live closure — not a stale `bool`. The provider passes
  `() => ref.read(appConfigProvider).audioFeedbackEnabled`.
- **Guard:** `startProcessingFeedback()` starts with `if (!getEnabled()) return;`,
  making it a no-op when the user disables feedback without requiring callers to
  check. `playSuccess()` / `playError()` always stop the player first, then guard
  on `getEnabled()` before playing the jingle. `stopLoop()` and `dispose()` never
  guard — they must always execute.

Processing feedback implementation (start jingle → loop, sequenced inside the service):

A generation counter `_generation` prevents stale start→loop callbacks from firing
after `playSuccess()`, `playError()`, or `stopLoop()` has already ended the cycle:

```dart
int _generation = 0;

Future<void> startProcessingFeedback() async {
  if (!getEnabled()) return;
  final gen = ++_generation;
  await _player.setReleaseMode(ReleaseMode.release);
  await _player.play(AssetSource('audio/processing_start.mp3'));
  // When the start jingle ends, transition to loop — unless a newer cycle started.
  _player.onPlayerComplete.first.then((_) async {
    if (_generation != gen) return; // cancelled by stopLoop/playSuccess/playError
    if (!getEnabled()) return;
    await _player.setReleaseMode(ReleaseMode.loop);
    await _player.play(AssetSource('audio/processing_loop.mp3'));
  });
}

Future<void> stopLoop() async {
  ++_generation; // invalidate any pending start→loop transition
  await _player.stop(); // always stop, even if disabled
}
```

`stopLoop()` does **not** guard on `getEnabled()` — if the loop somehow started
(e.g., toggle changed mid-processing), it must still be stoppable.

Success/error guard pattern — bumps generation, stops first, then conditionally plays jingle:

```dart
Future<void> playSuccess() async {
  ++_generation;         // invalidate any pending start→loop transition
  await _player.stop();  // always stop the loop, regardless of getEnabled()
  if (!getEnabled()) return;
  await _player.setReleaseMode(ReleaseMode.release);
  await _player.play(AssetSource('audio/processing_success.mp3'));
}
```

`playError()` follows the same pattern with `processing_error.mp3`.

`dispose()` also increments `_generation` before calling `_player.dispose()`,
ensuring any pending `onPlayerComplete.first.then(...)` callback sees a stale
generation and exits. The callback implementation must catch and swallow
`StateError` / stream-closed errors in case the player stream closes before
the callback observes the generation mismatch.

`startProcessingFeedback()`, `playSuccess()`, and `playError()` are called
**fire-and-forget** (`unawaited`) at the call sites — they must never block
the processing pipeline.

### Silent mode

**iOS:** `AudioPlayer` configured with `AudioContext`:

```dart
AudioContext(
  iOS: AudioContextIOS(
    category: AVAudioSessionCategory.ambient,
    options: {AVAudioSessionOptions.mixWithOthers},
  ),
)
```

`ambient` category:
- Respects the hardware silent switch — sounds do not play when silenced.
- Mixes with other audio (microphone recording session) — intended to minimize
  AVAudioSession conflicts with `record` or `flutter_tts`; must be verified on
  a physical device (see AC item 9 and Risks table).
- Does not take exclusive audio-session ownership.

**Android:** `AudioContext`:

```dart
AudioContext(
  android: AudioContextAndroid(
    contentType: AndroidContentType.sonification,
    usageType: AndroidUsageType.assistanceSonification,
    audioFocus: AndroidAudioFocus.none,
  ),
)
```

`none` audio focus — the feedback sounds do not interrupt the user's music or
silence a podcast. `assistanceSonification` usage type is respected by Android DND.

### Provider

Located at `core/audio/audio_feedback_provider.dart`:

```dart
final audioFeedbackServiceProvider = Provider<AudioFeedbackService>((ref) {
  final svc = AudioplayersAudioFeedbackService(
    getEnabled: () => ref.read(appConfigProvider).audioFeedbackEnabled,
  );
  ref.onDispose(svc.dispose);
  return svc;
});
```

`ref.onDispose` calls `svc.dispose()` which stops the player and releases the
`audioplayers` platform channel on hot-restart and app teardown.

### AppConfig.audioFeedbackEnabled

New field in `AppConfig`:

```dart
final bool audioFeedbackEnabled; // default: true
```

Persisted under key `'audio_feedback_enabled'` in `SharedPreferences`.
`AppConfigService` gets `saveAudioFeedbackEnabled(bool value)`.
`AppConfigNotifier` gets `updateAudioFeedbackEnabled(bool value)`.

### Settings toggle

New `SwitchListTile` in Settings → General section:

```dart
SwitchListTile(
  key: const Key('audio-feedback-tile'),
  title: const Text('Audio feedback'),
  subtitle: const Text('Play sounds during transcription and sync'),
  value: config.audioFeedbackEnabled,
  onChanged: (v) {
    ref.read(appConfigProvider.notifier).updateAudioFeedbackEnabled(v);
  },
)
```

### Integration points

All calls are `unawaited` — audio feedback never blocks processing.
Groq and API sync share the same method set.

| Moment | Call |
|--------|------|
| `RecordingController`: `state = RecordingTranscribing()` | `unawaited(afs.startProcessingFeedback())` |
| `RecordingController`: enqueue success → `RecordingIdle` | `unawaited(afs.playSuccess())` |
| `RecordingController`: any error path → `RecordingError` | `unawaited(afs.playError())` |
| `RecordingController`: empty transcription (silentOnEmpty) | no feedback (user is not waiting) |
| `HandsFreeController._processJob()`: job enters `Transcribing` | `unawaited(afs.startProcessingFeedback())` |
| `HandsFreeController._processJob()`: `Completed` | `unawaited(afs.playSuccess())` |
| `HandsFreeController._processJob()`: `JobFailed` | `unawaited(afs.playError())` |
| `SyncWorker._drain()`: after `markSending` | `unawaited(afs.startProcessingFeedback())` |
| `SyncWorker._drain()`: `ApiSuccess` | `unawaited(afs.playSuccess())` |
| `SyncWorker._drain()`: `ApiPermanentFailure` / `ApiTransientFailure` | `unawaited(afs.playError())` |

Note: `RecordingController` and `HandsFreeController` read the service via
`_ref.read(audioFeedbackServiceProvider)` at the call site (lazy read — no
constructor change). This avoids adding a constructor parameter to StateNotifiers
that already hold `_ref`; test overrides are placed at the root `ProviderScope`
which `ref.read` reaches correctly. `SyncWorker` receives the service as a
constructor argument (consistent with the TTS pattern introduced in P015 T2).

---

## Affected Mutation Points

### New files

```
lib/core/audio/audio_feedback_service.dart
lib/core/audio/audioplayers_audio_feedback_service.dart
lib/core/audio/audio_feedback_provider.dart
assets/audio/processing_start.mp3
assets/audio/processing_loop.mp3
assets/audio/processing_success.mp3
assets/audio/processing_error.mp3
test/core/audio/audioplayers_audio_feedback_service_test.dart
```

### Modified files

**T1:**
- `pubspec.yaml` — add `audioplayers: ^6.0.0`; add `assets/audio/` section
- `lib/core/config/app_config.dart` — add `audioFeedbackEnabled: bool`
- `lib/core/config/app_config_service.dart` — add `saveAudioFeedbackEnabled()`
- `lib/core/config/app_config_provider.dart` — add `updateAudioFeedbackEnabled()`
- `lib/features/settings/settings_screen.dart` — new `SwitchListTile`
- `test/features/settings/settings_screen_test.dart` — add stub + override
- `test/features/recording/presentation/recording_screen_test.dart` — add stub + override
- `test/features/recording/presentation/recording_screen_hands_free_test.dart` — add stub + override
- `test/features/recording/presentation/recording_screen_mic_button_test.dart` — add stub + override
- `test/features/recording/presentation/hands_free_controller_test.dart` — add stub + override
- `test/features/recording/presentation/recording_controller_test.dart` — add stub + override

**T2:**
- `lib/features/recording/presentation/recording_controller.dart` — add AFS calls
- `lib/features/recording/presentation/hands_free_controller.dart` — add `import` + AFS calls in `_processJob()`
- `lib/features/api_sync/sync_worker.dart` — add constructor param + AFS calls in `_drain()`
- `lib/features/api_sync/sync_provider.dart` — wire `audioFeedbackServiceProvider`
- `test/features/api_sync/sync_worker_test.dart` — add `_StubAudioFeedbackService` + pass to constructor

---

## Tasks

| # | Task | Layer |
|---|------|-------|
| T1 | `AudioFeedbackService` interface (5 methods: `startProcessingFeedback`, `stopLoop`, `playSuccess`, `playError`, `dispose`) + `AudioplayersAudioFeedbackService` impl + provider; download/generate audio files + `assets/audio/`; `AppConfig.audioFeedbackEnabled` + `AppConfigService.saveAudioFeedbackEnabled()` + `AppConfigNotifier.updateAudioFeedbackEnabled()`; Settings toggle; iOS/Android `AudioContext` config; `_StubAudioFeedbackService` added to all 6 affected test files; unit tests for the service | core, features/settings |
| T2 | Integration in `RecordingController.stopAndTranscribe()`, `HandsFreeController._processJob()`, `SyncWorker._drain()` + constructor; update `sync_worker_test.dart`; integration tests | features/recording, features/api_sync |

### T1 details

- `AudioFeedbackService` abstract class — 5 methods as specified in Solution Design (`startProcessingFeedback`, `stopLoop`, `playSuccess`, `playError`, `dispose`)
- `AudioplayersAudioFeedbackService`:
  - Constructor injects `AudioPlayer?` (default: `AudioPlayer()`) and `bool Function() getEnabled`
  - `AudioContext` set on the player at construction time (see Silent mode section)
  - `startProcessingFeedback()` checks `getEnabled()` at entry; `stopLoop()` and `dispose()` do not guard
  - `playSuccess()` and `playError()` always call `stop()` first, then check `getEnabled()` before playing the jingle — ensures loop cleanup even when feedback is toggled off mid-processing
  - `dispose()` increments `_generation` (invalidates any pending start→loop callback), then calls `_player.dispose()`. The `onPlayerComplete.first.then(...)` chain must catch and ignore `StateError` / stream-closed errors that may arise when the player is disposed mid-jingle
- `audioFeedbackServiceProvider`: `Provider<AudioFeedbackService>` with `ref.onDispose`
- `AppConfig.audioFeedbackEnabled` default `true`; persisted under key `'audio_feedback_enabled'`
- `AppConfig.copyWith` — add `bool? audioFeedbackEnabled` parameter
- Settings `SwitchListTile` with `Key('audio-feedback-tile')` in General section, below the TTS toggle
- `_StubAudioFeedbackService` (no-op for all methods) + `audioFeedbackServiceProvider.overrideWithValue(stub)` added to all 6 affected test files preemptively (prevents `audioplayers` platform channel errors in tests after T2 wires it in)
- The stub is added to `settings_screen_test.dart`, `recording_screen_test.dart`, `recording_screen_hands_free_test.dart`, `recording_screen_mic_button_test.dart`, `hands_free_controller_test.dart`, `recording_controller_test.dart`

### T2 details

- `RecordingController.stopAndTranscribe()`:
  - After `state = RecordingTranscribing()` (line 88): `unawaited(_ref.read(audioFeedbackServiceProvider).startProcessingFeedback())`
  - Before `state = RecordingIdle()` (enqueue success, line 122): `unawaited(_ref.read(audioFeedbackServiceProvider).playSuccess())`
  - Before every `state = RecordingError(...)` path: `unawaited(_ref.read(audioFeedbackServiceProvider).playError())`
  - Empty-transcription `silentOnEmpty` path (line 97–99): **no** feedback — user is not waiting for a result
- `HandsFreeController._processJob()`:
  - When `SegmentJob.state` transitions to `Transcribing`: `unawaited(_ref.read(audioFeedbackServiceProvider).startProcessingFeedback())`
  - When transitioning to `Completed`: `unawaited(_ref.read(audioFeedbackServiceProvider).playSuccess())`
  - When transitioning to `JobFailed`: `unawaited(_ref.read(audioFeedbackServiceProvider).playError())`
  - Add `import 'package:voice_agent/core/audio/audio_feedback_provider.dart';`
- `SyncWorker`:
  - Add `required AudioFeedbackService audioFeedbackService` constructor parameter
  - `_drain()`: after `await storageService.markSending(item.id)`: `unawaited(audioFeedbackService.startProcessingFeedback())`
  - `ApiSuccess` case (after `markSent`): `unawaited(audioFeedbackService.playSuccess())`
  - `ApiPermanentFailure` and `ApiTransientFailure` cases (after `markFailed`): `unawaited(audioFeedbackService.playError())`
  - Add import for `audio_feedback_service.dart`
- `sync_provider.dart`: add `audioFeedbackService: ref.watch(audioFeedbackServiceProvider)` to `SyncWorker(...)` constructor call
- `sync_worker_test.dart`: add `_StubAudioFeedbackService` class; pass instance to all `SyncWorker(...)` constructor calls in tests
- No changes to `ApiClient` — unchanged

---

## Test Impact

### Existing tests affected

- `test/features/recording/presentation/recording_screen_test.dart` — add `_StubAudioFeedbackService` + provider override (T1)
- `test/features/recording/presentation/recording_screen_hands_free_test.dart` — same (T1)
- `test/features/recording/presentation/recording_screen_mic_button_test.dart` — same (T1)
- `test/features/recording/presentation/hands_free_controller_test.dart` — add stub + provider override + pass to `makeContainer` (T1); new assertion tests (T2)
- `test/features/recording/presentation/recording_controller_test.dart` — add stub + provider override (T1); new assertion tests (T2)
- `test/features/api_sync/sync_worker_test.dart` — add stub + pass to constructor (T2)
- `test/features/settings/settings_screen_test.dart` — add stub + provider override + new toggle tests (T1)

### New tests (T1)

- Unit: `AudioplayersAudioFeedbackService.startProcessingFeedback()` plays `processing_start.mp3` with `ReleaseMode.release`, then transitions to looping `processing_loop.mp3` on completion
- Unit: `playSuccess()` calls `stop()` before `play()` with `processing_success.mp3`
- Unit: `playError()` calls `stop()` before `play()` with `processing_error.mp3`
- Unit: `startProcessingFeedback()` is a no-op when `getEnabled()` returns `false`
- Unit: `stopLoop()` calls `stop()` even when `getEnabled()` returns `false`
- Unit: loop started while enabled → toggle flips off → `playSuccess()` still stops the player and plays nothing (loop-cleanup-when-disabled edge case)
- Unit: `playSuccess()` called before start jingle completes → generation counter mismatch → loop does NOT start after jingle ends
- Widget: "Audio feedback" toggle is visible and defaults to `true`
- Widget: toggle saves `false` when toggled off

### New tests (T2)

- Unit: `HandsFreeController` — `startProcessingFeedback()` called when job enters `Transcribing`
- Unit: `HandsFreeController` — `playSuccess()` called when job completes
- Unit: `HandsFreeController` — `playError()` called when job fails
- Unit: `RecordingController` — `startProcessingFeedback()` called when `stopAndTranscribe()` begins transcription
- Unit: `RecordingController` — `playSuccess()` called on successful enqueue
- Unit: `RecordingController` — `playError()` called on error
- Unit: `SyncWorker` — `startProcessingFeedback()` called after `markSending`
- Unit: `SyncWorker` — `playSuccess()` called on `ApiSuccess`
- Unit: `SyncWorker` — `playError()` called on `ApiPermanentFailure` and `ApiTransientFailure`

---

## Acceptance Criteria

1. During VAD segment transcription the app plays the start jingle + loop.
2. After successful transcription and enqueue: loop stops, success jingle plays.
3. After transcription error: loop stops, error jingle plays.
4. Empty transcription result (press-and-hold with no speech): no sounds play.
5. During API submission: identical behaviour to transcription (criteria 1–3).
6. When the device is silenced (iOS hardware switch / Android DND): no sound plays. *(manual device verification required)*
7. The "Audio feedback" toggle in Settings disables all sounds.
8. `flutter test` and `flutter analyze` pass.
9. On iOS, feedback sounds play through the speaker (not the earpiece) immediately after recording stops. *(manual device verification required)*

---

## Risks

| Risk | Mitigation |
|------|------------|
| `audioplayers` vs AVAudioSession conflict with microphone or TTS | `ambient` category + `mixWithOthers` option avoids exclusive session ownership; **mandatory manual check on physical iOS device** — verify sounds play through the speaker (not earpiece) immediately after recording stops; see AC item 9 |
| Loop does not stop if the controller is disposed during processing | `dispose()` calls `_player.dispose()` which stops all playback |
| `audioplayers` platform channel unavailable in tests | T1 adds `_StubAudioFeedbackService` + provider overrides to all 6 affected test files before T2 wires anything in |
| First playback latency (~100 ms) from file loading | Acceptable for V1 (subtle feedback); no preloading needed at this scale |
| `audioplayers` API differences between v5 and v6 | Pin to `^6.0.0`; verify `ReleaseMode.loop`, `AssetSource`, `AudioContext` API in the chosen version |

---

## Alternatives Considered

**System sounds (`SystemSound.play` / `AudioServices.playSystemSound` on iOS):**
Simpler, no custom assets. Rejected — limited choice of tones, no loop support,
no control on Android, cannot be silenced per-app.

**`just_audio` instead of `audioplayers`:** Better for longer audio streams;
heavier dependency. `audioplayers` is sufficient for short one-shot and loop files.

---

## Known Compromises and Follow-Up Direction

### No asset preloading (V1)

The first playback of each file may have ~100 ms latency from loading the asset.
Acceptable for MVP. Preload in a future iteration using `AudioPlayer.setSource()`
at app startup if the latency becomes noticeable.

### One set of sounds for all processing (V1)

Groq transcription and API sync share the same audio files. If distinguishing
them becomes a requirement, add new methods to `AudioFeedbackService` and new
files to `assets/audio/` without changing existing callers.

### Single AudioPlayer instance

Using one `AudioPlayer` for all sounds means `playSuccess()` / `playError()`
always interrupt the loop by calling `stop()`. If a future design requires
overlapping sounds (e.g., a jingle that plays over the tail of the loop),
multiple player instances would be needed.

In hands-free mode, a new segment's start sound may interrupt the previous
segment's success sound (the serial STT slot processes jobs quickly). Acceptable
for V1 given the single-player design.

### Sync backlog rapid-fire audio

When multiple sync items are pending, each item plays the full start/loop/success
or error audio cycle. With a large backlog items are drained sequentially and the
user will hear the sequence repeat rapidly. A future improvement could coalesce a
batch into a single audio cycle.
