# Proposal 017 — Personal Agent Integration

## Status: Implemented

## Prerequisites
- P005 (API Sync) — `SyncWorker._drain()` with `_handleReply()` response handling must exist; merged
- P016 (Audio Feedback) — `SyncWorker` constructor pattern established; merged
- personal-agent P025 (Voice Chat Integration) — `POST /api/v1/voice/transcript` endpoint must be deployed

## Scope
- Tasks: 2
- Layers: features/settings (URL guidance), features/api_sync (reply emission), features/recording (reply display)
- Risk: Low — additive; no existing sync or TTS logic changed

---

## Problem Statement

Voice-agent can post transcripts to any HTTP endpoint, and personal-agent now accepts voice transcripts at `POST /api/v1/voice/transcript` (P025). However, connecting the two requires users to know the exact URL format and manually type it into a generic blank field. There is no in-app guidance.

Additionally, when personal-agent replies, `SyncWorker._handleReply()` speaks the reply via TTS but the text is ephemeral — never displayed. Users in noisy environments who cannot hear the reply have no way to read what the agent said.

---

## Are We Solving the Right Problem?

**Root cause (settings):** The URL `TextField` has no hint text or description explaining the expected format. A user connecting to personal-agent must know the exact path (`/api/v1/voice/transcript`) with no guidance from the app.

**Root cause (display):** `_handleReply()` extracts `message` from the API response and passes it straight to `TtsService.speak()`. The text is never stored or exposed to any UI widget. Riverpod `StateProvider` makes it straightforward to bridge this gap without changing sync or TTS logic.

**Alternatives dismissed:**

- *Persist reply in the `transcripts` table:* Requires schema migration and repository changes. The reply is ephemeral — the agent's response to that specific recording in context. Storing it permanently is overengineering for a display-only use case in V1.
- *Show reply in `TranscriptDetailScreen`:* The reply arrives 5–30 s after recording; by the time the user navigates to history the moment has passed. The `RecordingScreen` is where attention already is.

**Smallest change?** A `StateProvider<String?>` updated by `SyncWorker` on reply, read by `RecordingScreen`. No database changes; no changes to TTS logic.

---

## Goals

- The settings screen provides clear in-app guidance for connecting to personal-agent
- The agent's text reply is displayed on `RecordingScreen` after the sync cycle completes
- The reply display does not block or delay recording — it appears asynchronously when sync finishes
- The reply is cleared when a new recording or hands-free session starts

## Non-goals

- Persisting replies to SQLite
- Showing replies in `HistoryScreen` or `TranscriptDetailScreen`
- Streaming / token-by-token reply display
- Any changes to existing TTS behavior

---

## User-Visible Changes

**Settings screen:** The API endpoint `TextField` shows `http://192.168.x.x:8888/api/v1/voice/transcript` as hint text. A short description above the URL field explains the personal-agent connection.

**RecordingScreen:** After a recording is processed and personal-agent replies, a card appears below the recording controls with the agent's reply text and a dismiss button. Starting a new recording clears the card.

---

## Solution Design

### T1: Settings guidance

In `lib/features/settings/settings_screen.dart`, locate the URL `TextField`:

- Set `hintText: 'http://192.168.x.x:8888/api/v1/voice/transcript'`
- Set `helperText: 'Personal agent: http://<host>:8888/api/v1/voice/transcript'` and `helperMaxLines: 2`
- Add a `Text` description widget immediately above the URL field:
  `'Connect to a personal-agent backend for knowledge extraction and spoken replies.'`

No new fields, no new state, no new providers.

### T2: Agent reply display

#### `latestAgentReplyProvider`

New file `lib/core/providers/agent_reply_provider.dart` (in core, not in a feature,
so both `features/api_sync` and `features/recording` can import it without
violating the cross-feature import rule — same pattern as `apiUrlConfiguredProvider`):

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

final latestAgentReplyProvider = StateProvider<String?>((ref) => null);
```

#### SyncWorker changes

Add an optional `void Function(String reply)? onAgentReply` named constructor parameter to `SyncWorker` (default `null`).

Refactor `_handleReply()`: move the `getTtsEnabled()` guard to wrap only the
TTS call, and place `onAgentReply` outside the guard so the reply card always
appears even when TTS is disabled:

```dart
void _handleReply(String? body) {
  if (body == null) return;
  try {
    final json = jsonDecode(body) as Map<String, dynamic>;
    final message = json['message'] as String?;
    if (message == null || message.isEmpty) return;
    final language = json['language'] as String?;
    if (getTtsEnabled()) {
      unawaited(ttsService.stop().then((_) => ttsService.speak(message, languageCode: language)));
    }
    onAgentReply?.call(message);   // always called — independent of TTS toggle
  } catch (_) {}
}
```

`onAgentReply` is called synchronously before `_handleReply` returns; it is never called on failure paths.

#### sync_provider.dart

Wire the callback in the `SyncWorker(...)` constructor call:

```dart
onAgentReply: (reply) {
  ref.read(latestAgentReplyProvider.notifier).state = reply;
},
```

#### RecordingScreen

- Watch `latestAgentReplyProvider`: `final agentReply = ref.watch(latestAgentReplyProvider);`
- When `agentReply != null`: render an `AnimatedSwitcher`-wrapped `Card` with `Text(agentReply!)` and an `IconButton(icon: Icon(Icons.close))` that sets `ref.read(latestAgentReplyProvider.notifier).state = null`
- The card has a `SingleChildScrollView` with a `maxHeight` constraint (e.g. `200`) so a long reply does not push recording controls off screen
- `AnimatedSwitcher` uses `duration: Duration(milliseconds: 200)` with default fade transition
- Clear on recording start:
  - In `_MicButton._onTap()` and `_MicButton._onLongPressStart()`: add `ref.read(latestAgentReplyProvider.notifier).state = null` before the `recCtrl.startRecording()` call. (`_MicButton` is a private `ConsumerStatefulWidget` nested inside `recording_screen.dart` with its own `ref`.)
  - For hands-free: add a `ref.listen` on `handsFreeControllerProvider` that nulls the reply when state transitions to `HandsFreeCapturing` (i.e., when user starts speaking again — the logical analog of starting a new recording)

### Affected mutation points

**New files:**
- `lib/core/providers/agent_reply_provider.dart` — `latestAgentReplyProvider`

**Modified files (T1):**
- `lib/features/settings/settings_screen.dart` — hint text, helper text, description widget

**Modified files (T2):**
- `lib/features/api_sync/sync_worker.dart` — `onAgentReply` constructor param + call in `_handleReply()`
- `lib/features/api_sync/sync_provider.dart` — wire `onAgentReply` callback
- `lib/features/recording/presentation/recording_screen.dart` — watch provider, render reply card, clear on recording start
- `test/features/api_sync/sync_worker_test.dart` — assert callback behavior
- `test/features/recording/presentation/recording_screen_test.dart` — provider override + card visibility assertions

---

## Tasks

| # | Task | Layer |
|---|------|-------|
| T1 | Settings screen: URL hint text, helper text, description for personal-agent connection | features/settings |
| T2 | `latestAgentReplyProvider` + `SyncWorker.onAgentReply` callback + `RecordingScreen` reply card; tests | features/api_sync, features/recording |

### T1 details

- In `lib/features/settings/settings_screen.dart`, find the URL `TextField` (controlled by `_urlController`):
  - Add `hintText: 'http://192.168.x.x:8888/api/v1/voice/transcript'` to `InputDecoration`
  - Add `helperText: 'Personal agent: http://<host>:8888/api/v1/voice/transcript'` and `helperMaxLines: 2`
- Add a `Padding`-wrapped `Text` widget (style: `Theme.of(context).textTheme.bodySmall`) immediately above the URL field with the text: `'Connect to a personal-agent backend for knowledge extraction and spoken replies.'`
- No new tests required — text-only change; existing settings screen tests remain valid

### T2 details

- `lib/core/providers/agent_reply_provider.dart`: `StateProvider<String?>` as shown above
- `lib/features/api_sync/sync_worker.dart`:
  - Add `final void Function(String reply)? onAgentReply;` to the constructor and field list
  - In `_handleReply()`: after the existing `unawaited(ttsService.stop()...)` line (or when TTS is disabled), add `onAgentReply?.call(message);` — call regardless of `getTtsEnabled()` so the card always appears even when TTS is off
- `lib/features/api_sync/sync_provider.dart`: add `onAgentReply: (reply) => ref.read(latestAgentReplyProvider.notifier).state = reply` to the `SyncWorker(...)` call; add import for `agent_reply_provider.dart`
- `lib/features/recording/presentation/recording_screen.dart`:
  - Add `ref.watch(latestAgentReplyProvider)` call
  - Render `AnimatedSwitcher` with `Card` when non-null (see Solution Design above)
  - In `_MicButton._onTap()` and `_MicButton._onLongPressStart()`: `ref.read(latestAgentReplyProvider.notifier).state = null;` before the `recCtrl.startRecording()` call
  - For hands-free: `ref.listen` on `handsFreeControllerProvider` that nulls the reply on `HandsFreeCapturing` transition
- Tests in `test/features/api_sync/sync_worker_test.dart`:
  - `onAgentReply` is called with the correct string when `_drain()` receives an `ApiSuccess` response containing `{"message": "hello"}`
  - `onAgentReply` is called even when `getTtsEnabled()` returns `false`
  - `onAgentReply` is NOT called when `ApiPermanentFailure` or `ApiTransientFailure`
  - `onAgentReply` is NOT called when success body contains no `message` field
- Tests in `test/features/recording/presentation/recording_screen_test.dart`:
  - Override `latestAgentReplyProvider` with `'Agent reply text'` → assert reply `Card` is visible and contains the text
  - Override with `null` → assert card is absent
  - With reply visible, tap dismiss (×) button → assert card disappears and `latestAgentReplyProvider` is `null`
- Tests in `test/features/recording/presentation/recording_screen_mic_button_test.dart`:
  - Tap mic button → assert `latestAgentReplyProvider` is set to `null` (clearing on tap-start)
  - Long-press mic button → assert `latestAgentReplyProvider` is set to `null` (clearing on long-press start)
- Tests in `test/features/recording/presentation/recording_screen_hands_free_test.dart`:
  - Transition to `HandsFreeCapturing` → assert `latestAgentReplyProvider` is set to `null` (clearing on hands-free capture start)

---

## Test Impact

### Existing tests affected

- `test/features/api_sync/sync_worker_test.dart` — `onAgentReply` is an optional named param defaulting to null; all existing tests pass without modification; 4 new assertion tests added
- `test/features/recording/presentation/recording_screen_test.dart` — 3 new test cases (card visibility + dismiss)
- `test/features/recording/presentation/recording_screen_mic_button_test.dart` — 2 new test cases for reply clearing on tap and long-press
- `test/features/recording/presentation/recording_screen_hands_free_test.dart` — 1 new test case for reply clearing on capture start

### New tests

- `test/features/api_sync/sync_worker_test.dart`: callback behavior — 4 cases (T2)
- `test/features/recording/presentation/recording_screen_test.dart`: card visibility + dismiss — 3 cases (T2)
- `test/features/recording/presentation/recording_screen_mic_button_test.dart`: clearing behavior — 2 cases (T2)
- `test/features/recording/presentation/recording_screen_hands_free_test.dart`: clearing behavior — 1 case (T2)

Run: `flutter analyze && flutter test`

---

## Acceptance Criteria

1. The API endpoint field in Settings shows `http://192.168.x.x:8888/api/v1/voice/transcript` as placeholder text.
2. A short description above the URL field explains the personal-agent connection.
3. After a recording is sent to personal-agent and a reply arrives, the reply text appears on `RecordingScreen`.
4. The reply card appears even when TTS is disabled in Settings.
5. Starting a new recording (tap or long-press) clears the previous reply card.
6. Starting to capture speech in hands-free mode clears the previous reply card.
7. The dismiss (×) button on the card clears the reply without starting a new recording.
8. TTS behavior is unchanged — the reply is still spoken when TTS is enabled.
9. `flutter analyze` and `flutter test` pass.

---

## Risks

| Risk | Mitigation |
|------|------------|
| Reply arrives after user navigated away from `RecordingScreen` | `StateProvider` persists across navigation; card renders when user returns. Acceptable in V1. |
| Long agent reply overflows screen | Card uses `SingleChildScrollView` with a `maxHeight` constraint; recording controls remain visible. |
| `onAgentReply` called from an async context with stale `ref` | `SyncWorker._handleReply()` runs on the Dart event loop (not an isolate); Riverpod state writes from async functions on the main isolate are safe. |
| Settings hint text too long on small screens | `helperMaxLines: 2` wraps gracefully; verify on iPhone SE viewport. |

---

## Alternatives Considered

**Persist reply in DB:** Store the API response `message` alongside the transcript. Enables `TranscriptDetailScreen` to show past replies. Rejected for V1 — adds schema migration complexity for a display-only feature. Can be added as a follow-up once the pattern is validated.

**Show reply in `TranscriptDetailScreen`:** Natural place for persisted history. Deferred — requires persistence (see above).

---

## Known Compromises and Follow-Up Direction

### Reply not persisted (V1)

The reply resets on app restart and is lost if the user backgrounds the app before reading it. A follow-up could add a `agent_reply TEXT` column to the `transcripts` table, store the reply alongside the transcript, and surface it in `TranscriptDetailScreen`.

### Personal-agent-specific hint text replaces generic hint (V1)

The URL field's existing generic `hintText` (`'https://your-api.com/endpoint'`) is replaced with a personal-agent-specific one (`'http://192.168.x.x:8888/api/v1/voice/transcript'`). This is acceptable because personal-agent is the primary integration target. Users with a different backend can still type any URL — the hint is guidance, not a constraint.

### Stale reply after rapid re-recording (V1)

If the sync of recording A is still in flight when the user starts recording B, the reply-clear fires at B's start but A's reply arrives afterwards and repopulates the card. The window is small (personal-agent typically responds in <5 s) and the worst case is a briefly confusing card the user can dismiss. A follow-up could suppress `onAgentReply` while a recording is active, or correlate replies to a transcript ID so out-of-order arrivals are discarded.

### No streaming display (V1)

The reply is shown in full when sync completes. Personal-agent's endpoint returns a complete synchronous response. Token-by-token display would require a streaming mode on both sides — a separate future proposal.
