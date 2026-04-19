# Proposal 015 — TTS Response Playback

## Status: Implemented

## Prerequisites
- P014 (Recording Mode Overhaul) — integration of TTS interruption on tap/press-hold
- P005 (API Sync) — `SyncWorker` must exist

## Scope
- Tasks: ~3
- Layers: domain (core), features/api_sync, features/settings
- Risk: Low — new vertical feature, does not change the existing flow

---

## Problem Statement

The app sends a transcript to the user's API but ignores the response.
If the backend is a voice assistant (responding to dictated commands),
the user has to reach for the phone to read the reply — which breaks
the screenless UX. A full voice-in / voice-out cycle is impossible.

---

## Are We Solving the Right Problem?

**Root cause:** `ApiSuccess` carries no response body — `SyncWorker` never
sees what the server returned. Even if it did, there is no service capable
of converting text to speech.

**Alternatives dismissed:**
- *Display the response on screen:* requires looking at the phone; incompatible
  with hands-free UX.
- *Push notification with the response:* requires a separate back-channel to the
  backend; significantly larger scope.

**Smallest change?** Yes — add `body: String?` to `ApiSuccess`, a `TtsService`
domain port, and wire them together in `SyncWorker`. Minimal architectural change.

---

## Goals

- When the API response contains `{ "message": "..." }`, the app reads it aloud
- The TTS language comes from the API response (`"language"` field) or falls back
  to `config.language`
- VAD, tap, and press-hold interrupt TTS and immediately start recording
- The user can disable TTS in settings

## Non-goals

- Groq responses (transcriptions) are not read aloud
- No in-app control of TTS speed/voice — system settings are sufficient
- No queuing of multiple responses — a new response interrupts the previous one

---

## User-Visible Changes

When the server responds to a sent transcript with a JSON body containing a
`message` field, the app plays that text via TTS. If the user starts speaking
(or taps/holds the mic icon), playback stops immediately.
New toggle in Settings → General: "Read API response aloud".

---

## Solution Design

### TtsService port

New domain abstraction in `core/`:

```
TtsService {
  Future<void> speak(String text, {String? languageCode})
  Future<void> stop()
  void dispose()
}
```

`languageCode` is an **ISO 639-1 two-letter code** (e.g. `"pl"`, `"en"`, `"de"`)
as sent by the server, or the `'auto'` sentinel when coming from `AppConfig.language`.
It is **not** passed directly to `flutter_tts.setLanguage()` — see below.

`isSpeaking` is intentionally excluded from the V1 interface — no caller in this
proposal needs it, and adding it forces every stub to implement an async getter.

The `FlutterTtsService` implementation uses the `flutter_tts` package
(must be added to `pubspec.yaml` in T1).
It accepts an optional `FlutterTts? tts` constructor parameter so unit tests can
inject a mock and verify `setLanguage()` calls without hitting the real plugin.
The language is set before each `speak()` call via `flutter_tts.setLanguage()`.

Language resolution inside `FlutterTtsService.speak()`:
- `'auto'` → `Platform.localeName` (full locale, e.g. `"pl_PL"`) — **not** stripped
  to two letters, because `AVSpeechSynthesizer` on iOS needs the full tag to select
  the correct voice.
- Any other code (e.g. `"pl"`) → passed as-is to `flutter_tts.setLanguage()`.
  On iOS this may silently fall back to the device default if the bare code is
  not recognized (see Known Compromises).
- `'auto'` must never reach `flutter_tts.setLanguage()` — `FlutterTtsService.speak()`
  owns the `'auto'` → `Platform.localeName` resolution.

The provider is placed at `core/tts/tts_provider.dart` (the same layer as
`TtsService`) so that `features/api_sync/`, `features/recording/`, and
`features/settings/` can all import it from `core/` without cross-feature
imports. The provider must call `ref.onDispose(() => tts.dispose())` to
release the `flutter_tts` platform channel on hot-restart and app teardown.

### ApiSuccess with body

`ApiSuccess` gets an optional field `body: String?` (raw response body).
Dio automatically decodes JSON responses into `Map<String, dynamic>` — calling
`.toString()` on a Map produces `{key: value}` (Dart's Map.toString()), which is
not valid JSON. The correct extraction:
- if `response.data is Map` → `jsonEncode(response.data)`
- if `response.data is String` → use directly
- otherwise → `null`

`const ApiSuccess()` still compiles because `body` is nullable.

### Parsing in SyncWorker

In `SyncWorker._drain()`, after `ApiSuccess`, if `ttsEnabled` and `body != null`:
1. Attempt to parse body as JSON: `jsonDecode(body)`
2. Extract `message` (String) and optionally `language` (String?)
3. `await ttsService.stop()` (interrupt any ongoing playback — must be awaited so
   that the audio session is released before the next `speak()` call)
4. `unawaited(ttsService.speak(message, languageCode: language ?? config.language))`
   — fire-and-forget: `speak()` blocks until the utterance finishes, which can be
   seconds. Awaiting it inside `_drain()` would block the 5-second poll loop.

The `language` field in the JSON response is an **ISO 639-1 two-letter code**
(e.g. `"pl"`, `"en"`, `"de"`). No validation or normalisation is performed at
this layer — the value is passed directly to `TtsService.speak()`, which owns
the `'auto'` → device locale resolution (see TtsService port section).

Parsing is defensive: if the body is not JSON or lacks a `message` field,
`TtsService` is not called — sync completes normally.

**`ttsEnabled` reactivity:** `SyncWorker` is instantiated once and held by
`syncWorkerProvider`. A raw `bool` constructor argument would go stale when
the user toggles the setting. `SyncWorker` receives a `bool Function() getTtsEnabled`
closure as a constructor argument. `syncWorkerProvider` passes
`() => ref.read(appConfigProvider).ttsEnabled`. Inside `_drain()`, call
`getTtsEnabled()` at the point of the check — not once at construction.

### Interrupting TTS

Three interruption points:

1. **VAD speech start** (`HandsFreeController._onEngineEvent` → `EngineCapturing`):
   `unawaited(ttsService.stop())` — fire-and-forget is acceptable here because
   the VAD is capturing audio immediately; the brief overlap is tolerable and
   stopping TTS does not block the event handler.
2. **Tap-to-record** (`RecordingScreen._onTap`, P014 T3):
   `await ref.read(ttsServiceProvider).stop()` — must be awaited before
   `startRecording()` to avoid an iOS AVAudioSession conflict between the
   TTS playback session and the recording session.
3. **Press-and-hold** (`RecordingScreen._onLongPressStart`, P014 T4):
   `await ref.read(ttsServiceProvider).stop()` — same reason as above.

**iOS AVAudioSession note:** `flutter_tts` activates `AVAudioSession` with
category `playback` when `speak()` is called. The `record` package uses category
`record` (or `playAndRecord`). On iOS, two conflicting sessions cannot both be
active. Awaiting `stop()` at interruption points 2 and 3 ensures the TTS session
is deactivated before recording begins. Interruption point 1 tolerates the brief
overlap because the VAD engine (already recording) takes priority.

`TtsService` is accessed via `ref.read(ttsServiceProvider)` — same pattern as
all other providers in this codebase. The provider lives in `core/tts/tts_provider.dart`.

---

## Affected Mutation Points

**New files:**
- `core/tts/tts_service.dart` — `TtsService` abstract interface
- `core/tts/flutter_tts_service.dart` — `FlutterTtsService` implementation
- `core/tts/tts_provider.dart` — `Provider<TtsService>` with `ref.onDispose`

**Needs change:**
- `ApiSuccess` — add `body: String?`
- `ApiClient.post()` — extract body via `jsonEncode` (if Map) or direct (if String)
  and pass to `ApiSuccess`; see Solution Design § ApiSuccess with body
- `SyncWorker` — add `TtsService ttsService` constructor param; read `ttsEnabled`
  reactively at call-time in `_drain()` (not as a stale `bool` field)
- `features/api_sync/sync_provider.dart` — wire `ttsServiceProvider` into
  `syncWorkerProvider`
- `HandsFreeController._onEngineEvent` (EngineCapturing case) — `unawaited(ttsService.stop())`
  via `_ref.read(ttsServiceProvider)` (same pattern as existing services in the controller)
- `RecordingScreen._onTap` and `_onLongPressStart` — `await ref.read(ttsServiceProvider).stop()`
  before `startRecording()`
- `AppConfig` — add `ttsEnabled: bool` (default `true`)
- `AppConfigService.load()` — read `tts_enabled` from SharedPreferences
- `AppConfigService.saveTtsEnabled()` — new method
- `AppConfigNotifier.updateTtsEnabled()` — new method
- `SettingsScreen` — new `SwitchListTile` in General section

**No change needed:**
- `ApiClient.testConnection()` — no TTS parsing for test calls
- `SyncWorker._promoteEligibleRetries()` — unchanged
- `HandsFreeOrchestrator` — unchanged

---

## Tasks

| # | Task | Layer |
|---|------|-------|
| T1 | `TtsService` interface + `FlutterTtsService` impl + provider; `AppConfig.ttsEnabled` + `AppConfigService` + `AppConfigNotifier`; toggle in Settings; tests | core, features/settings |
| T2 | `ApiSuccess.body` + `ApiClient` body parsing; `SyncWorker` inject TtsService + message/language parsing + speak call; tests | core/network, features/api_sync |
| T3 | TTS interruption integration: `HandsFreeController` on EngineCapturing; `RecordingScreen` on tap and long press (depends on P014 T3/T4); tests | features/recording |

### T1 details

- Add `flutter_tts: ^4.2.0` (or latest stable) to `pubspec.yaml`
- iOS native setup: `flutter_tts` uses `AVSpeechSynthesizer` — no Info.plist key required;
  verify `AVAudioSession` works alongside the `record` package (see Risks)
- Android: `flutter_tts` requires a TTS engine installed on device (normally present)
- `core/tts/tts_service.dart` — abstraction (no `isSpeaking`; see Solution Design)
- `core/tts/flutter_tts_service.dart` — implementation; accepts optional `FlutterTts? tts`
  constructor param for unit testing; `speak()` resolves `'auto'` via `Platform.localeName`
  (full locale, e.g. `"pl_PL"`) before calling `flutter_tts.setLanguage()`
- `core/tts/tts_provider.dart` — `Provider<TtsService>` with
  `ref.onDispose(() => tts.dispose())` to release the platform channel
- `AppConfig.ttsEnabled` default `true`; SharedPreferences key: `'tts_enabled'`
- **Widget test stub overrides (in T1, not T3):** once `ttsServiceProvider` exists,
  every test that pumps `RecordingScreen` or the full `App` widget will instantiate
  `FlutterTtsService` and crash. Add a no-op `_StubTtsService` override for
  `ttsServiceProvider` to all affected test files in this task:
  `recording_screen_mic_button_test.dart`, `recording_screen_test.dart`,
  `recording_screen_hands_free_test.dart`, `hands_free_controller_test.dart`,
  `settings_screen_test.dart`. This keeps `flutter test` green between T1 and T3.
- Tests: unit test `FlutterTtsService.speak()` (with injected `MockFlutterTts`) calls
  `setLanguage('pl')` not `'auto'`; unit test that `'auto'` resolves to `Platform.localeName`
  (full locale) not a stripped two-letter code; widget test toggle in Settings

### T2 details

- `ApiSuccess({this.body})` — `const ApiSuccess()` still compiles (body is nullable)
- `ApiClient.post()`: extract body as described in § ApiSuccess with body
- `SyncWorker` constructor: add `TtsService ttsService`
- `ttsEnabled` reactivity: `syncWorkerProvider` passes `() => ref.read(appConfigProvider).ttsEnabled`
  as the `getTtsEnabled` closure; never a stale `bool` constructor argument. The closure
  must capture `ref` (the live `ProviderRef`), not `ref.read(appConfigProvider).ttsEnabled`
  (which would capture the value at construction time and go stale).
- `features/api_sync/sync_provider.dart` — wire in `ttsServiceProvider`
- Parsing in `_drain()`: `try { final json = jsonDecode(body!); ... } catch (_) {}`
  — `speak()` call is fire-and-forget (`unawaited`); `stop()` call is awaited first
- Update `FakeApiClient` in test stubs to expose a settable `body` field on the
  returned `ApiSuccess` so T2 tests can inject a response body
- Tests:
  - `SyncWorker` parses `{ "message": "ok", "language": "pl" }` → `speak("ok", languageCode: "pl")`
  - `SyncWorker` calls `stop()` before `speak()` (verify ordering via call log)
  - `SyncWorker` ignores body that is not JSON
  - `SyncWorker` ignores body that is valid JSON but has no `message` field
  - `SyncWorker` does not call `speak()` when `ttsEnabled == false`

### T3 details

- `HandsFreeController` reads `TtsService` via `_ref.read(ttsServiceProvider)` —
  no constructor change; matches the existing lazy-read pattern in the class
- In `_onEngineEvent(EngineCapturing())`: `unawaited(_ref.read(ttsServiceProvider).stop())`
- `RecordingScreen._onTap` and `_onLongPressStart`: add
  `await ref.read(ttsServiceProvider).stop()` before `startRecording()` calls
- All widget test files that pump `RecordingScreen` (including
  `recording_screen_mic_button_test.dart`) must add `ttsServiceProvider.overrideWithValue(...)`
  with a stub `TtsService` to their `_baseOverrides`; otherwise the real
  `FlutterTtsService` will be instantiated and crash in the test environment
- `hands_free_controller_test.dart` must add a stub `TtsService` override so
  `EngineCapturing` event tests still pass
- Tests: verify `TtsService.stop()` called on `EngineCapturing` event
  (`hands_free_controller_test.dart`); verify `stop()` called in `_onTap` and
  `_onLongPressStart` (`recording_screen_mic_button_test.dart`)

---

## Test Impact

### Existing tests affected
- `test/features/api_sync/` — `const ApiSuccess()` still compiles; `FakeApiClient`
  stub needs a configurable `body` field so T2 tests can inject response bodies
- `test/features/recording/presentation/hands_free_controller_test.dart` —
  add stub `TtsService` override; add assertion for `stop()` on `EngineCapturing`
- `test/features/recording/presentation/recording_screen_mic_button_test.dart` —
  add stub `TtsService` override in `_baseOverrides`
- `test/features/settings/settings_screen_test.dart` —
  add stub `TtsService` override in `_baseOverrides`
- Any other test that pumps `RecordingScreen` must add the stub override

### New tests
- Unit: `FlutterTtsService.speak("text", languageCode: "pl")` calls `setLanguage("pl")`
  (uses injected `MockFlutterTts`)
- Unit: `FlutterTtsService.speak("text")` with `config.language == "auto"` calls
  `setLanguage("pl_PL")` (full `Platform.localeName`), not `setLanguage("auto")` or
  `setLanguage("pl")`
- Unit: `SyncWorker` parses `{ "message": "ok", "language": "pl" }` → `stop()` then `speak("ok", languageCode: "pl")`
- Unit: `SyncWorker` ignores body that is not JSON
- Unit: `SyncWorker` ignores body with no `message` field (e.g. `{"status": "ok"}`)
- Unit: `SyncWorker` does not call `speak()` when `ttsEnabled == false`
- Widget: toggle in Settings saves `ttsEnabled`

---

## Acceptance Criteria

1. When the API responds with `{ "message": "Understood" }`, the app plays the text via TTS.
2. When the response contains `{ "message": "...", "language": "en" }`, TTS uses English.
   The `language` value is an ISO 639-1 two-letter code (`"pl"`, `"en"`, `"de"`, etc.).
3. When the response omits `language` and `config.language` is `'auto'`, TTS uses the
   full device locale tag (e.g. `"pl_PL"` for a device set to Polish).
4. When the response has no `message` field or is not JSON, the app is silent.
5. VAD detecting speech during TTS playback interrupts it immediately.
6. Tapping or holding the mic icon during TTS interrupts playback and starts recording.
7. The "Read API response aloud" toggle in Settings disables TTS.
8. `flutter test` and `flutter analyze` pass.

---

## Risks

| Risk | Mitigation |
|------|------------|
| iOS `AVAudioSession` conflict between TTS (`playback`) and microphone (`record`) | `stop()` is awaited at tap/long-press interruption points before `startRecording()`. VAD engine is already recording when TTS fires, so `stop()` there is fire-and-forget. Verify in manual testing on device. |
| Concurrent TTS and microphone echo (VAD active while TTS plays) | TTS fires only after `SyncWorker` sends a segment; VAD stops TTS on `EngineCapturing` event |
| Response body may be very large | Only `message` field is extracted; TTS has a natural per-utterance limit via `flutter_tts` |

---

## Known Compromises and Follow-Up Direction

### No TTS queuing (V1 pragmatism)
A new response interrupts the previous one. If the user records two segments quickly,
only the last response will be read aloud. Sufficient for MVP.

### ISO 639-1 bare codes on iOS (V1 pragmatism)
`flutter_tts.setLanguage("pl")` may silently fall back to the device default on iOS
because `AVSpeechSynthesizer` prefers full BCP-47 tags (`"pl-PL"`). The `'auto'`
path passes `Platform.localeName` (full locale) and is safe. Explicit codes from the
server (`"pl"`, `"en"`) are passed as-is and are best-effort on iOS. Full locale-tag
mapping is deferred to a future proposal.

### _drain() re-entrancy (V1 pragmatism)
`SyncWorker._drain()` has no re-entrancy guard. If two timer ticks overlap
(e.g. a slow API response), a later drain may call `stop()` while a prior `speak()`
is still in progress. The resulting interruption is acceptable for V1 (it matches the
"no queuing" policy). A non-reentrant drain guard is deferred to a future proposal.

### System language as fallback for 'auto' (V1 pragmatism)
If `config.language == 'auto'` and the server does not send `language`, the device
language is used. This may be incorrect if the user dictates in a different language
than the system language. Solution: dedicated language detection in a future proposal.
