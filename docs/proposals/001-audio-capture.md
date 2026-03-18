# Proposal 001 — Audio Capture

## Status: Draft

## Prerequisites
- Proposal 000 (Project Bootstrap) — directory structure, shared dependencies, buildable app shell.
- Proposal 008 (App Navigation) — provides the `StatefulShellRoute` shell and `/record` branch route that T4 modifies.

## Scope
- Tasks: ~3
- Layers: core, features/recording, app
- Risk: Medium — platform permission handling varies across devices

---

## Problem Statement

The app must record audio from the device microphone so it can later be transcribed
on-device. There is currently no recording capability: no microphone access, no audio
file output, and no UI to start or stop a recording. Without this, the downstream
speech-to-text proposal (002) has no audio input to process.

---

## Are We Solving the Right Problem?

**Root cause:** The app has no way to capture audio from the microphone and persist it
as a file suitable for on-device transcription.

**Alternatives dismissed:**
- *Use `flutter_sound`:* Heavier package with more features than needed (playback,
  codec conversion). The `record` package is lighter, better maintained, and sufficient
  for capture-only use. Playback can be added later if needed.
- *Use platform channels directly:* Unnecessary complexity. The `record` package already
  abstracts iOS (AVAudioRecorder) and Android (MediaRecorder/AudioRecord) behind a
  single API.
- *Stream audio bytes instead of writing to file:* Adds complexity for no MVP benefit.
  Proposal 002 uses post-recording transcription, so a file on disk is the natural
  interface between recording and STT.

**Smallest change?** Yes — this proposal adds only audio capture and the recording
screen. Transcription is handled by Proposal 002. Storage of transcripts is handled
by Proposal 004.

---

## Goals

- Provide a `RecordingService` abstraction that captures microphone audio to a WAV file
- Build a recording screen with start, stop, and cancel controls
- Handle microphone permission request and denial gracefully on both platforms

## Non-goals

- No audio playback — out of scope for capture; add if needed later
- No waveform visualization — cosmetic, can be layered on in a future proposal
- No background recording — recording happens only while the app is in the foreground
- No audio format conversion — output is always WAV/PCM, the format Whisper expects
- No streaming of audio data — file-based handoff to STT is sufficient for MVP

---

## User-Visible Changes

After this proposal, the Record tab (the default/home tab from Proposal 008's shell)
shows a recording screen with a prominent record button. Tapping it requests microphone permission (first time
only), then starts recording. A timer displays elapsed duration. Tapping stop ends the
recording and produces a WAV file on disk. Tapping cancel discards the recording and
returns to idle state.

---

## Solution Design

### Recording State Machine

```
[Idle] --tap record--> [Recording] --tap stop--> [Completed(filePath)]
                            |
                            +--tap cancel--> [Idle]
                            |
                            +--error--> [Error(message)]
                            |
                            +--app backgrounded--> [Idle] (discard partial recording)
```

States are modeled as a sealed class so the UI can exhaustively switch on them.

The `RecordingController` listens to `AppLifecycleState`. On `paused` (app backgrounded),
if currently recording, it calls `cancel()` and transitions to `Idle`. The partial WAV
file is discarded. This is consistent with the non-goal of no background recording.

### RecordingService Contract

```
abstract class RecordingService {
  Future<void> start({required String outputPath});
  Future<RecordingResult> stop();  // returns file path + metadata
  Future<void> cancel();           // discards the current recording
  Stream<Duration> get elapsed;    // broadcast stream, emits ~200ms while recording,
                                   // completes on stop/cancel/error
  bool get isRecording;
}
```

`RecordingResult` is a simple value object:

```
class RecordingResult {
  final String filePath;
  final Duration duration;
  final int sampleRate;     // always 16000 for MVP
}
```

This avoids Proposal 002 needing to re-read WAV headers for metadata.

The default implementation (`RecordingServiceImpl`) delegates to the `record` package.
Tests use a fake that simulates state transitions without touching the microphone.

### Audio Configuration

| Setting | Value | Rationale |
|---------|-------|-----------|
| Sample rate | 16 kHz | Whisper's expected input rate |
| Channels | Mono | Speech is mono; stereo doubles file size for no benefit |
| Encoding | PCM 16-bit | Uncompressed, best compatibility with Whisper |
| Format | WAV | Standard container for PCM, no codec dependency |
| `record` encoder | `AudioEncoder.wav` | Produces a WAV file with proper headers. Do NOT use `AudioEncoder.pcm16bits` — it produces headerless raw PCM that Whisper cannot read. |

The audio configuration (sample rate, channels, encoder) is hardcoded as constants
in `RecordingServiceImpl`. No external configuration needed for MVP — these values are dictated
by Whisper's input requirements (Proposal 002).

Output files are written to the app's temporary directory
(`getTemporaryDirectory()`) with a timestamped filename:
`recording_<epoch_ms>.wav`.

### Permission Handling

1. On first record tap, check `Permission.microphone.status`.
2. If not granted, call `Permission.microphone.request()` with rationale provided
   via platform-native UI (iOS `NSMicrophoneUsageDescription`, Android permission dialog).
3. If permanently denied, show a dialog explaining the requirement and offering a
   button that opens app settings (`openAppSettings()`).
4. Permission state is exposed via a provider so the UI can react declaratively.

Platform manifest entries:
- iOS: `NSMicrophoneUsageDescription` in `Info.plist`
- Android: `<uses-permission android:name="android.permission.RECORD_AUDIO"/>` in
  `AndroidManifest.xml`

### Dependencies (owned by this proposal)

| Package | Version | Purpose |
|---------|---------|---------|
| `record` | ^5.1 (verify latest stable on pub.dev before implementation; update to ^6.0 if current) | Cross-platform audio recording |
| `permission_handler` | ^11.0 | Runtime permission requests |
| `path_provider` | ^2.1 | Access to temporary directory for output files |

### Directory Layout

```
lib/features/recording/
  data/
    recording_service_impl.dart # RecordingService impl using `record` package
  domain/
    recording_service.dart     # Abstract RecordingService interface
    recording_state.dart       # Sealed class: Idle, Recording, Completed, Error
  presentation/
    recording_screen.dart      # UI with record button and timer
    recording_controller.dart  # Riverpod StateNotifier managing RecordingState
    recording_providers.dart   # Provider declarations
```

---

## Affected Mutation Points

| File / Area | Change |
|-------------|--------|
| `pubspec.yaml` | Add `record`, `permission_handler`, `path_provider` |
| `lib/app/router.dart` | Replace the Record branch placeholder screen (from 008) with `RecordingScreen` in the existing `/record` route builder |
| `android/app/src/main/AndroidManifest.xml` | Add `RECORD_AUDIO` permission |
| `ios/Runner/Info.plist` | Add `NSMicrophoneUsageDescription` |
| `lib/features/recording/` | New files (replaces `.gitkeep`) |

---

## Tasks

| # | Task | Layer |
|---|------|-------|
| T1 | Add `record`, `permission_handler`, `path_provider` to `pubspec.yaml`. Add `RECORD_AUDIO` to Android manifest and `NSMicrophoneUsageDescription` to iOS `Info.plist`. Create `RecordingService` interface, `RecordingResult` value object, `RecordingState` sealed class, and `RecordingServiceImpl` with hardcoded audio config (`AudioEncoder.wav`, 16 kHz, mono). Write unit tests for `RecordingServiceImpl` state transitions using a mock of the `record` package's `AudioRecorder`. | core, features/recording |
| T2 | Create `RecordingController` (StateNotifier), providers, permission-check logic, and app lifecycle handling (cancel on background). Write unit tests covering: idle→recording→completed, idle→recording→cancelled, recording→backgrounded→idle, permission denied→error. | features/recording |
| T3 | Build `RecordingScreen` UI with record/stop/cancel button and elapsed-time display. Replace the Record branch placeholder (from 008) with `RecordingScreen` in `router.dart`. Write widget tests verifying button states and navigation. | features/recording, app |

---

## Test Impact

### Existing tests affected
- `test/app/app_test.dart` — may need update if router change affects the smoke test
  (unlikely, since the home screen is unchanged).

### New tests
- `test/features/recording/data/recording_service_impl_test.dart` — unit tests for
  `RecordingServiceImpl` (mocked `AudioRecorder`): start writes to path with correct
  `AudioEncoder.wav` config, stop returns `RecordingResult`, cancel clears state.
- `test/features/recording/presentation/recording_controller_test.dart` — state
  transition tests: idle→recording→completed, idle→recording→cancelled,
  recording→backgrounded→idle, permission denied→error.
- `test/features/recording/presentation/recording_screen_test.dart` — widget tests:
  record button visible in idle, timer visible while recording, stop/cancel buttons
  appear during recording.

Run with: `flutter test`

---

## Acceptance Criteria

1. `flutter analyze` exits with zero issues.
2. `flutter test` passes with all new recording tests green.
3. (Manual verification) Tapping the record button on a physical device starts recording
   (LED/status bar indicator appears on iOS; notification shade shows mic usage on Android 12+).
4. (Manual verification) Stopping a recording produces a `.wav` file in the temporary
   directory with 16 kHz mono PCM content and valid WAV headers.
5. Cancelling a recording deletes any partially written file and returns to idle state.
6. (Manual verification) On first launch, tapping record triggers the OS permission
   dialog. Denying permanently shows a dialog with a link to app settings.
7. If the app goes to background while recording, the recording is cancelled and state
   returns to idle.
8. `stop()` returns a `RecordingResult` containing `filePath`, `duration`, and `sampleRate`.
9. `RecordingService` is an abstract class; no UI code imports the `record` package
   directly. `RecordingServiceImpl` uses `AudioEncoder.wav` (not `pcm16bits`).
10. `pubspec.yaml` adds exactly `record`, `permission_handler`, and `path_provider`
    as new non-dev dependencies.

---

## Risks

| Risk | Mitigation |
|------|------------|
| `record` package does not support 16 kHz PCM on all Android OEMs | Test on at least 2 Android devices (Samsung, Pixel) in T4. If a device cannot record at 16 kHz, this is a blocker — investigate alternative recording configurations or a different audio package. Do NOT fall back to 44.1 kHz, as Proposal 002 requires 16 kHz input and resampling is out of scope for MVP. |
| iOS interrupts recording when a phone call or Siri activates | Handle `AudioSession` interruption by pausing state and showing a user-visible message. Acceptable for MVP to discard the recording on interruption. |
| `permission_handler` version conflicts with other plugins added later | Pin to a major version (`^11.0`) and verify compatibility when future proposals add plugins. |
| Large recordings fill temporary storage | Recordings are written to temp dir and cleaned up after transcription (Proposal 002). For MVP, acceptable; add a cleanup job if needed later. |

---

## Known Compromises and Follow-Up Direction

### No background recording (V1 pragmatism)
Recording stops if the app goes to background. Background audio requires
`AVAudioSession` configuration on iOS and a foreground service on Android — significant
platform-specific work. Can be added when user feedback indicates demand.

### No waveform visualization
The recording screen shows only a timer. Waveform rendering adds visual polish but
requires reading audio amplitude data in real time. Defer to a UI-polish proposal.

### Temp directory only — cleanup owned by Proposal 002
Recordings are stored in the OS temp directory. Proposal 002 is responsible for deleting
the WAV file after successful transcription (it consumes the file and produces a
`TranscriptResult`). If transcription fails, the file remains in temp and may be
retried or cleaned up by the OS. Long-term storage of transcripts (not audio) is
handled by Proposal 004.
