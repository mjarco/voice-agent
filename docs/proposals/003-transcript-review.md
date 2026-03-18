# Proposal 003 — Transcript Review & Edit

## Status: Draft

## Prerequisites
- Proposal 002 (Speech-to-Text Engine) — provides `TranscriptResult` from the STT service that this screen displays.
- Proposal 004 (Local Storage) — provides `StorageService`, `Transcript` model, device ID, and sync queue for the Approve action.
- Proposal 008 (App Navigation) — provides the `/record/review` child route that this screen replaces.

## Scope
- Tasks: ~3
- Layers: features/transcript, app (routing)
- Risk: Low — standard Flutter UI with no platform dependencies

---

## Problem Statement

After the STT engine produces a transcript (Proposal 002), the user has no way to
review, correct, or act on the result. The raw `TranscriptResult` is ephemeral — it
exists only in memory and will be lost if the user navigates away. The app needs a
dedicated screen where the user can read the transcript, fix recognition errors, and
decide whether to approve (enqueue for sync), re-record, or discard.

---

## Are We Solving the Right Problem?

**Root cause:** The STT output is a transient object with no user-facing surface to
inspect or act on it before persistence.

**Alternatives dismissed:**
- *Auto-approve every transcript without review:* Removes user control over recognition
  errors. Polish speech recognition is imperfect — users need a correction step.
- *Inline editing on the recording screen:* Overloads the recording screen with two
  responsibilities (capture + review). Violates single-responsibility and makes the
  navigation flow harder to reason about.
- *Full-screen rich-text editor:* Over-engineered for plain-text transcripts. A simple
  `TextField` covers all needs.

**Smallest change?** Yes — this proposal adds one screen (`TranscriptReviewScreen`)
and the navigation edge from recording to it. It does not own persistence (004) or
sync (005).

---

## Goals

- Give the user a clear, fast review-and-edit experience for STT output
- Provide three unambiguous actions: approve, re-record, discard
- Pass approved transcripts to the local storage sync queue (Proposal 004)

## Non-goals

- No persistence logic — saving and queuing are owned by Proposal 004
- No network sync — owned by Proposal 005
- No transcript history browsing — owned by Proposal 007
- No rich-text formatting or multi-segment editing
- No undo/redo beyond standard platform text-field behavior

---

## User-Visible Changes

After transcription completes, the app automatically navigates to a review screen
that shows:
- The transcript text in an editable field
- Metadata (detected language, audio duration, timestamp) in a subtle secondary row
- Three action buttons: **Approve** (primary), **Re-record**, **Discard**

Tapping **Approve** saves the transcript locally, enqueues it for sync, shows a brief
confirmation snackbar, and returns to the recording screen. **Re-record** discards the
current transcript and navigates back to start a fresh recording. **Discard** returns
to the recording screen with no side effects (shows a confirmation dialog if the user
edited the text).

---

## Solution Design

### Screen States and Transitions

```
RecordingScreen
     │
     │  STT completes → TranscriptResult produced
     │
     ▼
TranscriptReviewScreen(transcriptResult)
     │
     ├── [Approve] ──► StorageService.saveTranscript(...)
     │                  StorageService.enqueue(transcriptId)
     │                  SnackBar("Transcript saved")
     │                  Navigator → RecordingScreen
     │
     ├── [Re-record] ─► Navigator → RecordingScreen (start new recording)
     │
     └── [Discard] ──► (if edited: confirm dialog) → Navigator → RecordingScreen
```

### Data Flow

The `TranscriptResult` from Proposal 002 is passed as a navigation argument via
GoRouter's `extra` parameter:

```
GoRouter route:  /record/review  (child route of /record, defined by Proposal 008)
Extra:           TranscriptResult { text, segments, detectedLanguage, audioDurationMs }
```

The `TranscriptReviewScreen` receives this object in its constructor and uses it to
populate the editable text field and metadata display. No provider is needed for the
transit — the data flows as a one-shot navigation argument.

### Widget Structure

```
TranscriptReviewScreen (ConsumerStatefulWidget)
├── AppBar (title: "Review Transcript")
├── Expanded
│   └── SingleChildScrollView
│       └── Padding
│           ├── TextField (multiline, maxLines: null, controller: _textController)
│           └── MetadataRow (language, duration, timestamp — Text widgets, muted style)
└── SafeArea
    └── ButtonBar
        ├── OutlinedButton("Re-record", icon: refresh)
        ├── TextButton("Discard", icon: close)
        └── FilledButton("Approve", icon: check)  ← primary
```

### State Management

The screen uses local `StatefulWidget` state — no global providers needed:

- `_textController`: `TextEditingController` initialized with `transcriptResult.text`
- `_isEdited`: `bool` — set to `true` on first text change, controls discard confirmation
- `_isSubmitting`: `bool` — set to `true` while saving, disables buttons to prevent double-tap

### Approve Action Contract

When the user taps **Approve**:

1. Build a `Transcript` model (from Proposal 004) with fields:
   - `id`: generated UUID (via `uuid` package from Proposal 004)
   - `text`: current value of `_textController.text`
   - `language`: from `TranscriptResult.detectedLanguage`
   - `audioDurationMs`: from `TranscriptResult.audioDurationMs`
   - `createdAt`: `DateTime.now()` as Unix milliseconds
   - `deviceId`: from `StorageService` / device ID provider (Proposal 004)
2. Call `StorageService.saveTranscript(transcript)`
3. Call `StorageService.enqueue(transcript.id)`
4. Show `SnackBar` with "Transcript saved"
5. Pop back to `/record` (recording screen)

Steps 2–3 are awaited sequentially. If either throws, show an error snackbar and
keep the user on the review screen (do not lose their text).

### Navigation Registration

Replace the review placeholder screen in the existing `/record/review` child route
(defined by Proposal 008) with the real `TranscriptReviewScreen`:

```
GoRoute(
  path: 'review',   // child of /record — resolves to /record/review
  builder: (context, state) => TranscriptReviewScreen(
    transcriptResult: state.extra as TranscriptResult,
  ),
)
```

---

## Affected Mutation Points

| File | Change |
|------|--------|
| `lib/app/router.dart` | Replace the review placeholder in the existing `/record/review` child route (from 008) with `TranscriptReviewScreen` |
| `lib/features/transcript/` | New directory — `transcript_review_screen.dart`, `widgets/metadata_row.dart` |

---

## Tasks

| # | Task | Layer |
|---|------|-------|
| T1 | Create `TranscriptReviewScreen` with editable text field, metadata row, and three action buttons (Approve, Re-record, Discard). Include discard-confirmation dialog when text was edited. Wire Approve to call `StorageService.saveTranscript` + `enqueue`. Add widget tests: renders with sample `TranscriptResult`, tapping Approve calls storage service (mocked), discard shows confirmation when text was edited. | features/transcript |
| T2 | Replace the review placeholder screen in the existing `/record/review` child route (from 008) with `TranscriptReviewScreen` in `router.dart`. Verify navigation from recording feature: after STT completes (Proposal 002), `context.push('/record/review', extra: transcriptResult)` shows the review screen. Add navigation test: pushing `/record/review` with extra displays `TranscriptReviewScreen`. | app |
| T3 | Add edge-case handling: disable buttons during save (`_isSubmitting`), show error snackbar on save failure, handle long transcripts with scrollable view. Add widget tests: buttons disabled while submitting, error snackbar shown on storage failure, long text scrolls. | features/transcript |

### T1 details

- Create `lib/features/transcript/transcript_review_screen.dart`
- Create `lib/features/transcript/widgets/metadata_row.dart`
- `TranscriptReviewScreen` is a `ConsumerStatefulWidget`
- Text field: `TextField(controller: _textController, maxLines: null, keyboardType: TextInputType.multiline)`
- Track `_isEdited` via `_textController.addListener`
- Approve button calls `ref.read(storageServiceProvider)` — the provider is defined by Proposal 004
- For testing before 004 is merged, mock `StorageService` using Riverpod overrides
- Widget tests use `ProviderScope(overrides: [...])` with a mock `StorageService`

### T2 details

- In `lib/app/router.dart`, replace the review placeholder builder in the existing `GoRoute(path: 'review', ...)` child of `/record` with `TranscriptReviewScreen`
- Navigation is already triggered by Proposal 002: after `SttService.transcribe` completes, `context.push('/record/review', extra: transcriptResult)`
- Test: `pumpWidget` with `MaterialApp.router`, push `/record/review` route, verify `TranscriptReviewScreen` is in the widget tree

### T3 details

- Wrap the approve action in try/catch; on failure, show `SnackBar` with error message
- Set `_isSubmitting = true` before save, `false` after (in `finally` block)
- Disable all three action buttons when `_isSubmitting` is true
- `SingleChildScrollView` around the text field handles long transcripts
- Test with a 5000-character transcript string to verify scrollability

---

## Test Impact

### Existing tests affected
- `test/app/app_test.dart` may need route list update if it validates route count (unlikely to break).

### New tests
- `test/features/transcript/transcript_review_screen_test.dart` — widget tests for rendering, actions, edit tracking, error handling
- `test/features/transcript/widgets/metadata_row_test.dart` — renders language, duration, timestamp
- `test/app/router_test.dart` (or extend existing) — `/record/review` route resolves to correct screen
- Run with: `flutter test`

---

## Acceptance Criteria

1. Navigating to `/record/review` with a `TranscriptResult` displays the transcript text in an editable field.
2. The metadata row shows detected language, audio duration, and timestamp.
3. Tapping Approve calls `StorageService.saveTranscript` and `StorageService.enqueue` with correct data.
4. After successful Approve, a snackbar is shown and the app navigates to the recording screen.
5. Tapping Discard without editing navigates directly to the recording screen.
6. Tapping Discard after editing shows a confirmation dialog; confirming navigates away, cancelling stays.
7. Tapping Re-record navigates to the recording screen (no confirmation needed).
8. All three action buttons are disabled while the save operation is in progress.
9. If `StorageService` throws during save, an error snackbar is shown and the user stays on the review screen with their text intact.
10. `flutter test` passes with all new widget tests.
11. `flutter analyze` exits with zero issues.

---

## Risks

| Risk | Mitigation |
|------|------------|
| Proposal 004 not yet merged — `StorageService` unavailable at development time | Mock `StorageService` via Riverpod overrides in tests; use a no-op stub in dev builds until 004 lands |
| Keyboard obscures action buttons on small screens | Action buttons are in a `SafeArea` at the bottom; `SingleChildScrollView` + `resizeToAvoidBottomInset: true` (default) handles keyboard inset |
| `TranscriptResult` is null or corrupted when arriving via `state.extra` | Add a null-check with redirect to `/` if extra is missing or wrong type; log a warning |
| Large transcript text causes janky scrolling | `TextField` with `maxLines: null` inside `SingleChildScrollView` handles this natively; test with 5000+ characters in T3 |

---

## Known Compromises and Follow-Up Direction

### No offline indicator on review screen (V1 pragmatism)
The review screen does not show whether the device is online or offline. The user
taps Approve regardless — the sync queue (Proposal 004) handles retry. A network
status indicator can be added in Proposal 005 or 008 if user feedback warrants it.

### No transcript segmentation display
Whisper provides time-stamped segments, but this screen shows only the full merged
text. Segment-level display (highlighting current segment, per-segment editing) is a
potential V2 enhancement if users need finer-grained correction.

### Confirmation dialog only on Discard, not on Re-record
Re-record implies intent to replace the transcript entirely. Adding a confirmation
dialog would add friction to a deliberate action. If user feedback shows accidental
re-records are common, add a confirmation in a follow-up.
