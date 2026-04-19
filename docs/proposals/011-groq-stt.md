# Proposal 011 — Groq Cloud STT

## Status: Implemented

## Prerequisites
- None — `SttService` interface already exists and is injected via Riverpod

## Scope
- Tasks: ~3
- Layers: features/recording (data, domain, presentation), core/config
- Risk: Low — replaces one `SttService` implementation; controller gets minor additions

---

## Problem Statement

On-device Whisper (`whisper_flutter_new`) is not viable for production use:

- **Model download**: ~140 MB asset bundled into the app or downloaded on first run
- **Cold start**: `loadModel()` takes several seconds on a real device before
  the first transcription can run
- **Inference speed**: transcription of a 10-second clip takes 5–20 seconds
  depending on device, making the UX feel broken
- **Binary size**: the Whisper native library adds ~60 MB to the IPA

The result: on the first real-device test session (see P010), the UX was
unusable. The user has to wait for model load before every session restart.

---

## Are We Solving the Right Problem?

**Root cause:** On-device Whisper is slow and heavy. The architecture already
abstracts STT behind `SttService` — the problem is purely in the implementation
choice, not the design.

**Alternatives dismissed:**
- *Keep on-device, optimise model*: `whisper-tiny` is faster but accuracy drops
  significantly for non-English speech, especially Polish. Not acceptable.
- *Stream audio to own server*: requires the user to run their own STT backend
  in addition to the transcript-sync backend. Too much friction.
- *OpenAI Whisper API*: identical capability to Groq, but higher latency and
  cost. Groq's free tier (2 000 req/day, 8 h audio/day) covers all development
  and personal use.

**Smallest change?** Replace `WhisperSttService` with `GroqSttService` and add
a Groq API key field to settings. The `SttService` interface stays untouched.
`RecordingController` needs two small additions: a `Ref` constructor parameter
so it can read config lazily at action time (T3), and unwrapping of `SttException`
messages in the `stopAndTranscribe` catch block (T2). All downstream consumers
of `TranscriptResult` (transcript review, history, sync) are unchanged.

---

## Goals

- Transcription on a real device completes in < 3 seconds for a 30-second clip
- App binary no longer bundles or downloads the Whisper model
- `loadModel()` / `isModelLoaded()` become no-ops (Groq is always "ready")
- Groq API key is stored securely and configurable from Settings

## Non-goals

- Fallback to on-device if Groq is unavailable (offline mode stays out of scope)
- Streaming transcription (send audio in chunks as it records)
- Support for STT providers other than Groq

---

## User-Visible Changes

A new **Groq API Key** field appears in Settings → Transcription section.
After entering the key, recording and transcribing audio is near-instant
(typically 1–2 s for a 30-second clip). If no key is set, tapping the mic
button shows an error prompting the user to configure it.

---

## Solution Design

### HTTP contract with Groq

Groq's Speech-to-Text endpoint:

```
POST https://api.groq.com/openai/v1/audio/transcriptions
Authorization: Bearer <groq_api_key>
Content-Type: multipart/form-data

fields:
  file       — WAV audio file (binary)
  model      — "whisper-large-v3-turbo"
  language   — ISO 639-1 code or omit for auto-detect
  response_format — "verbose_json"  (gives segments + language)
```

Success response (200):
```json
{
  "text": "...",
  "language": "pl",
  "duration": 12.4,
  "segments": [
    { "text": "...", "start": 0.0, "end": 2.3 },
    ...
  ]
}
```

Error responses: 401 (bad key), 429 (rate limit), 5xx (transient).

### `SttService` interface changes

`loadModel()` and `isModelLoaded()` are meaningless for a cloud service but
must remain on the interface to avoid breaking the controller. `GroqSttService`
implements them as no-ops:

- `isModelLoaded()` → always returns `true`
- `loadModel()` → does nothing

The `loadModel()` guard in `RecordingController.startRecording()` stays in place
— it just becomes instant.

### API key storage

Groq API key stored via `AppConfig.groqApiKey` (nullable `String?`), persisted
through `AppConfigService` using `flutter_secure_storage` (same as existing
`apiToken`). The key is never logged.

### Error handling in `GroqSttService`

| HTTP status | Action |
|-------------|--------|
| 200 | Parse response, return `TranscriptResult` |
| 401 | Throw `SttException('Invalid Groq API key')` |
| 429 | Throw `SttException('Groq rate limit exceeded')` |
| 4xx | Parse `response.data` with null-safe navigation: `(response.data is Map) && (response.data['error'] is Map) ? response.data['error']['message'] as String? ?? 'Transcription failed' : 'Transcription failed'`; never index blindly (body may be non-Map or missing `error.message`) |
| 5xx / timeout | Throw `SttException('Groq service unavailable')` |
| `DioExceptionType.connectionError` / offline | Throw `SttException('No network connection')` |
| `DioExceptionType.cancel` | Throw `SttException('Transcription cancelled')` |
| No key set | Throw `SttException('Groq API key not configured')` |

`RecordingController.stopAndTranscribe()` currently catches all exceptions as
`'Transcription failed: $e'`. Because `SttException.toString()` returns
`'SttException: <message>'`, a 401 would currently surface as
`"Transcription failed: SttException: Invalid Groq API key"` — not the intended
user-facing message. The catch block must be updated (T2) to unwrap `SttException`:

```
} catch (e) {
  if (e is SttException) state = RecordingState.error(e.message);
  else state = RecordingState.error('Transcription failed: $e');
}
```

### Dio configuration

`GroqSttService` accepts an optional `Dio?` constructor parameter (defaults to
a new `Dio()` instance if null). This enables injection of a mock in tests
without a separate HTTP client abstraction.

The Dio instance is configured with:
- `connectTimeout: Duration(seconds: 15)` — TCP connection to Groq endpoint
- `sendTimeout: Duration(seconds: 30)` — upload WAV file
- `receiveTimeout: Duration(seconds: 30)` — wait for transcription result

`dio` is already in `pubspec.yaml` (`^5.7.0`) — do not add it again. Verify
`HttpClientAdapter.fetch` signature against the pinned version before writing the
`FakeAdapter`: `Future<ResponseBody> fetch(RequestOptions, Stream<Uint8List>?, Future<void>?)`.

### Temp file cleanup

After uploading the WAV file to Groq, `GroqSttService.transcribe()` deletes
the file from disk regardless of success or failure (same temp file the
`RecordingServiceImpl` writes to). This prevents WAV files accumulating in the
app's temp directory.

### Provider wiring and config lifecycle

`sttServiceProvider` switches from `WhisperSttService` to `GroqSttService`,
passing `Ref` so the service reads config lazily at call time:

```
sttServiceProvider
  └─ GroqSttService(ref)          // ref.read(appConfigProvider) inside transcribe()

recordingControllerProvider
  └─ RecordingController(service, sttService, ref)   // ref.read(appConfigProvider) inside startRecording()
```

**Why `Ref` instead of a captured `AppConfig` value, and the async-load contract:**

`AppConfigNotifier` starts with `const AppConfig()` (all nulls) and loads
secure storage asynchronously via `_load()`. Capturing `appConfig.groqApiKey` at
construction time would snapshot the null value before the async load finishes.

`ref.read(appConfigProvider)` inside the action reads the _current_ state at the
moment of the tap — but that is still only safe if `_load()` has already completed.
To make this a contract rather than an assumption, `AppConfigNotifier` must expose
a `Future<void> get loadCompleted` that completes when `_load()` finishes:

```
// AppConfigNotifier addition:
final _loadCompleter = Completer<void>();
Future<void> get loadCompleted => _loadCompleter.future;
// In _load(): complete in finally so it never hangs even on error:
//   try { ... } finally { if (!_loadCompleter.isCompleted) _loadCompleter.complete(); }
```

`startRecording()` awaits this before reading config:
```
await (_ref.read(appConfigProvider.notifier) as AppConfigNotifier).loadCompleted;
final config = _ref.read(appConfigProvider);
```

The completer is resolved in a `finally` block so `loadCompleted` always
completes — even if secure-storage read throws (in that case the key stays null
and the "not configured" error is shown, which is the correct graceful-degradation
behaviour). `loadCompleted` is idempotent: awaiting it after load has already
finished returns immediately.

This also prevents the controller recreation problem: `recordingControllerProvider`
does NOT watch `appConfigProvider`, so a user changing the API key in Settings
does not recreate `RecordingController` and drop in-progress recording state.
`GroqSttService` likewise reads config lazily, so `sttServiceProvider` never
needs to rebuild on config change.

---

## Affected Mutation Points

**`SttService` implementors:**

| Site | Change needed |
|------|---------------|
| `WhisperSttService.transcribe()` | Replaced entirely by `GroqSttService` |
| `WhisperSttService.loadModel()` | Removed |
| `WhisperSttService.isModelLoaded()` | Removed |

**`AppConfig` / persistence:**

| Site | Change needed |
|------|---------------|
| `AppConfig` fields | Add `groqApiKey` |
| `AppConfig.copyWith()` | Add `groqApiKey` param |
| `AppConfigService.load()` | Read `groqApiKey` from secure storage |
| `AppConfigService.saveGroqApiKey()` | New method |
| `AppConfigNotifier.updateGroqApiKey()` | New method |
| `AppConfigNotifier.loadCompleted` | New `Future<void>` getter; completes when `_load()` finishes |

**`RecordingController` / state / providers:**

| Site | Change needed |
|------|---------------|
| `RecordingState.error(...)` factory on sealed class | Add `{bool requiresAppSettings = false}` to the redirecting factory signature — both the factory on `RecordingState` and the concrete `RecordingError` constructor must declare the default; do NOT copy the `requiresSettings` anti-pattern (existing factory omits its default) — both sides must have `= false` so callers see a consistent API |
| `RecordingError` constructor | Add `requiresAppSettings: bool = false`; assert `!(requiresSettings && requiresAppSettings)`; all call sites use factory form `RecordingState.error(msg, requiresAppSettings: true)` |
| `RecordingController` constructor | Add `Ref` parameter for lazy config reads |
| `RecordingController.startRecording()` | Add early exit: `ref.read(appConfigProvider).groqApiKey` |
| `RecordingController.stopAndTranscribe()` | Unwrap `SttException` in catch block |
| `RecordingScreen` | Handle `requiresAppSettings: true` → `context.go('/settings')` |
| `recording_screen.dart` | Add "Go to Settings" button for `requiresAppSettings` state |
| `recording_providers.dart` — `sttServiceProvider` | Switch to `GroqSttService(ref)` (T2) |
| `recording_providers.dart` — `recordingControllerProvider` | Pass `ref` to constructor (T3) |

**Tests affected by controller constructor change:**
- `recording_controller_test.dart`: every `RecordingController(fakeService, fakeStt)` call
  must be replaced with a `ProviderContainer` that satisfies `appConfigServiceProvider` —
  see T3 details for the test seam

**No change needed:**
- `SttService` interface — `loadModel`/`isModelLoaded` kept as no-ops
- All downstream consumers of `TranscriptResult`

---

## Tasks

| # | Task | Layer |
|---|------|-------|
| T1 | Add `groqApiKey` to `AppConfig`, persist via `AppConfigService`, expose in `AppConfigNotifier`; add Groq API Key field to Settings UI; add tests | core/config, features/settings |
| T2 | Implement `GroqSttService` using `dio`, wire to `sttServiceProvider`, remove `whisper_flutter_new` and model asset; add tests | features/recording/data |
| T3 | Guard recording start when Groq key is missing: add `requiresAppSettings` to `RecordingError`, check key in controller, show "Go to Settings" button navigating in-app; add tests | features/recording/domain, presentation |

### T1 details

- Add `groqApiKey: String?` to `AppConfig` and `copyWith`
- Add `saveGroqApiKey` / load in `AppConfigService` (key: `groq_api_key`,
  stored in `flutter_secure_storage`); read must use the same try-catch-return-null
  pattern as `apiToken` so that a secure-storage failure on locked devices
  degrades gracefully to `groqApiKey == null` rather than throwing
- Add `updateGroqApiKey` to `AppConfigNotifier`
- Settings UI: add Groq API Key text field (obscured) in Transcription section,
  save on focus-lost (same pattern as existing API Token field). Clearing the field
  (empty string) calls `updateGroqApiKey('')` which stores `''` in
  `flutter_secure_storage` — this is consistent with how `apiToken` is cleared and
  is safe because `startRecording()` guards on `groqApiKey == null || groqApiKey!.isEmpty`
- Async sync: `SettingsScreen` copies provider values into `TextEditingController`s
  in `initState`, but `appConfigProvider` loads secure storage asynchronously so
  the value may arrive after `initState`. Use `ref.listenManual` (called in
  `initState`, subscription stored and cancelled in `dispose`) to react to the
  first non-default config value and update the controllers:
  the listener fires when `appConfigProvider` emits an updated `AppConfig`, sets
  `_groqKeyController.text = config.groqApiKey ?? ''` (and likewise the URL and
  token controllers). `ref.listenManual` is the correct lifecycle-safe API for
  `ConsumerState.initState` — `ref.listen` is only valid inside `build()`. Apply
  the same listener to fix the identical latent bug in the existing URL and token fields.
- `groqApiKey` in `AppConfig.copyWith()` must use the sentinel pattern
  (`Object? groqApiKey = _sentinel`) consistent with `apiUrl` and `apiToken`,
  so that passing `groqApiKey: null` does not accidentally clear the key when
  only another field is being updated. The `_sentinel` constant is already defined
  as a file-private `const Object` in `app_config.dart` — add the parameter to the
  existing `copyWith` method, no new constant needed
- Tests: round-trip save/load for `groqApiKey` in `AppConfigService` tests;
  widget tests for async config load population (use `ProviderScope` with
  `appConfigServiceProvider` overridden to return a service pre-seeded with
  values, pump, assert field text is non-empty):
  - Groq API key field is populated after async config load
  - URL and token fields are populated after async config load (regression — these
    fields have the same latent bug being fixed by the `ref.listenManual` listener)

### T2 details

- `GroqSttService` sends a `multipart/form-data` POST to Groq using `dio`
- Constructor: `GroqSttService(this._ref, {Dio? dio})` — accepts `Ref` for lazy
  config reads and an optional `Dio?` for test injection; defaults to `Dio()` with
  30s send/receive timeouts
- Inside `transcribe()`, reads `_ref.read(appConfigProvider)` to get `groqApiKey`
  and `language`; throws `SttException('Groq API key not configured')` if key is null/empty
- Parses `verbose_json` response into `TranscriptResult`:
  - `text` ← top-level `text`
  - `detectedLanguage` ← top-level `language` (from response, not the hint sent)
  - `audioDurationMs` ← top-level `duration` (seconds as `double`) × 1000, rounded to `int`
  - `segments` ← `segments[]` with `start`/`end` converted from seconds (`double`) to ms (`int`)
- After upload (success or failure), deletes the WAV temp file from disk; wrap
  `File(path).delete()` in `try/catch` and swallow — a cleanup failure must not
  mask the transcription result or error
- `isModelLoaded()` returns `true`, `loadModel()` is a no-op
- Before removing `whisper_flutter_new`: run `grep -r "whisper_flutter_new" test/` to confirm
  no test files import it directly; remove the import if found
- Note: `AppConfig.language` already exists (default `'auto'`) — do not add it; just read it inside `transcribe()`. `SttService.transcribe()` already declares `{String? languageCode}` but
  `RecordingController` never passes it. `GroqSttService` compensates by reading
  `appConfig.language` internally via `Ref`. This inconsistency is a deferred
  cleanup — do not refactor the interface in this proposal.
- Delete `lib/features/recording/data/whisper_stt_service.dart` and its test file
  `test/features/recording/data/whisper_stt_service_test.dart`
- Remove `whisper_flutter_new` from `pubspec.yaml` and `assets/models/` from
  `flutter.assets`; run `make clean`
- Update `sttServiceProvider` to `GroqSttService(ref)` — service reads config
  lazily at transcription time, no rebuild on config change
- `GroqSttService` accepts `Ref` as sole constructor parameter; inside `transcribe()`,
  reads `ref.read(appConfigProvider)` to get current `groqApiKey` and `language`
- Passes `language` as the request hint when `config.language != 'auto'`, omits it otherwise
- Update `RecordingController.stopAndTranscribe()` catch block to unwrap `SttException`:
  `if (e is SttException) state = RecordingState.error(e.message)` so error messages
  surface verbatim (e.g. `"Invalid Groq API key"` rather than
  `"Transcription failed: SttException: Invalid Groq API key"`)
- Add controller unit test for the SttException unwrap path: when
  `FakeSttService.transcribe()` throws `SttException('custom message')`, state
  becomes `RecordingError` with `message == 'custom message'` (no prefix, no type name).
  This is distinct from the missing-key test in T3 — it covers the `stopAndTranscribe()`
  catch branch, not the `startRecording()` guard.
- Tests: create `GroqSttService` inside a `ProviderContainer` with
  `appConfigServiceProvider` overridden to supply a known key; inject a fake HTTP layer
  via `FakeAdapter implements HttpClientAdapter` (no extra library needed):
  - 200 success mapping (verify all `TranscriptResult` fields)
  - 401 → `SttException('Invalid Groq API key')`
  - 429 → `SttException('Groq rate limit exceeded')`
  - 5xx → `SttException('Groq service unavailable')`
  - missing key (override `appConfigServiceProvider` to return null `groqApiKey`) → `SttException('Groq API key not configured')`
  - `DioExceptionType.sendTimeout` / `receiveTimeout` → `SttException('Groq service unavailable')` (same as 5xx; verifies the timeout row in the error table)
  - 4xx with missing/malformed `error.message` body → falls back to `'Transcription failed'`
  - auto-detect language: when `config.language == 'auto'`, `language` field is omitted
    from the request and `detectedLanguage` in `TranscriptResult` is taken from the
    response body (e.g., `'pl'`) rather than from the config
  - WAV file deleted after successful upload
  - WAV file deleted after failed upload
  - `loadModel()` is a no-op, `isModelLoaded()` returns `true`

### T3 details

- `RecordingController` constructor signature becomes
  `RecordingController(this._service, this._sttService, this._ref)` where
  `_ref` is a `Ref` passed from `recordingControllerProvider`
- `recordingControllerProvider` passes `ref` (NOT `ref.watch(appConfigProvider)`)
  so controller identity is independent of config — config changes do NOT recreate
  the controller and cannot drop in-progress recording state
- Guard order at the start of `startRecording()`:
  1. Permission check (existing — microphone permission, opens OS settings on denial)
  2. Groq key check — await load, then read config:
     `await (_ref.read(appConfigProvider.notifier) as AppConfigNotifier).loadCompleted;`
     `final config = _ref.read(appConfigProvider);`
     if `config.groqApiKey == null || config.groqApiKey!.isEmpty` → emit error and return
  3. `isModelLoaded` / `loadModel` guard (existing no-op for Groq, keeps in place)
  The key check comes before `isModelLoaded` to fail fast before touching platform resources.
  Awaiting `loadCompleted` guarantees the key is the persisted value, not the initial null default
- If not configured: emit `RecordingState.error('Groq API key not set.', requiresAppSettings: true)` (factory form, consistent with existing call sites)
- Add `requiresAppSettings: bool` flag (default `false`) to `RecordingError`,
  alongside the existing `requiresSettings: bool` (which opens OS app settings).
  The two flags serve different navigation targets and are mutually exclusive:
  `RecordingError` should assert `!(requiresSettings && requiresAppSettings)`.
  `RecordingScreen` error branch must destructure **both** boolean fields and use a
  three-way check (not two independent `if` blocks):
  ```
  RecordingError(:final message, :final requiresSettings, :final requiresAppSettings) =>
    if (requiresAppSettings) → "Go to Settings" → context.go('/settings')
    else if (requiresSettings) → "Open Settings" → openAppSettings()
    else → "Try Again" (default error button)
  ```
  Omitting `requiresAppSettings` from the destructure makes the "Go to Settings"
  branch unreachable with no compile error. The order matters: `requiresAppSettings`
  must be the **first** `if` — adding it at the end after the existing
  `if (requiresSettings) ... else ...` also makes it unreachable (the `else` already
  catches all non-`requiresSettings` cases). Both flags default to `false`.
- **Test seam for controller tests:** unit tests cannot use the real `Ref`; instead
  create a `ProviderContainer` with overrides for these three providers and get the
  controller via `container.read(recordingControllerProvider.notifier)`:
  - `appConfigServiceProvider` — override with a fake `AppConfigService` that returns
    the desired `AppConfig` synchronously. This constructs a real `AppConfigNotifier`
    automatically, making the cast `as AppConfigNotifier` in `startRecording()` safe.
    **Do NOT override `appConfigProvider` directly** — a substitute notifier that is
    not an `AppConfigNotifier` will throw `TypeError` at that cast.
  - `recordingServiceProvider` — override with `FakeRecordingService` (hand-written
    class implementing `RecordingService`; no `mocktail` — consistent with existing
    test patterns in this repo)
  - `sttServiceProvider` — override with `FakeSttService` (hand-written class
    implementing `SttService`; check `whisper_stt_service_test.dart` before deleting
    it in T2 — it may contain a `FakeSttService` worth reusing; if so, move it to
    `test/helpers/fake_stt_service.dart` before deletion)
  - Missing-key scenario: fake `AppConfigService` returns `AppConfig()` (null key)
  - Valid-key scenario: fake returns `AppConfig(groqApiKey: 'test-key')`
- Tests: controller unit test for missing-key path (fires `RecordingError` with
  `requiresAppSettings: true`); widget tests covering all three `RecordingError`
  branches in `RecordingScreen` (these are regression tests — the existing
  `requiresSettings` and default "Try Again" paths must still pass after the
  three-way branch is introduced):
  - `requiresAppSettings: true` → "Go to Settings" button present, "Open Settings" absent
  - `requiresSettings: true` → "Open Settings" button present, "Go to Settings" absent
  - neither flag → "Try Again" button present, both Settings buttons absent
- **`ProviderContainer` binding requirement:** unit tests using `ProviderContainer`
  must still call `TestWidgetsFlutterBinding.ensureInitialized()` before constructing
  the container, because `RecordingController` registers a `WidgetsBindingObserver`
  in its constructor

---

## Test Impact

### Existing tests affected
- `recording_controller_test.dart`: constructor changes from `(fakeService, fakeStt)`
  to using a `ProviderContainer` with `appConfigServiceProvider` overridden; all
  existing tests must be adapted (enumerate occurrences before writing T3)
- `app_config_service_test.dart`: add round-trip test for `groqApiKey`
- `recording_screen_test.dart`: existing tests that exercise the mic-tap path
  (triggering `startRecording()`) **must** override `appConfigServiceProvider` —
  the cast `as AppConfigNotifier` inside `startRecording()` is unconditional and
  will throw `TypeError` if the provider is not overridden or if `flutter_secure_storage`
  platform channels are not initialised in the test environment
- `test/features/settings/` — check for any existing settings screen test file before
  writing T1; if one exists, it must be updated to override `appConfigServiceProvider`
  with a pre-seeded config (the `ref.listenManual` fix changes existing URL/token
  field population behaviour, not just adds the Groq field)

### New tests
- `groq_stt_service_test.dart` — `test/features/recording/data/`:
  unit tests using `FakeAdapter implements HttpClientAdapter`; also needs
  `appConfigServiceProvider` overridden in a `ProviderContainer` to supply the key
- `test/features/settings/settings_screen_test.dart` (new file):
  - Groq API Key field appears in Settings
  - Field is populated after async config load (override `appConfigServiceProvider`)
  - Field saves on focus-lost
- `test/features/recording/presentation/recording_screen_test.dart`:
  add test: when `recordingControllerProvider` is in
  `RecordingError('...', requiresAppSettings: true)`, "Go to Settings" button appears

---

## Acceptance Criteria

1. User enters Groq API key in Settings → Transcription → key is persisted across
   app restarts, and the field is populated when the screen opens after restart.
2. If Groq API key is not set, tapping the mic button shows an error state with
   a "Go to Settings" button that navigates to the in-app Settings tab (not OS settings).
3. If Groq returns 401, the error state shows "Invalid Groq API key".
4. If Groq returns 429, the error state shows "Groq rate limit exceeded".
5. If the device has no network, the error state shows "No network connection"
   (not a raw `DioException` message).
6. The WAV temp file is deleted from disk after transcription regardless of
   success or failure (verified by the unit tests in T2).
7. `flutter analyze` passes with zero issues; all tests pass.

**Validation notes (manual, on-device):**
- V1: Recording a 10-second clip completes transcription in under 5 seconds on a
  real device with a working network connection.
- V2: `flutter build ios --release` IPA size is at least 60 MB smaller than a
  baseline build produced before removing `whisper_flutter_new`. Record the two
  sizes in the PR description.

---

## Known Compromises and Follow-Up Direction

### No offline transcription (V1 pragmatism)
This proposal removes on-device STT entirely. If the device has no network,
transcription will fail. Acceptable for now — the app already requires network
for sync. A future proposal could add an optional offline fallback.

### `Ref` injected into a data-layer class (V1 pragmatism)

`GroqSttService` receives a `Ref` to read config lazily, which is unusual for a
data-layer class (CLAUDE.md expects data classes to import only platform packages).
It works and does not violate the dependency rule — `flutter_riverpod` is a
framework package, not a feature. However, it sets a precedent that could erode the
presentation/data boundary. A cleaner follow-up would move the lazy reads to the
provider body and pass `groqApiKey` and `language` explicitly to `transcribe()`,
keeping `GroqSttService` free of Riverpod.

### Missing-key check only in `startRecording()` (V1 pragmatism)

If a user starts recording with a valid key, navigates to Settings (another tab),
removes the key, returns, and taps Stop — `stopAndTranscribe()` will call
`GroqSttService.transcribe()` which throws `SttException('Groq API key not
configured')`. The `stopAndTranscribe()` catch block surfaces this as a generic
`RecordingError` without `requiresAppSettings: true`, so the user sees a "Try Again"
button instead of "Go to Settings". This is acceptable for V1: the user explicitly
deleted their key mid-session, and the very next tap on the mic will trigger
`startRecording()`'s guard, showing the correct "Go to Settings" prompt.

### WAV temp file not deleted on `cancelRecording()` (V1 pragmatism)

`GroqSttService.transcribe()` deletes the WAV file after upload (success or failure),
but if the user cancels mid-recording via `cancelRecording()`, the WAV file is
written to disk and then abandoned — `transcribe()` is never called and the cleanup
never runs. This is a pre-existing gap (same behaviour as `WhisperSttService`).
Acceptable for V1: cancel mid-recording is uncommon and the OS will eventually
reclaim temp files. A follow-up should add cleanup in `RecordingServiceImpl.cancel()`
once the cancel path is more actively used.

### `DioExceptionType.cancel` row in error table is unreachable in V1 (V1 pragmatism)

The error table lists `DioExceptionType.cancel → SttException('Transcription cancelled')`,
but this type is only raised by Dio when a `CancelToken` is passed to the request.
`GroqSttService.transcribe()` does not accept a `CancelToken` in V1. The row documents
desired future behaviour; the V1 implementation will never reach that branch.
A follow-up should add a `CancelToken?` parameter to `transcribe()` and wire it
to `cancelRecording()` so in-flight HTTP uploads can be cancelled gracefully.

### Hard cast `appConfigProvider.notifier as AppConfigNotifier` in controller (V1 pragmatism)

`startRecording()` accesses `loadCompleted` via a hard cast:
`(_ref.read(appConfigProvider.notifier) as AppConfigNotifier).loadCompleted`.
This is safe in production and in tests that override `appConfigServiceProvider`
(which constructs a real `AppConfigNotifier`), but will throw `TypeError` if any
future test or integration overrides `appConfigProvider` directly with a different
notifier type. A cleaner follow-up would expose `loadCompleted` via a dedicated
`appConfigLoadedProvider` (`FutureProvider<void>`) so no cast is needed.

### `loadModel` / `isModelLoaded` kept on `SttService` interface
These methods are now meaningless for cloud STT. They stay to avoid a breaking
interface change at this point. A follow-up cleanup proposal could remove them
once no in-device implementation exists.
