# Proposal 002 — Speech-to-Text Engine (On-Device)

## Status: Implemented

## Prerequisites
- Proposal 000 (Project Bootstrap) — directory structure, shared dependencies.
- Proposal 001 (Audio Capture) — provides WAV file output that this proposal consumes.

## Scope
- Tasks: ~4
- Layers: core, features/recording
- Risk: High — native binary integration (whisper.cpp), large model asset, device performance variance

---

## Problem Statement

The app must convert recorded audio into text entirely on-device, with no cloud
dependency. Proposal 001 produces WAV files; this proposal consumes them and outputs
structured transcripts. Without on-device STT, the app cannot fulfil its core value
proposition of offline-first voice capture.

Polish is the primary language; English is secondary. Both must work without a network
connection.

---

## Are We Solving the Right Problem?

**Root cause:** There is no speech-to-text capability in the app. Audio files sit on
disk with no way to extract text from them.

**Alternatives dismissed:**
- *Cloud STT (Google, Azure, OpenAI API):* Violates the offline-first requirement.
  Network dependency makes the app unusable in the field.
- *Vosk (`vosk_flutter`):* Smaller models (~50 MB for Polish) and streaming-capable,
  but lower accuracy than Whisper for Polish. Kept as a future fallback if Whisper
  proves too heavy on low-end devices, but not the primary engine for MVP.
- *`speech_to_text` (platform STT):* Uses OS-level recognition (Siri / Google).
  Requires network on most devices for non-English languages. Does not meet the
  offline-first requirement for Polish.
- *Real-time streaming transcription:* Adds significant complexity (chunked audio,
  partial results, UI for interim text). Post-recording transcription is simpler and
  sufficient for MVP. Streaming can be revisited in a future proposal.

**Smallest change?** Yes — this proposal adds only the STT service and its integration
with the recording flow. Transcript storage is Proposal 004. Transcript editing UI is
Proposal 003.

---

## Goals

- Provide an `SttService` abstraction that transcribes a WAV file to text on-device
- Integrate Whisper (via `whisper_flutter_new`) as the concrete STT engine
- Bundle the Whisper `base` model (~140 MB) in the app for zero-setup offline use
- Support Polish and English language transcription

## Non-goals

- No real-time / streaming transcription — post-recording batch processing only
- No model download UI — the model is bundled; download-on-first-launch is a future
  optimization to reduce initial app size
- No transcript editing or display — that is Proposal 003
- No Vosk integration — noted as future fallback, not implemented now
- No model selection UI — base model is hardcoded for MVP

---

## User-Visible Changes

After this proposal, completing a recording (Proposal 001) automatically triggers
transcription. A progress indicator (indeterminate spinner with "Transcribing...")
appears on the recording screen while Whisper processes the file. When finished, the
app navigates to the transcript review screen (`/record/review` from Proposal 008)
with the `TranscriptResult` as a navigation argument. The recording screen itself
does not display transcript text — that is owned by Proposal 003. The user sees no
model management or language selection — language is auto-detected by Whisper.

---

## Solution Design

### Transcription Data Flow

```
RecordingScreen (stop pressed)
       |
       v
RecordingController.stopAndTranscribe()
       |
       v
SttService.transcribe(filePath)      // runs on isolate via whisper.cpp
       |
       v
TranscriptResult { text, segments, languageCode, audioDurationMs }
       |
       v
RecordingController emits Completed(transcriptResult)
       |
       v
RecordingScreen navigates to /record/review with TranscriptResult as extra
       |
       v
(Proposal 003 owns the review screen)
```

The `Completed` state is transient on the recording screen — the UI reacts to it by
immediately pushing `/record/review` via `context.push('/record/review', extra: result)`.
After navigation, the controller resets to `Idle` so the recording screen is ready for
the next recording when the user returns.

### SttService Contract

```
abstract class SttService {
  Future<TranscriptResult> transcribe(
    String audioFilePath, {
    String? languageCode,        // ISO 639-1, e.g. "pl", "en". Null = auto-detect.
  });

  Future<bool> isModelLoaded();
  Future<void> loadModel();      // call once at app startup or before first transcription
}
```

### TranscriptResult Model

```
class TranscriptResult {
  final String text;                    // full transcript
  final List<TranscriptSegment> segments; // timestamped segments
  final String detectedLanguage;        // ISO 639-1 code
  final int audioDurationMs;            // length of source audio
}

class TranscriptSegment {
  final String text;
  final int startMs;
  final int endMs;
}
```

### WhisperSttService Implementation Notes

- Uses `whisper_flutter_new` which wraps `whisper.cpp` via FFI.
- Whisper runs inference on a background thread managed by the native library; the
  Dart side awaits a `Future`.
- The `base` model (ggml-base.bin, ~140 MB) is bundled as a Flutter asset.
- Model is loaded into memory once at app startup (`loadModel()`). Loading takes
  ~2-3 seconds on a mid-range device.
- Transcription of a 60-second audio clip takes approximately 10-20 seconds on a
  mid-range device with the base model.

### Audio Requirements

Input files must match the format produced by Proposal 001:
- WAV container, PCM 16-bit, 16 kHz, mono.
- If a file does not match (e.g., different sample rate), `transcribe()` throws an
  `SttException` with a descriptive message. Resampling is out of scope for MVP.

### Dependencies (owned by this proposal)

| Package | Version | Purpose |
|---------|---------|---------|
| `whisper_flutter_new` | ^1.3 | On-device Whisper inference via whisper.cpp |

### Asset Configuration

The model file is added as a Flutter asset in `pubspec.yaml`:

```yaml
flutter:
  assets:
    - assets/models/ggml-base.bin
```

The file is ~140 MB. This increases the app bundle size but eliminates the need for a
download step, which simplifies the first-run experience.

### Directory Layout

```
lib/features/recording/
  data/
    record_impl.dart               # (from 001)
    whisper_stt_service.dart        # SttService impl using whisper_flutter_new
  domain/
    recording_service.dart          # (from 001)
    recording_state.dart            # (from 001 — extended with transcription states)
    stt_service.dart                # Abstract SttService interface
    transcript_result.dart          # TranscriptResult and TranscriptSegment models
    stt_exception.dart              # Typed exception for STT failures
  presentation/
    recording_screen.dart           # (from 001 — extended with transcription UI)
    recording_controller.dart       # (from 001 — extended with transcribe step)
    recording_providers.dart        # (from 001 — add SttService provider)

assets/
  models/
    ggml-base.bin                   # Whisper base model (~140 MB)
```

### Extended Recording State

Proposal 001's state machine is extended with a transcription phase:

```
[Idle] --> [Recording] --> [Transcribing(filePath)] --> [Completed(TranscriptResult)]
                |                    |
                +--cancel--> [Idle]  +--error--> [Error(message)]
```

---

## Affected Mutation Points

| File / Area | Change |
|-------------|--------|
| `pubspec.yaml` | Add `whisper_flutter_new` dependency and `assets/models/` asset entry |
| `lib/features/recording/domain/recording_state.dart` | Add `Transcribing` state variant |
| `lib/features/recording/presentation/recording_controller.dart` | Add `stopAndTranscribe()` method that calls `SttService` after stopping recording |
| `lib/features/recording/presentation/recording_screen.dart` | Add spinner for `Transcribing` state; on `Completed`, navigate to `/record/review` and reset to `Idle` |
| `lib/features/recording/presentation/recording_providers.dart` | Add `sttServiceProvider` |
| `assets/models/` | New directory with `ggml-base.bin` |
| `lib/main.dart` or `lib/app/app.dart` | Call `SttService.loadModel()` during app initialization |

---

## Tasks

| # | Task | Layer |
|---|------|-------|
| T1 | Add `whisper_flutter_new` to `pubspec.yaml`. Add `assets/models/` directory and configure the asset entry. Add the `ggml-base.bin` model file. Verify the app still builds on both platforms. Include a build-verification test. | core |
| T2 | Create `SttService` interface, `TranscriptResult` model, `TranscriptSegment` model, and `SttException`. Create `WhisperSttService` implementation. Write unit tests using a mock of `whisper_flutter_new` verifying: successful transcription returns correct `TranscriptResult`, missing model throws `SttException`, invalid audio file throws `SttException`. | features/recording |
| T3 | Integrate `SttService` into the recording flow: extend `RecordingState` with `Transcribing` variant, add `stopAndTranscribe()` to `RecordingController`, add `sttServiceProvider`. Write unit tests for the extended state machine (recording→transcribing→completed, recording→transcribing→error). | features/recording |
| T4 | Update `RecordingScreen` to show a spinner during `Transcribing` state. On `Completed`, navigate to `/record/review` with `TranscriptResult` as `extra` and reset controller to `Idle`. Add `loadModel()` call to app startup. Write widget tests verifying: spinner visible during transcription, navigation triggered on completion (mock GoRouter), error message visible on failure, controller resets to Idle after navigation. | features/recording, app |

---

## Test Impact

### Existing tests affected
- `test/features/recording/presentation/recording_controller_test.dart` — must be
  updated to account for the new `Transcribing` state in the flow.
- `test/features/recording/presentation/recording_screen_test.dart` — must be
  updated to test the spinner state and navigation-on-completion behavior.

### New tests
- `test/features/recording/data/whisper_stt_service_test.dart` — unit tests for
  `WhisperSttService` (mocked whisper FFI): transcription returns result, model not
  loaded throws, invalid file throws.
- `test/features/recording/domain/transcript_result_test.dart` — unit tests for
  model construction, segment ordering, edge cases (empty text, zero duration).

Run with: `flutter test`

---

## Acceptance Criteria

1. `flutter analyze` exits with zero issues.
2. `flutter test` passes with all new and updated STT tests green.
3. `flutter build apk --debug` succeeds with the bundled model asset (APK size
   increases by ~140 MB).
4. `flutter build ios --debug --no-codesign` succeeds with the bundled model asset.
5. (Manual verification) On a physical device, recording a 10-second English phrase
   and stopping triggers transcription and navigates to `/record/review` within 30 seconds.
6. (Manual verification) On a physical device, recording a 10-second Polish phrase
   produces a `TranscriptResult` with `detectedLanguage` value `"pl"` (verifiable via
   the review screen from Proposal 003, or via debug logging).
7. After `Completed` state is emitted, the recording screen navigates to `/record/review`
   and the controller resets to `Idle`.
8. `SttService` is an abstract class; no UI code imports `whisper_flutter_new`
   directly.
9. If `loadModel()` has not been called, `transcribe()` throws `SttException` with
   a message indicating the model is not loaded.
10. `pubspec.yaml` adds exactly `whisper_flutter_new` as a new non-dev dependency
    and lists `assets/models/ggml-base.bin` in the assets section.

---

## Risks

| Risk | Mitigation |
|------|------------|
| Whisper base model (~140 MB) inflates app bundle beyond store limits (Android 150 MB AAB limit) | Android App Bundles use on-demand asset delivery for assets over 150 MB. If needed, move model to an asset pack. iOS limit is 200 MB (4 GB with on-demand resources), so less concern. Monitor APK size in T1. |
| Transcription is too slow on low-end devices (>2x real-time) | Test on a low-end device (e.g., Android Go) in T4. If unacceptable, switch to `tiny` model (~75 MB) with a documented accuracy tradeoff. |
| Polish accuracy is significantly lower than English with the base model | Evaluate with 5 Polish test phrases during T2. If word error rate exceeds 30%, consider the `small` model as an opt-in download in a follow-up proposal. |
| `whisper_flutter_new` FFI crashes or hangs on specific devices | Wrap all FFI calls in try-catch. Add a timeout (default: 120 seconds) to `transcribe()`. If the library is unstable, Vosk is the documented fallback (separate proposal). |
| Model loading at app startup adds 2-3 seconds to launch time | Load model lazily on first transcription request rather than at startup. Show a one-time "Preparing engine..." indicator. Acceptable for MVP. |

---

## Known Compromises and Follow-Up Direction

### Bundled model instead of download-on-first-launch (V1 pragmatism)
Bundling the ~140 MB base model makes the app larger but eliminates first-run download
UX, network dependency for setup, and partial-download error handling. When app size
becomes a concern, move to on-demand asset delivery (Android asset packs, iOS
on-demand resources) and add a download progress UI.

### No model selection
The base model is hardcoded. A future proposal can add a settings screen to choose
between tiny/base/small models, with download management for non-bundled models.

### No Vosk fallback
Vosk is identified as a viable alternative for low-end devices but is not implemented.
If Whisper proves unusable on target hardware, implement `VoskSttService` behind the
same `SttService` interface in a dedicated follow-up proposal.

### Post-recording only
Streaming (real-time) transcription would enable live captions during recording. This
requires chunked audio processing and partial-result UI, which is significantly more
complex. Defer to a future proposal if user feedback indicates demand.

### No language selection UI
Whisper auto-detects language. If auto-detection proves unreliable for Polish, add a
language picker to the recording screen in a follow-up.
