# Proposal 015 — TTS Response Playback

## Status: Draft

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
  Future<bool> get isSpeaking
  void dispose()
}
```

The `FlutterTtsService` implementation uses the `flutter_tts` package.
The language is set before each `speak()` — fallback: `config.language`;
if `config.language == 'auto'` → fallback to the device system language.

### ApiSuccess with body

`ApiSuccess` gets an optional field `body: String?` (raw response body).
`ApiClient.post()` passes `response.data.toString()` when status is 2xx.

### Parsing in SyncWorker

In `SyncWorker._drain()`, after `ApiSuccess`, if `ttsEnabled` and `body != null`:
1. Attempt to parse body as JSON: `jsonDecode(body)`
2. Extract `message` (String) and optionally `language` (String?)
3. `ttsService.stop()` (interrupt any ongoing playback)
4. `ttsService.speak(message, languageCode: language ?? config.language)`

Parsing is defensive: if the body is not JSON or lacks a `message` field,
`TtsService` is not called — sync completes normally.

### Interrupting TTS

Three interruption points:

1. **VAD speech start** (`HandsFreeController._onEngineEvent` → `EngineCapturing`):
   `ttsService.stop()`
2. **Tap-to-record** (`RecordingScreen` onTap, P014 T3):
   `ttsService.stop()` before `startRecording()`
3. **Press-and-hold** (`RecordingScreen` onLongPressStart, P014 T4):
   `ttsService.stop()` before `startRecording()`

`TtsService` is available via provider — injected wherever needed.

---

## Affected Mutation Points

**Needs change:**
- `ApiSuccess` — add `body: String?`
- `ApiClient.post()` — extract `response.data.toString()` and pass it to `ApiSuccess`
- `SyncWorker` — inject `TtsService`, `AppConfig` (or `ttsEnabled` flag);
  in `_drain()` on `ApiSuccess`: parse message, call `speak()`
- `HandsFreeController._onEngineEvent` (EngineCapturing case) — `ttsService.stop()`
- `RecordingScreen` (P014 T3/T4) — `ttsService.stop()` on tap and long press start
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

- `core/tts/tts_service.dart` — abstraction
- `core/tts/flutter_tts_service.dart` — implementation
- `core/tts/tts_provider.dart` — `Provider<TtsService>`
- `AppConfig.ttsEnabled` default `true`; SharedPreferences key: `'tts_enabled'`
- Tests: unit test `FlutterTtsService` with mocked `flutter_tts`; widget test toggle in Settings

### T2 details

- `ApiSuccess({this.body})` — `const ApiSuccess()` still works (body is nullable)
- `ApiClient.post()`: if response.data is Map → `jsonEncode(response.data)`;
  if String → use directly; otherwise `null`
- `SyncWorker` constructor: add `TtsService ttsService` and access to `ttsEnabled`
  (via `AppConfig` or a separate flag)
- Parsing: `try { final json = jsonDecode(body); final msg = json['message']; ... } catch (_) {}`
- Tests: `SyncWorker` with mocked `TtsService`; verify `speak()` called with correct text
  and language; verify `speak()` not called when `ttsEnabled == false`

### T3 details

- `HandsFreeController` inject `TtsService`; in `_onEngineEvent(EngineCapturing())`:
  `unawaited(ttsService.stop())`
- `RecordingScreen` (P014): before `startRecording()` in tap handler and long press handler:
  `ref.read(ttsServiceProvider).stop()`
- Tests: verify `TtsService.stop()` called on EngineCapturing event

---

## Test Impact

### Existing tests affected
- `test/features/api_sync/` — `ApiSuccess()` tests may need updating
  if `const ApiSuccess()` changes signature (body is nullable, so
  `const ApiSuccess()` still compiles)
- `test/features/recording/presentation/hands_free_controller_test.dart` —
  add mocked `TtsService` to overrides

### New tests
- Unit: `FlutterTtsService.speak()` calls flutter_tts with the correct language
- Unit: `SyncWorker` parses `{ "message": "ok", "language": "pl" }` → `speak("ok", languageCode: "pl")`
- Unit: `SyncWorker` ignores body that is not JSON
- Unit: `SyncWorker` does not call speak when `ttsEnabled == false`
- Widget: toggle in Settings saves `ttsEnabled`

---

## Acceptance Criteria

1. When the API responds with `{ "message": "Understood" }`, the app plays the text via TTS.
2. When the response contains `{ "message": "...", "language": "en" }`, TTS uses English.
3. When the response has no `message` field or is not JSON, the app is silent.
4. VAD detecting speech during TTS playback interrupts it immediately.
5. Tapping or holding the mic icon during TTS interrupts playback and starts recording.
6. The "Read API response aloud" toggle in Settings disables TTS.
7. `flutter test` and `flutter analyze` pass.

---

## Risks

| Risk | Mitigation |
|------|------------|
| `flutter_tts` on iOS requires audio session permission | Check `AVAudioSession` config; TTS should work with category `playback` |
| Concurrent TTS and microphone (echo) | TTS plays after the segment ends; VAD stops TTS when speech is detected |
| Response body may be very large | We only parse the `message` field; TTS has a natural limit via `flutter_tts` |

---

## Known Compromises and Follow-Up Direction

### No TTS queuing (V1 pragmatism)
A new response interrupts the previous one. If the user records two segments quickly,
only the last response will be read aloud. Sufficient for MVP.

### System language as fallback for 'auto' (V1 pragmatism)
If `config.language == 'auto'` and the server does not send `language`, the device
language is used. This may be incorrect if the user dictates in a different language
than the system language. Solution: dedicated language detection in a future proposal.
