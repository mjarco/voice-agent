# Proposal 012 — Hands-Free Mode with Local VAD

## Status: Draft

## Prerequisites
- Proposal 001 (Audio Capture) — provides microphone capture and WAV output.
- Proposal 003 (Transcript Review) — owns the manual review flow used by the normal recording mode.
- Proposal 004 (Local Storage) — persists transcripts locally.
- Proposal 005 (API Sync) — sends queued transcripts to the user's API.
- Proposal 011 (Groq Cloud STT) — provides the cloud STT implementation used after segment finalization.

## Scope
- Tasks: ~7 (T1, T2a, T2b, T3a, T3b, T4, T5)
- Layers: features/recording, core/config, core/storage
- Risk: High — real-time audio segmentation, noisy-environment behaviour, and a new session model

---

## Problem Statement

The current recording flow is single-shot:

`tap mic -> speak -> tap stop -> transcribe -> review -> save/send`

That flow is workable when the user can operate the phone, but it does not support
hands-free use. In a car or while walking, the user needs the microphone to remain in
standby after they manually enable a mode, detect speech automatically, and create a
separate transcript/request after each spoken segment ends.

The missing capability is not just "auto-stop on silence". The app currently has no
model for:

- continuous listening after manual activation
- deciding when a spoken segment starts and ends in noisy environments
- handling multiple transcripts inside one recording session
- bypassing the review screen without breaking the normal recording flow

Without that contract, any "pause detection" added to the current controller will be
fragile and will fight the existing review-first state machine.

---

## Why This Is The Right Problem

The visible symptom is "I want the mic in standby and transcription after each pause."
The deeper problem is that the recording feature only knows how to produce one result
per user gesture. It has no ownership model for a long-lived speech session that emits
many independent transcript items over time.

This is therefore not primarily a UI problem and not primarily a Groq problem.
Replacing the stop button with a timer or threshold would not solve:

- false starts in noisy environments such as a car
- repeated transitions back to `/record/review`
- ownership of accepted segments once they are created
- backpressure when STT is slower than speech segmentation

The right problem to solve is: introduce a dedicated hands-free session model with
local speech/non-speech detection, bounded segmentation, and a durable path from
accepted segment to transcript storage and sync queue.

---

## Alternative Problem Framings

1. `recording screen lacks a hands-free button`
   - Too shallow. It describes the trigger, not the missing runtime contract.

2. `the app lacks reliable speech segmentation in noisy environments`
   - True, but incomplete. Segmentation alone does not solve the downstream flow.

3. `the recording feature has no owner for a multi-segment speech session`
   - Recommended framing. It captures both the local VAD problem and the fact that
     many transcript items must be created without going through the existing
     one-recording-one-review route.

The proposal uses framing `3`, because it explains why this change touches state
ownership, storage handoff, and UI flow together.

---

## Primary Owner

`features/recording` owns the hands-free session runtime:

- whether hands-free is active
- whether the session is currently listening, capturing speech, cooling down, or
  draining a transcription backlog
- when a segment starts and ends
- which segment jobs are in flight
- what session feedback is shown on screen

`core/storage` remains the owner of persisted transcripts and sync queue items after a
segment has been accepted.

---

## Source of Truth

There are two authoritative truths after this change:

1. While a hands-free session is running, the authoritative runtime state is an
   in-memory `HandsFreeSessionState` owned by the recording feature.
2. Once a segment has been accepted for delivery, the authoritative durable record is
   the existing `Transcript` row plus its sync queue entry.

The `/record/review` route is not authoritative in hands-free mode. It remains the
source of truth only for the normal manual mode.

---

## Goals

- Add a manually enabled `hands-free` mode on the recording screen
- Keep the microphone in listening mode until the user stops the session
- Use local VAD to detect speech start/end instead of raw silence thresholding
- Produce one transcript per spoken segment and enqueue each as a separate API request
- Keep the existing manual recording + review flow unchanged

## Non-goals

- Wake word detection
- Fully offline STT
- Realtime partial transcript streaming while the user is still speaking
- Editing each hands-free segment before it is queued
- Perfect speaker isolation in all high-noise environments
- Background recording when the app is not foregrounded

---

## Risks

| Risk | Mitigation |
|------|------------|
| No VAD package passes all four evaluation criteria (iOS+Android, null-safe, synchronous frames, compatible license) | T2 is blocked; escalate to design. No amplitude fallback in production — feature ships only with a proper VAD implementation. |
| WAV write failure during `HandsFreeStopping` (e.g., low-storage device) | Catch the exception, mark the nascent segment as `Rejected('Write failed: $e')`, transition to `HandsFreeListening` or `HandsFreeWithBacklog`. The segment is silently discarded (visible as `Rejected` in the list). |
| Dart isolate scheduling latency on low-end Android delays VAD classification | Frame processing must not perform any I/O on the audio stream callback path. VAD classify() is synchronous; WAV writes go through a separate `Future`. Enforce this as a code-review constraint in T2. |
| Mutual exclusivity enforced only at UI layer; programmatic or test-driver call can start both recorders simultaneously | `HandsFreeController.startSession()` reads `recordingControllerProvider` via `ref` and emits `SessionError` if state is `RecordingActive`. This provides defence-in-depth beyond the UI disable. |
| `saveTranscript` + `enqueue` non-atomic; double failure leaves orphaned row | Best-effort rollback via `deleteTranscript`. Residual inconsistency documented as V1 known compromise. See Known Compromises. |

---

## Missed Opportunities

- A richer session history model could preserve entire hands-free conversations as a
  first-class object. This proposal intentionally keeps the session ephemeral and uses
  existing `Transcript` rows as the durable outcome.
- A shared audio pipeline could unify manual recording and hands-free recording behind
  one lower-level engine. This proposal keeps hands-free-specific orchestration in a
  separate path to reduce migration risk.
- Wake phrase support could reduce accidental captures in a car. It is intentionally
  deferred because it is a different problem than speech segmentation.
- Server-side or provider-side streaming STT could eventually improve latency, but it
  would add new backend/runtime contracts and is not required to make hands-free
  useful.

---

## Solution Options

### Option 1 — Amplitude threshold + pause timer

Use microphone level only:

- start speech when audio level exceeds a threshold
- end speech after `N` ms below threshold

Pros:
- smallest implementation
- no new native model/runtime dependency

Cons:
- unreliable in a car, on a train, or with HVAC/road noise
- prone to false starts and missed ends
- encourages constant retuning of thresholds

### Option 2 — Local VAD + chunked Groq STT

Run local voice activity detection on short audio frames:

- VAD decides `speech / non-speech`
- segmenter applies pre-roll, hangover, minimum-speech length, and cooldown
- closed segment is uploaded to Groq STT as a normal file transcription request
- accepted result becomes its own transcript + queue item

Pros:
- works materially better than amplitude-only detection in noisy environments
- fits the current Groq file-upload API
- keeps segmentation local and latency acceptable
- preserves the current durable storage and sync contracts

Cons:
- adds a new real-time audio/VAD subsystem
- still requires tuning for noisy environments
- must guard against STT backlog and free-tier request waste

### Option 3 — Provider streaming/realtime STT

Continuously stream audio to an STT provider and let the provider handle endpointing.

Pros:
- potentially simpler client segmentation
- better partial-result UX in the long term

Cons:
- does not match the current Groq STT contract used by the app
- would force a bigger architecture change than the feature requires
- increases network dependence and vendor coupling

---

## Recommendation

Choose **Option 2: Local VAD + chunked Groq STT**.

This is the smallest approach that addresses the real problem. It improves noisy
environment behaviour without requiring a new backend contract, and it keeps normal
recording mode untouched.

The proposal deliberately separates:

- **speech detection** — local, immediate, low-latency
- **speech recognition** — Groq STT after a segment is finalized
- **delivery** — existing transcript storage + sync queue

That separation keeps each concern owned in one place and prevents the hands-free mode
from distorting the normal manual review flow.

---

## User-Visible Changes

The Record screen gains a `Hands-free` control. When enabled manually by the user:

- the screen enters a listening state instead of one-shot recording
- the app shows clear status such as `Listening`, `Capturing speech`,
  `Transcribing 1 segment`, or `Backlog`
- each detected spoken segment appears in a session list as a separate item
- accepted segments are automatically saved and queued as individual transcript/API
  items
- the user stops the session explicitly; the app does not navigate to the review
  screen after each segment

Normal tap-to-record mode continues to use the existing review screen.

---

## Solution Design

### Audio Frame Delivery

The hands-free subsystem uses the `record` package's `startStream()` API, which is
already a dependency (`record: ^5.2.0`). This method returns a `Stream<Uint8List>`
of raw PCM frames without writing any file to disk.

The `HandsFreeOrchestrator` (see below) owns a dedicated `AudioRecorder` instance
separate from the one used by `RecordingServiceImpl`. It calls:

```
stream = await audioRecorder.startStream(
  RecordConfig(
    encoder: AudioEncoder.pcm16bits,
    sampleRate: 16000,
    numChannels: 1,
  ),
);
```

Each `Uint8List` chunk in the stream is a raw PCM-16 LE buffer at 16 kHz mono.
Frame sizes are not guaranteed uniform by the `record` package; the orchestrator
must accept variable-length chunks.

#### Segment file construction

When the VAD transitions from non-speech to speech, the orchestrator opens a
`BytesBuilder` accumulating PCM bytes. Pre-roll bytes (from a ring buffer of
the last `preRollMs` of PCM) are prepended. The ring buffer holds at most
`preRollBytes = (16000 × 1 × 2 × preRollMs) / 1000` bytes (e.g., 9 600 bytes
at the default 300 ms).

When the VAD transitions from speech to non-speech (after hangover), or when
`maxSegmentMs` is exceeded, the orchestrator:

1. Stops accumulating.
2. Initiates an async WAV file write to the temp directory:
   `{tmpDir}/hf_seg_{timestamp}.wav` with a 44-byte PCM WAV header (16-bit,
   16 kHz, mono). The write uses `File.writeAsBytes()` (async, non-blocking).
3. The orchestrator enters `HandsFreeStopping` and holds that state until
   `writeAsBytes` completes. During `HandsFreeStopping`:
   - **VAD classification continues** on all incoming PCM chunks (frames are
     not buffered or dropped — they pass through `VadService.classify()`
     normally).
   - Speech frames that arrive during the write are accumulated in a new
     `BytesBuilder` for the next segment (post-write pre-roll is populated from
     these frames if their duration exceeds `preRollMs`).
   - If VAD signals a new speech start before the write completes, the
     orchestrator notes the start time but does not emit an additional
     `HandsFreeCapturing` state update until `HandsFreeStopping` resolves. This
     prevents race conditions in the state machine — the new segment starts
     accumulating immediately but the session state flip is deferred.
4. After write completes, the orchestrator passes the file path to the job queue
   and transitions to `HandsFreeListening` or `HandsFreeWithBacklog` (or
   `HandsFreeCapturing` if a new speech start was already detected during the
   write).
   If `writeAsBytes` throws, the orchestrator emits `EngineSegmentReady` is
   **not** emitted; instead the nascent segment is marked `Rejected('Write
   failed: $e')` and the orchestrator transitions to `HandsFreeListening` or
   `HandsFreeWithBacklog`. The WAV bytes (in-memory `BytesBuilder`) are discarded.

`HandsFreeOrchestrator` receives its `AudioRecorder` instance via constructor
injection so unit tests can substitute a fake. The `handsFreeEngineProvider`
constructs it with `AudioRecorder()` at runtime.

#### WAV file ownership and cleanup

`GroqSttService.transcribe()` deletes the WAV file in its `finally` block after
each transcription call, regardless of success or failure. This is the
authoritative deletion for all files that reach the `Transcribing` state.

Consequently:
- `HandsFreeController` **does not** delete the WAV file for jobs in
  `Transcribing`, `Persisting`, `Completed`, or `Failed` states — the file is
  already gone by the time the controller observes the outcome.
- For jobs that are `Rejected` before transcription (too short, empty, or queue
  full), the WAV file was never passed to `SttService`. In this case,
  `HandsFreeController` deletes the file directly (best-effort; failure is
  logged, not fatal).
- On session stop, the controller:
  1. Calls `engine.stop()` to release the microphone and VAD resources.
  2. Rejects and deletes WAV files for jobs still in `QueuedForTranscription`
     (not yet handed to `SttService`).
  3. Allows jobs already in `Transcribing` or `Persisting` to complete
     normally. The session state remains `HandsFreeWithBacklog` until all
     in-flight jobs settle, then transitions to `HandsFreeIdle`. The UI must
     not show the controls as fully stopped until the state reaches
     `HandsFreeIdle`.

No WAV file survives after the session ends and all in-flight jobs resolve.

#### Microphone exclusivity contract

The `AudioRecorder` instance inside `HandsFreeOrchestrator` is separate from the
one in `RecordingServiceImpl`. Both use the device microphone. **Only one may be
active at a time.** The `RecordingScreen` enforces mutual exclusivity at the UI
level:

- While a hands-free session is running, the manual record button is disabled.
- While a manual recording is active (`RecordingActive`), the hands-free toggle is
  disabled.

The `HandsFreeController` and `RecordingController` are separate providers.
The screen disables controls as the primary exclusivity mechanism. As defence-
in-depth, `HandsFreeController.startSession()` also reads
`recordingControllerProvider` via `ref` and emits `HandsFreeSessionError` if
the state is `RecordingActive`, preventing programmatic or test-driver misuse.

If the app is backgrounded while hands-free is active, the orchestrator calls
`audioRecorder.stop()` in `didChangeAppLifecycleState(AppLifecycleState.paused)`,
transitions session state to `SessionError('Interrupted: app backgrounded')`, and
releases the microphone. In-flight STT jobs continue until they complete or fail;
no new segments are started. The user must restart the session when returning to
the foreground.

### VadService Interface

```dart
/// Classifies a fixed-size PCM-16 LE frame as speech or non-speech.
///
/// Implementations wrap a native VAD library. The interface is kept synchronous
/// because VAD inference on a 10–30 ms frame must not block the audio stream.
///
/// Lifecycle: call [init] once before [classify], call [dispose] when the
/// session ends to release native resources.
abstract interface class VadService {
  /// Initialise the underlying VAD model/engine.
  ///
  /// Must be called before [classify]. May be called again after [dispose]
  /// to reinitialise. Throws [VadException] if initialisation fails.
  Future<void> init();

  /// Classify a single PCM frame.
  ///
  /// [pcmFrame] must be exactly [frameSize] bytes of 16-bit LE mono PCM at
  /// 16 kHz. Returns [VadLabel.speech] or [VadLabel.nonSpeech].
  ///
  /// Throws [VadException] if called before [init] or after [dispose].
  VadLabel classify(Uint8List pcmFrame);

  /// The number of bytes the native VAD expects per [classify] call.
  ///
  /// Typically 320 bytes (160 samples × 2 bytes = 10 ms at 16 kHz), but
  /// the concrete implementation determines this value.
  ///
  /// The orchestrator must maintain a remainder buffer and emit only complete
  /// frames to [classify]. Any bytes left over after extracting whole frames
  /// are held in the remainder buffer until the next chunk arrives. Partial
  /// frames must **never** be zero-padded — padding distorts PCM signal and
  /// produces incorrect VAD labels.
  int get frameSize;

  /// Release native resources. After [dispose], [classify] must not be called.
  void dispose();
}

enum VadLabel { speech, nonSpeech }

class VadException implements Exception {
  final String message;
  const VadException(this.message);
  @override String toString() => 'VadException: $message';
}
```

#### VAD package candidates

The implementation must choose one native VAD package. Evaluation must verify:

1. iOS and Android support in the current Flutter/Dart toolchain.
2. Pub.dev publication and null-safety compatibility.
3. Ability to classify 10–30 ms frames synchronously or via isolate without
   UI-thread blocking.
4. License compatibility (MIT, Apache 2.0, or BSD preferred; GPL is disqualifying).

Packages to evaluate at implementation time (in preference order):

| Package | Notes |
|---------|-------|
| `vad` (pub.dev) | Dart-native WebRTC VAD port; no native plugin required |
| `voice_activity_detector` (pub.dev) | Flutter plugin wrapping libfvad |
| `silero_vad_flutter` (pub.dev) | ONNX-based; heavier but higher quality |

If none pass criteria 1–4, the implementation is blocked. The T2 PR must not
merge with an amplitude-only fallback in production: AC3 requires VAD-based
segmentation. `AmplitudeVadService implements VadService` is permitted as a
**test-only stub** (for unit tests that need a controllable `VadService`), but it
must not be the production `VadService` registered in the provider. If no package
qualifies, T2 is escalated back to design as a blocker.

### Runtime Model

#### HandsFreeSessionState transitions

```
                          user taps Start
                               │
                         [Idle] ─────────────────────────────────────────────┐
                               │                                              │
               permission+key OK│                                             │
                               ▼                                              │
                          [Listening] ────────────────────────────────────────┤
                         ▲     │                                              │
                         │     │ VAD: speech frames ≥ minSpeechMs             │ unrecoverable
                cooldown │     ▼                                              │ error (any state)
                    [CapturingSpeech] ───────────────────────────────────────►│
                               │                                              │
                    maxSegmentMs│ or hangover complete                         ▼
                               ▼                                       [SessionError]
                   [HandsFreeStopping]
                               │
          WAV write done/failed │
                               ▼
               [Listening] or [WithBacklog]  ← diagram shorthand for
                         ▲           │        HandsFreeListening / HandsFreeWithBacklog
         backlog drains  └───────────┘   user taps Stop
                                         │
                                         ▼
                                    [Idle] (after all in-flight jobs settle)
```

`SessionError` is reachable from any state on: permission denied at start,
VAD init failure, `audioRecorder.startStream()` exception, or app backgrounding
while the session is active.

**Cooldown visibility:** Cooldown (post-VAD-triggered segment end) is internal
orchestrator state. `HandsFreeSessionState` stays at `Listening` during cooldown.
No cooldown indicator is shown in the UI; the status strip simply shows
`Listening`.

#### HandsFreeSessionState data model

`HandsFreeSessionState` is a sealed class. The `Listening` and
`ListeningWithBacklog` variants carry a `List<SegmentJob>` field representing
all jobs in the current session (any state). This list is what the segment list
widget renders. Each `SegmentJob` contains its `SegmentJobState` and a short
display label (timestamp or index).

```
sealed class HandsFreeSessionState { ... }
class HandsFreeIdle          extends HandsFreeSessionState { }  // no jobs — session not running
class HandsFreeListening      extends HandsFreeSessionState { final List<SegmentJob> jobs; }
class HandsFreeCapturing      extends HandsFreeSessionState { final List<SegmentJob> jobs; }
class HandsFreeStopping       extends HandsFreeSessionState { final List<SegmentJob> jobs; }
class HandsFreeWithBacklog    extends HandsFreeSessionState { final List<SegmentJob> jobs; }
class HandsFreeSessionError   extends HandsFreeSessionState {
  final String message;
  final bool requiresSettings;      // true → OS settings (mic permission)
  final bool requiresAppSettings;   // true → in-app /settings (API key)
  // At most one flag may be true. Assert: !(requiresSettings && requiresAppSettings)
  final List<SegmentJob> jobs;   // jobs at time of error, for display
}
```

State descriptions:

| State | Microphone | Description |
|-------|-----------|-------------|
| `HandsFreeIdle` | Off | Session not running. |
| `HandsFreeListening` | On (stream) | VAD running; no speech; no job backlog. Cooldown (if active) is invisible. |
| `HandsFreeCapturing` | On (stream) | Speech frames accumulating in segment buffer. Carries full job list. |
| `HandsFreeStopping` | On (stream) | Hangover or maxSegmentMs; WAV being written asynchronously. Carries full job list. |
| `HandsFreeWithBacklog` | On (stream) | Listening; ≥1 STT job is pending/in-flight. |
| `HandsFreeSessionError` | Off | Unrecoverable error (permission denied, VAD crash, backgrounded). |

#### Segment job state transitions

```
[QueuedForTranscription] → [Transcribing] → [Persisting] → [Completed(transcriptId)]
         │                       │                │
         │                       ▼                ▼
         └──────────────► [Rejected(reason)]   [Failed(message)]
```

Job state descriptions:

| State | Description |
|-------|-------------|
| `QueuedForTranscription` | WAV file ready; waiting for the STT slot. |
| `Transcribing` | Active Groq STT request in-flight. |
| `Persisting` | STT result received; writing Transcript + enqueue. |
| `Completed(transcriptId)` | Transcript saved; WAV deleted. |
| `Rejected(reason)` | Segment too short, empty text, or queue full. WAV deleted. |
| `Failed(message)` | STT or storage error. WAV deleted after display. |

### Segmentation Heuristics

Required heuristics:

- `preRollMs` (default 300 ms): ring buffer of PCM bytes prepended to segment.
  Buffer size in bytes: `(sampleRate × numChannels × bytesPerSample × preRollMs) / 1000`
  = `(16000 × 1 × 2 × 300) / 1000` = **9 600 bytes**.
- `hangoverMs` (default 400 ms): non-speech frames required to close segment.
- `minSpeechMs` (default 500 ms): minimum accumulated speech to accept segment.
- `maxSegmentMs` (default 30 000 ms): force-closes segment if speech continues
  beyond this limit. When force-closed, the orchestrator enters `HandsFreeStopping`,
  writes the WAV, and transitions to `HandsFreeListening` or `HandsFreeWithBacklog`.
  No cooldown is applied on force-close because the user is still speaking.
- `cooldownMs` (default 1 000 ms): after a VAD-triggered segment end (not a
  force-close), the orchestrator suppresses new segment starts for this duration.
  During cooldown, the session state remains `HandsFreeListening` (or
  `HandsFreeWithBacklog` if jobs are in flight) — cooldown is not a distinct
  visible state. Once cooldown expires, the session returns to normal speech
  detection.

All defaults are internal constants in the orchestrator class. They are not
exposed to `core/config` in V1. Tuning is done by editing source code.

### Session Start Guard

`HandsFreeController.startSession()` performs two checks before activating the
microphone, in this order:

**1. Microphone permission check** — via the `HandsFreeEngine` domain port so no
`data/` type leaks into the controller:

```
final granted = await engine.hasPermission();
if (!granted) {
  state = HandsFreeSessionError(
    message: 'Microphone permission denied.',
    requiresSettings: true,
    jobs: const [],  // guard runs from HandsFreeIdle; no jobs yet
  );
  return;
}
```

**2. Groq API key check:**

```
await ref.read(appConfigProvider.notifier).loadCompleted;
final config = ref.read(appConfigProvider);
if (config.groqApiKey == null || config.groqApiKey!.isEmpty) {
  state = HandsFreeSessionError(
    message: 'Groq API key not set.',
    requiresAppSettings: true,   // → context.go('/settings')
    jobs: const [],  // guard runs from HandsFreeIdle; no jobs yet
  );
  return;
}
```

`HandsFreeSessionError` carries two separate flags mirroring the existing
`RecordingError` pattern:
- `requiresSettings: true` — permission denied → UI shows "Open Settings"
  (`openAppSettings()` to OS settings)
- `requiresAppSettings: true` — missing API key → UI shows "Go to Settings"
  (`context.go('/settings')` in-app)

At most one flag may be true; assert `!(requiresSettings && requiresAppSettings)`
enforced in the constructor. `EngineError.requiresSettings` covers only
permission-denied events from the engine. API-key errors are emitted directly by
the controller before `engine.start()` is called.

### Hands-free and STT Backlog

Hands-free must not block on the current segment being transcribed. A segment
finalized by VAD becomes a transcription job. The session immediately returns to
listening while the job is processed in the background.

Backpressure rules:

- Allow only **one** active Groq STT request at a time. Enforced via a single
  `Future?` field in the controller: when non-null, the STT slot is occupied.
  The next `QueuedForTranscription` job starts only when the slot becomes null.
- Allow a maximum of **3** pending segments in the queue (not counting the
  in-flight job). Total inflight+queued cap: **4**.
- If the queue limit is reached when a new segment arrives, reject the new
  segment immediately with `Rejected('Queue full')` and surface it in the session
  list. The orchestrator returns to `Listening` after the configured cooldown.
  Silent dropping is not permitted.

### Groq Request Shaping

The current Groq STT flow remains file-based. Each accepted segment becomes one
normal `transcribe()` call via `SttService`.

To avoid waste on free-tier limits:

- Reject segments shorter than `minSpeechMs`.
- Reject transcripts whose normalised text is empty (`.trim().isEmpty`).
- Keep segment duration bounded by `maxSegmentMs`.

### STT Error Classification

`HandsFreeController` handles `SttService.transcribe()` errors as follows (V1):

- `SttException` — use `e.message` verbatim as the job `Failed` message. This
  covers Groq-specific errors (invalid key, rate limit, service unavailable)
  already mapped by `GroqSttService._mapDioException`.
- Any other exception — wrap as `Failed('Transcription failed: $e')`.

In V1, all failures simply show the message in the segment list and allow the
session to continue. No retry is attempted.

### Durable Handoff

Hands-free mode bypasses `/record/review`. After successful transcription:

1. Call `storageService.getDeviceId()` to obtain the device identifier. On
   error → `Failed('Storage error: $e')`.
2. Generate a UUID for the transcript ID (using the `uuid` package, matching
   the pattern in `TranscriptReviewScreen`).
3. Build a `Transcript` using the STT result, device ID, UUID, and current
   timestamp.
4. Call `StorageService.saveTranscript(transcript)`. On error → `Failed`.
5. Call `StorageService.enqueue(transcript.id)`.
   - On success → mark job `Completed(transcript.id)`.
   - On error → attempt best-effort rollback:
     `StorageService.deleteTranscript(transcript.id)` (swallow rollback error),
     then mark job `Failed('Enqueue failed: $e')`.
   - Rationale: `saveTranscript` and `enqueue` are separate operations with no
     database-level transaction. If `enqueue` fails, an orphaned `Transcript`
     row would be visible in history with no sync status. Rolling back the row
     keeps the storage state consistent in the common case.
   - Known residual: if `enqueue` fails **and** `deleteTranscript` also fails,
     an orphaned `Transcript` row remains. This is documented as a V1 known
     compromise (see Known Compromises section). A transactional `saveAndEnqueue`
     StorageService method would close this gap but is deferred.
6. The WAV file has already been deleted by `SttService.transcribe()` — no
   further cleanup is required by the controller for this success path.

### Manual Mode Unchanged

The existing manual flow continues to use:

`record -> stop -> transcribe -> review -> approve/discard`

Hands-free is a parallel mode, not a replacement. The two modes share the
`SttService` interface but not the same controller or audio recorder instance.

### HandsFreeEngine Domain Port

`HandsFreeController` (in `presentation/`) must not depend directly on
`HandsFreeOrchestrator` (in `data/`). Following the project architecture rule —
controllers depend on domain interfaces, not data implementations — a domain
port is required:

```dart
/// Phase events emitted by [HandsFreeEngine] in real time.
sealed class HandsFreeEngineEvent {}
class EngineListening    extends HandsFreeEngineEvent {}
class EngineCapturing    extends HandsFreeEngineEvent {}
class EngineStopping     extends HandsFreeEngineEvent {}
class EngineSegmentReady extends HandsFreeEngineEvent { final String wavPath; ... }
class EngineError        extends HandsFreeEngineEvent {
  final String message;
  final bool requiresSettings;  // true for mic permission-denied only.
  // API-key errors are NOT emitted via EngineError — they are caught
  // in HandsFreeController.startSession() before engine.start() is called.
}

/// Domain-layer port for the hands-free audio pipeline.
///
/// The implementation ([HandsFreeOrchestrator]) lives in data/.
/// The controller in presentation/ depends only on this interface.
abstract interface class HandsFreeEngine {
  /// Check whether the app has microphone permission.
  Future<bool> hasPermission();

  /// Start the audio stream and VAD pipeline.
  ///
  /// Returns a stream of [HandsFreeEngineEvent]s that the controller maps
  /// to [HandsFreeSessionState] updates. The stream is closed when [stop]
  /// completes.
  Stream<HandsFreeEngineEvent> start();

  /// Stop the audio stream, release VAD resources, and flush the pre-roll
  /// buffer. Ongoing WAV writes are awaited before the stream closes.
  ///
  /// Safe to call before [start] returns (e.g., if a permission prompt is
  /// in progress). Idempotent — calling [stop] on an already-stopped engine
  /// is a no-op.
  Future<void> stop();

  /// Release all resources. Must be called when the owning controller is
  /// disposed. Safe to call after [stop].
  void dispose();
}
```

The controller maps engine events to session state:
- `EngineListening` → `HandsFreeListening(jobs)`
- `EngineCapturing` → `HandsFreeCapturing(jobs)`
- `EngineStopping` → `HandsFreeStopping(jobs)`
- `EngineSegmentReady(wavPath)` → enqueue job, update jobs list
- `EngineError(message, requiresSettings)` → `HandsFreeSessionError`

The session-start guard calls `engine.hasPermission()` before `engine.start()`.
No direct dependency on `AudioRecorder` or any `data/` type is needed in the
controller.

`HandsFreeOrchestrator implements HandsFreeEngine` and lives in
`features/recording/data/`. The controller receives it via a Riverpod
provider:

```dart
final handsFreeEngineProvider = Provider<HandsFreeEngine>((ref) {
  return HandsFreeOrchestrator(
    AudioRecorder(),                    // injected for testability
    ref.watch(vadServiceProvider),
  );
});
```

### Provider Naming

The new Riverpod provider is declared as:

```dart
final handsFreeControllerProvider =
    StateNotifierProvider<HandsFreeController, HandsFreeSessionState>((ref) {
  return HandsFreeController(ref);
});
```

`HandsFreeController` takes `Ref` directly rather than injecting individual
services. This mirrors the `RecordingController` pattern (`RecordingController`
takes `Ref` as its third parameter for lazy config access). The justification is
the same: the controller needs late access to `storageServiceProvider` and
`appConfigProvider.notifier.loadCompleted` during async job processing (segment
persist), not just at construction time. Injecting a captured `Ref` is the
established pattern in this codebase for controllers with async lifecycle
dependencies.

---

## Affected Mutation Points

| File / Area | Change |
|-------------|--------|
| `lib/features/recording/domain/` | Add `HandsFreeSessionState`, `SegmentJobState`, `SegmentJob`, `VadService` interface, `VadLabel`, `VadException`, `HandsFreeEngine` domain port |
| `lib/features/recording/data/` | Add `HandsFreeOrchestrator implements HandsFreeEngine` (frame delivery + segment writing) and concrete `VadService` adapter |
| `lib/features/recording/presentation/hands_free_controller.dart` | New controller: owns session state, depends on `HandsFreeEngine` domain port, submits jobs to SttService, persists via StorageService |
| `lib/features/recording/presentation/recording_providers.dart` | Add `handsFreeControllerProvider`, `handsFreeEngineProvider` |
| `lib/features/recording/presentation/recording_screen.dart` | Add hands-free toggle, session status strip, segment list; enforce mutual exclusivity with manual recording |
| `lib/core/storage/` | Reuse `saveTranscript` and `enqueue`; no schema change required for V1 |
| `lib/core/config/` | No change; tuning constants remain internal to orchestrator |
| `pubspec.yaml` | Add chosen VAD package dependency in T2 |
| `test/features/recording/` | New unit and widget tests (see Test Impact) |

---

## Test Impact

### Existing tests affected

- `test/features/recording/presentation/recording_screen_test.dart`
  - Add coverage for hands-free toggle enabled/disabled states and session status.
- `test/features/recording/presentation/recording_controller_test.dart`
  - Keep existing manual-mode tests intact; no hands-free state added here.

### New tests

- `test/features/recording/domain/hands_free_session_state_test.dart`
  - Session and segment-job state transition coverage.
- `test/features/recording/presentation/hands_free_controller_test.dart`
  - `listening → capturingSpeech → queued → transcribing → persisted`
  - Cooldown suppresses immediate retrigger.
  - `minSpeechMs` filter rejects short bursts.
  - Queue saturation emits `Rejected('Queue full')`.
  - Missing Groq key emits `SessionError` before mic starts.
  - Background transition emits `SessionError('Interrupted: app backgrounded')`.
  - `saveTranscript()` succeeds but `enqueue()` fails: job is `Failed`, rollback
    deletes the transcript row, no orphaned row remains.
- `test/features/recording/data/vad_service_test.dart`
  - Adapter contract with mocked native VAD frames.
- `test/features/recording/data/hands_free_orchestrator_test.dart`
  - Remainder-buffered framing: partial chunk held until full frame available;
    no padding of partial frames.
  - Speech start detected during `HandsFreeStopping` (write in progress):
    new segment accumulates immediately; correct state event sequence emitted
    after write completes.
- `test/features/recording/presentation/recording_screen_hands_free_test.dart`
  - Manual toggle starts/stops session.
  - Segment list updates as jobs complete.
  - Error state renders correctly.
  - Mutual exclusivity: manual record button disabled during hands-free session.
- `test/features/recording/presentation/hands_free_persist_flow_test.dart`
  - Successful segment creates exactly one `Transcript` row and one sync queue item.
  - Failed STT does not create a Transcript.

Run with:

```bash
flutter test
```

---

## Acceptance Criteria

1. The Record screen offers a manually enabled `hands-free` mode alongside the existing
   manual recording flow.
2. Starting hands-free keeps the session in a listening state until the user stops it
   or an unrecoverable error occurs.
3. The app detects speech boundaries using local VAD-based segmentation, not a raw
   amplitude threshold alone.
4. In hands-free mode, each accepted spoken segment results in a separate
   `Transcript` record and a separate queue item.
5. The app does not navigate to `/record/review` for hands-free segments.
6. A short noise burst below the configured minimum speech duration is rejected and
   appears as a `Rejected` entry in the session segment list.
7. If Groq STT is slower than segmentation, the app surfaces `ListeningWithBacklog`
   state instead of silently losing work.
8. Stopping hands-free cleanly releases microphone/VAD resources, deletes any
   un-transcribed temp WAV files, and stops creating new jobs.
9. The existing manual record/stop/review flow still behaves exactly as before.
10. Starting hands-free without a configured Groq API key immediately shows
    `SessionError('Groq API key not set.')` and does not activate the microphone.
11. Backgrounding the app while hands-free is active transitions to
    `SessionError('Interrupted: app backgrounded')` and releases the microphone.
12. `flutter analyze` exits with zero issues and `flutter test` passes.

---

## Why This Proposal Might Be Solving The Wrong Problem

- The user's main pain may be interaction friction, not speech segmentation. If so, a
  push-to-talk hybrid could deliver more value with much less complexity.
- The biggest real-world problem may be microphone placement and cabin acoustics, not
  the absence of local VAD. In that case, software-only gains will be bounded.
- The session-list UI may still be too distracting if the true goal is a voice
  assistant interaction rather than transcript capture.
- If Groq file transcription latency or free-tier economics become the dominant limit,
  local VAD will help segmentation but not overall product fit.
- The app may eventually need a first-class `ConversationSession` model. Reusing
  individual `Transcript` rows might prove too narrow once session analytics, replay,
  or grouped resend become important.

---

## Tasks

| # | Task | Layer |
|---|------|-------|
| T1 | Add hands-free domain types: `HandsFreeSessionState` sealed class (all variants with `List<SegmentJob>` payload), `SegmentJobState` sealed class, `SegmentJob` model, `VadService` abstract interface, `VadLabel` enum, `VadException`, `HandsFreeEngine` domain port interface, and `HandsFreeEngineEvent` sealed class (`EngineListening`, `EngineCapturing`, `EngineStopping`, `EngineSegmentReady`, `EngineError`). Unit tests: sealed class exhaustiveness, state model. Independently mergeable — adds types only. | features/recording |
| T2a | VAD package evaluation spike: attempt to add the `vad` package to `pubspec.yaml`; verify it compiles on iOS and Android, provides synchronous frame classification, and has a compatible license. If `vad` passes, proceed to T2b. If it fails, evaluate `voice_activity_detector`, then `silero_vad_flutter`. If none pass, T2a blocks T2b and must be escalated. Deliver: a concrete `VadService` adapter (`VadServiceImpl`) with unit tests using mocked frames, and `pubspec.yaml` updated. | features/recording |
| T2b | Implement `HandsFreeOrchestrator implements HandsFreeEngine`: `AudioRecorder` injected via constructor for testability; `startStream()` frame delivery; remainder-buffered PCM framing (no padding); pre-roll ring buffer; VAD classification continues during `HandsFreeStopping`; hangover accumulator; `minSpeechMs` gate; `maxSegmentMs` force-close; async WAV write with `Rejected` on write failure; `cooldownMs` suppression; deferred next-segment start during write. Add `handsFreeEngineProvider`. Unit tests: mocked `AudioRecorder`, mocked `VadService`, remainder buffering, speech start during stopping, WAV write failure. | features/recording |
| T3a | Add `HandsFreeController` session lifecycle (StateNotifier): session-start guard (`engine.hasPermission()` → Groq key check → active manual recording check via `recordingControllerProvider`); `HandsFreeEngineEvent` stream mapping to `HandsFreeSessionState`; background lifecycle via `WidgetsBindingObserver`; session stop with in-flight job drain (session emits `HandsFreeIdle` only after all jobs leave `Transcribing`/`Persisting`). Add `handsFreeControllerProvider`. Unit tests: permission guard, API key guard, active-recording guard, background interruption, drain-then-idle. Depends on T2b. | features/recording |
| T3b | Extend `HandsFreeController` with job processing: STT serial slot (`Future?` field); bounded job queue (max 4 total); `getDeviceId()` + UUID generation during persist; `StorageService.saveTranscript` + `enqueue` with best-effort rollback; WAV cleanup for pre-transcription rejections and session stop. Unit tests: queue saturation, success path (one Transcript + one queue item), STT failure, `saveTranscript` success + `enqueue` failure → rollback + `Failed`. | features/recording, core/storage |
| T4 | Update `RecordingScreen`: hands-free toggle (disabled when `RecordingActive`), manual record button (disabled when hands-free session active), session status strip, segment list. Widget tests: toggle starts/stops session, segment list renders job states, `SessionError` renders with `requiresSettings`/`requiresAppSettings`/no-flag variants, mutual exclusivity. Integration test `test/features/recording/presentation/hands_free_persist_flow_test.dart`: successful segment creates exactly one `Transcript` row and one sync queue item; failed STT creates no Transcript. | features/recording |
| T5 | Verify end-to-end behaviour on a physical device in a noisy environment. AC coverage: AC1, AC3, AC4, AC6, AC7, AC8, AC11. Pass criteria: (a) three consecutive spoken segments each produce a separate Transcript row in the history screen [AC4]; (b) a noise burst under 500 ms appears as Rejected [AC6]; (c) backgrounding transitions to SessionError within 2 seconds [AC11]; (d) stopping leaves zero WAV temp files in app temp directory [AC8]. Document any heuristic constants changed from defaults as inline comments. | features/recording |

---

## Known Compromises and Follow-Up Direction

### Tuning constants are not user-configurable (V1 pragmatism)

`preRollMs`, `hangoverMs`, `minSpeechMs`, `maxSegmentMs`, and `cooldownMs` are
internal constants in `HandsFreeOrchestrator`. They will need tuning across device
types and environments. If user feedback reveals that the defaults are frequently
wrong, a follow-up proposal should add persisted config via `core/config`.

### Separate AudioRecorder instances create no shared pool

The hands-free subsystem allocates its own `AudioRecorder` and the manual recording
path allocates another. On most devices these share the same physical microphone, so
mutual exclusivity is enforced at the UI layer only. A lower-level engine shared
between both paths could enforce exclusivity in code, but building it now would add
migration risk without proportionate benefit. Track as a future `AudioEngine` abstraction.

### VAD package is not locked at design time

The proposal names candidates but defers final selection to T2 implementation.
If the selected package has correctness issues in noisy-environment testing (T4),
swapping implementations is low-risk because `VadService` is an interface, but the
change would require a new PR after T4 feedback.

### Non-atomic save + enqueue with best-effort rollback

`saveTranscript()` and `enqueue()` are separate database operations. If `enqueue`
fails and `deleteTranscript` (rollback) also fails, an orphaned `Transcript` row
remains in the database, visible in history with no sync status. The V1 decision
is best-effort rollback because adding a transactional `saveAndEnqueue` to
`StorageService` is out of scope here. If this inconsistency proves problematic
in practice, a follow-up proposal should add a combined atomic storage method.

### GroqSttService owns WAV file deletion

`GroqSttService.transcribe()` deletes the input WAV file in its `finally` block
(P011 decision). This means `HandsFreeController` cannot safely retry a segment
after an STT failure because the file is already gone. In V1, all failures are
terminal — the job goes to `Failed` and the user can see the error message. If
retries become desirable, `GroqSttService` would need a "do not delete" mode or
the hands-free path would need to write a separate copy before passing to STT.

### `saveAndEnqueue` atomic operation is a V2 follow-up

`saveTranscript` + `enqueue` are separate non-transactional calls. The V1
best-effort rollback leaves a residual inconsistency risk. Track a follow-up
proposal to add `StorageService.saveAndEnqueue(Transcript)` as a single SQLite
transaction. All three call sites (TranscriptReviewScreen, the future manual-mode
persist path, and hands-free) should migrate to it once available.

### HandsFreeController using `Ref` grows toward a god controller

`HandsFreeController(Ref)` is justified by async lifecycle needs (same pattern as
`RecordingController`). However, this controller has more responsibilities than
its predecessor: session lifecycle, engine event mapping, STT serial slot, job
queue, persist+rollback, WAV cleanup, and background observer. If the controller
grows beyond the T3a+T3b scope, audit whether the persist logic should be
extracted to a standalone `SegmentPersistService`.

### isModelLoaded / loadModel are not called in hands-free path

`SttService.isModelLoaded()` and `loadModel()` are no-ops for `GroqSttService` (P011
decision). `HandsFreeController` calls `SttService.transcribe()` directly without
checking `isModelLoaded()`, mirroring the existing `RecordingController` pattern.
If a local STT implementation is ever added back, this will need to be revisited.
