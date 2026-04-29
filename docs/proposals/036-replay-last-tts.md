# Proposal 036 — Replay Last TTS Reply (Client-Side)

## Status: Draft

## Origin

Production conversation `019dd85d-b27e-7b26-9d5c-6fff5a5b5495` on 2026-04-29:

- [42] user: "Powtórz, żeby coś przerwało."
  → [43] agent: "Nie rozumiem — co dokładnie mam powtórzyć?"
- [44] user: "Powtórz ostatnią wygenerowaną wiadomość."
  → [45] agent re-generates the long action-item list — text identical, but
  this is a fresh LLM call, costs tokens, and adds latency.

The user wanted to *re-hear* the previous reply. There is no need to
round-trip the backend.

## Prerequisites / Scope

- **Tier 0** — voice-agent only, no backend contract change, no schema
  change, no new permissions, no platform-audio behavior change.
- Depends on **P029** (`reset_session` and `adoptConversationId` already
  implemented in `SessionIdCoordinator`) and **P030** (TTS mixed-language
  splitter / `<lang>` segment shape) as **already merged & implemented**.
  This proposal builds on the existing `TtsService` interface and the
  `_handleReply` reply-receipt path; it does not modify either.

## Problem

"Powtórz" is a common voice command in hands-free use. Today it is treated as
a chat turn → LLM call → TTS render. Three issues:

1. Latency: 2–4 s wait for an answer the device already has.
2. Cost: a re-generation costs the same as a fresh question.
3. Drift: nothing guarantees the regenerated text matches the original; the
   user hears something close-but-different.

## Goals

- Recognise a small, conservative whitelist of replay phrases on-device.
- Re-speak the most recently spoken successful agent reply from an in-memory
  buffer, with no network round-trip and no LLM call.
- Provide unambiguous user feedback (toast + haptic) on every replay,
  including the empty-buffer case.
- Preserve all existing layering, dependency-rule, and TTS-ordering
  invariants from P029 / P030.

## Approach — Client-Side Local Command

This is a voice-agent-only proposal. No backend change.

### Architecture & layer placement

To respect the dependency rule (`features/` may not import from other
`features/`; `core/` may not import from `features/`), the new code is split
across `core/` and `features/api_sync/`:

| New element | Location | Responsibility |
|---|---|---|
| `TtsReplyBuffer` (interface) | `lib/core/tts/tts_reply_buffer.dart` | Ring-buffer port: `record(text, languageCode)`, `last()`, `clear()`. |
| `InMemoryTtsReplyBuffer` (impl) | `lib/core/tts/tts_reply_buffer.dart` | Default in-memory bounded buffer. |
| `BufferingTtsService` (decorator) | `lib/core/tts/buffering_tts_service.dart` | Decorates `TtsService.speak(...)`; on every successful `speak` call writes `(text, languageCode)` into the buffer. The decorator is only wired around the *agent-reply* speak site (see "Capture site" below) — **not** around error/feedback speak calls. |
| `LocalCommandMatcher` | `lib/core/local_commands/local_command_matcher.dart` | Pure function `match(String utterance) → LocalCommandDecision`. |
| `LocalCommandDecision` | `lib/core/local_commands/local_command_matcher.dart` | Sealed: `passthrough` / `replayLast` / `bufferEmpty`. |
| Wiring | `lib/features/api_sync/sync_worker.dart` | Consumes the matcher between transcript fetch and `apiClient.post`. Reads from the buffer to replay; emits the toast/haptic. |

`features/recording/` does **not** import the buffer or the matcher. The
matcher runs inside the sync pipeline (`SyncWorker._processNext`) before the
network call, which is the single funnel through which every captured
utterance — VAD-driven or manual — already passes. This avoids any
cross-feature import.

### Capture site (who writes to the buffer)

The buffer is written **only** from the agent-reply path in
`SyncWorker._handleReply` (`sync_worker.dart`), specifically when:

1. `getTtsEnabled()` is true,
2. `message` is non-null and non-empty, and
3. `ttsService.speak(message, languageCode: language)` returned without
   throwing.

The buffer entry is `(text: message, languageCode: language)` — i.e. exactly
what was passed to `speak`. The platform engine handles the same `<lang>`
segment splitting on replay because P030's splitter is invoked by the
shared `FlutterTtsService.speak` implementation.

**Explicitly excluded** from the buffer:

- Any error / feedback `speak` calls (e.g. local error announcements,
  audio-feedback service utterances, future error-speak helpers). Today the
  codebase has exactly one `ttsService.speak` callsite, in `_handleReply`;
  the decorator is wrapped only around the instance used by that callsite.
  If a future PR adds an error-speak path, it must use a separate
  `TtsService` instance (or call the underlying `FlutterTtsService` directly,
  bypassing `BufferingTtsService`) so error text never lands in the replay
  buffer.

### Local-command matcher

Before sending a transcribed utterance to `/api/v1/voice/transcript`, the
sync worker passes the transcript through `LocalCommandMatcher.match`.

Matcher contract — **deliberately conservative**:

1. Lowercase the utterance, trim leading/trailing whitespace, strip
   trailing punctuation (`. , ! ? ; :`), collapse internal whitespace runs
   to a single space.
2. If the normalized string is **exactly** equal to one of the entries in
   the whitelist below → return `replayLast` (or `bufferEmpty` if the
   buffer is empty).
3. Otherwise → return `passthrough`. The transcript is sent to the backend
   normally.

Whitelist (whole-utterance match only — substring matches do **not**
trigger):

```
powtórz
powtórz proszę
powtórz to
powtórz jeszcze raz
jeszcze raz
repeat
say again
say it again
```

Any utterance that contains additional content words — e.g. "Powtórz, żeby
coś przerwało.", "Powtórz, że X", "powtórz ostatnią wygenerowaną wiadomość"
— falls through to the backend. This is intentional: a regex / substring
match would mis-trigger on the [42] case from the origin transcript. We
prefer false negatives (one extra LLM call) over false positives (silently
swallowing a real chat turn). The whitelist may be widened later based on
production telemetry; v1 ships small.

### TTS ordering on replay

When the matcher returns `replayLast` and the buffer has an entry:

1. Show toast "Powtarzam ostatnią odpowiedź" + light haptic tick.
2. If `ttsService.isSpeaking.value` is true, call `ttsService.stop()` and
   await it. (Mirrors the stop-then-speak ordering in
   `SyncWorker._handleReply` and the P029 "Order-of-signal-arrival edge"
   note.)
3. Call `ttsService.speak(buffered.text, languageCode: buffered.languageCode)`.
4. Mark the original transcript queue item as locally handled — i.e. do
   **not** call `apiClient.post`, do **not** mark sent/failed/pending. The
   item is treated as consumed by the local command and removed from the
   queue (same effect as `markSent` for queue-state purposes; the
   transcript row stays in storage and history shows it as "local").

When the matcher returns `bufferEmpty`:

1. Show toast "Brak wcześniejszej odpowiedzi" + light haptic tick.
2. Fall through to the backend (`apiClient.post`) so the user still gets
   *some* response.

### Buffer lifetime

- **In-memory only.** Not persisted. Cleared on app restart.
- **Cleared on `SessionIdCoordinator.resetSession()`** — already invoked by
  `SessionControlDispatcher` when the backend sends `reset_session: true`
  (P029). The buffer subscribes to the same reset trigger via a port
  callback rather than importing the dispatcher.
- **Cleared on `adoptConversationId(newId)`** when `newId` differs from the
  buffer's current conversation tag. This handles the case where the
  backend rotates conversation_id without an explicit `reset_session`.
- **Not cleared on `stop_recording`.** Stopping recording does not start a
  new conversation — pressing record again resumes the same conversation
  and the user may legitimately ask to replay the last reply at that
  point. Buffer survives `stop_recording`.
- The buffer keeps a small bounded history (see "Buffer size" below); on
  overflow it evicts oldest first (LRU / ring).

## Tasks

PR-sized split. Each task is one PR; `make verify` must pass at every
step.

| # | Title | Files / new types |
|---|---|---|
| **T1** | Add `TtsReplyBuffer` port + `InMemoryTtsReplyBuffer` impl + tests | `lib/core/tts/tts_reply_buffer.dart` (new); `test/core/tts/tts_reply_buffer_test.dart` (new). |
| **T2** | Add `BufferingTtsService` decorator + tests; wire it into the TTS provider chain so `_handleReply`'s `ttsService` is the buffering instance | `lib/core/tts/buffering_tts_service.dart` (new); `lib/core/tts/tts_provider.dart` (edit, add buffer provider + decorator override); `test/core/tts/buffering_tts_service_test.dart` (new). |
| **T3** | Add `LocalCommandMatcher` (pure function) + whitelist + normalization + tests | `lib/core/local_commands/local_command_matcher.dart` (new); `test/core/local_commands/local_command_matcher_test.dart` (new). |
| **T4** | Wire matcher into `SyncWorker._processNext`: replayLast / bufferEmpty / passthrough branches; toast + haptic via existing services injected from `core/session_control/`; tests for all three branches | `lib/features/api_sync/sync_worker.dart` (edit); `lib/features/api_sync/sync_provider.dart` (edit, wire deps); `test/features/api_sync/sync_worker_test.dart` (extend). |
| **T5** | Wire buffer-clear to `SessionIdCoordinator.resetSession` and to `adoptConversationId`-on-change; tests | `lib/core/session_control/session_id_coordinator.dart` (edit, add reset listener hook if not already exposed); buffer subscription in `tts_provider.dart`; tests in `test/core/session_control/`. |

T4 from the original draft ("powtórz drugą ostatnią" / "powtórz
przedostatnią" → index 1) is moved to **Non-goals** (see below).

## Acceptance criteria

- A whitelisted utterance with a non-empty buffer triggers a TTS replay
  with **the same text and `languageCode` as the original utterance**,
  producing content-equivalent speech with **no LLM call and no network
  round-trip**. Byte-identical audio is *not* an acceptance criterion: the
  buffer stores `(text, languageCode)` only, and `flutter_tts` re-synthesises
  on the platform engine on each call — voice cache, prosody, and platform
  engine state can vary between two invocations, so byte-identity is
  unachievable and not promised.
- A whitelisted utterance with an empty buffer shows the
  "Brak wcześniejszej odpowiedzi" toast and falls through to the backend.
- A non-whitelisted utterance (including "Powtórz, żeby coś przerwało.")
  is sent to the backend unchanged. The matcher does not mis-trigger on
  the origin [42] case.
- `_handleReply`'s post-reply behavior (TTS speak, `onAgentReply`,
  `adoptConversationId`, session-control dispatch) is unchanged.
- Buffer is cleared on `resetSession()` and on `adoptConversationId` of a
  *different* conversation; not cleared on `stop_recording`; not persisted
  across app restarts.
- Internal replay latency — measured from "matcher returns `replayLast`"
  to "`ttsService.speak` returns" (i.e. dispatch overhead only, excluding
  the platform engine's first-frame audio) — is comparable to a normal
  `_handleReply` `speak` call. We do not promise a hard millisecond bound:
  iOS `AVSpeechSynthesizer`'s first call after backgrounding routinely
  exceeds 200 ms, and any number we put here would be a measurement of
  the OS, not of our code. The user-visible win is "no LLM, no network"
  — that is the contract.

## Buffer size

`n = 1`. T4 (replay second-to-last) is moved to Non-goals; without it,
nothing in v1 needs more than the most recent entry. Keeping `n = 1`
makes the data structure trivially correct and trivially testable. If
production telemetry later motivates "powtórz przedostatnią", we revisit
the size and the matcher whitelist together in a follow-up proposal.

## Affected Mutation Points

New files:

- `lib/core/tts/tts_reply_buffer.dart`
- `lib/core/tts/buffering_tts_service.dart`
- `lib/core/local_commands/local_command_matcher.dart`
- `test/core/tts/tts_reply_buffer_test.dart`
- `test/core/tts/buffering_tts_service_test.dart`
- `test/core/local_commands/local_command_matcher_test.dart`

Edited files:

- `lib/core/tts/tts_provider.dart` — wrap `TtsService` provider with
  `BufferingTtsService`; expose `ttsReplyBufferProvider`.
- `lib/core/session_control/session_id_coordinator.dart` — add a reset
  listener hook (if one is not already exposed) so the buffer can subscribe
  without importing features.
- `lib/features/api_sync/sync_worker.dart` — inject `LocalCommandMatcher`,
  `TtsReplyBuffer`, `Toaster`, `HapticService`; add the three-branch
  pre-flight check in `_processNext` before `apiClient.post`.
- `lib/features/api_sync/sync_provider.dart` — wire new dependencies into
  `SyncWorker`.
- Existing tests in `test/features/api_sync/sync_worker_test.dart` —
  extend.

## Test Impact / Verification

Unit tests:

- `local_command_matcher_test.dart`:
  - Each whitelist entry, lowercased / with trailing `. , ? !` /
    surrounding whitespace → `replayLast` (with non-empty buffer) /
    `bufferEmpty` (with empty buffer).
  - Negative cases that must return `passthrough`:
    - "Powtórz, żeby coś przerwało." (the origin [42] case),
    - "Powtórz ostatnią wygenerowaną wiadomość.",
    - "powtórz, że X",
    - "Repeat please tell me more",
    - "" / "   " / pure punctuation.
- `tts_reply_buffer_test.dart`: write-then-read, overflow eviction,
  `clear()` empties, `last()` on empty returns `null`.
- `buffering_tts_service_test.dart`: successful `speak` writes to buffer
  with the exact `(text, languageCode)` passed in; thrown `speak` does not
  write; `stop` does not write.
- `sync_worker_test.dart` (extended):
  - Whitelisted utterance + non-empty buffer → no `apiClient.post` call,
    `ttsService.stop` then `ttsService.speak` invoked with buffered
    `(text, languageCode)`, toast shown, haptic fired, queue item marked
    consumed.
  - Whitelisted utterance + empty buffer → toast shown, falls through to
    `apiClient.post`.
  - Non-whitelisted utterance → matcher returns `passthrough`, `_handleReply`
    runs unchanged.
- Reset / adopt:
  - `resetSession()` clears the buffer.
  - `adoptConversationId(newId)` with `newId != currentTag` clears.
  - `adoptConversationId(sameId)` does not clear.
  - `stop_recording` signal does not clear.

Manual verification (device-only, called out as such per CLAUDE.md):

- iOS + Android, foreground and locked-screen: speak a reply, then say
  "powtórz" → hear the same text. No network traffic during replay
  (verify via Charles / Android log).
- Origin transcript replay: utter "Powtórz, żeby coś przerwało." → does
  *not* trigger local replay; goes to backend.

## Are We Solving the Right Problem?

Alternatives considered and ruled out:

- **Server-side replay endpoint.** Adds a backend round-trip (defeats the
  latency goal), requires a new API contract, and re-introduces drift if
  the server re-renders. Rejected.
- **Persisted buffer across app restarts.** Conversation context is
  ephemeral; replaying yesterday's last reply after an app restart is
  surprising rather than helpful. Rejected.
- **Substring / regex matcher.** Mis-triggers on the origin [42]
  transcript and on any "powtórz, że X" turn. Rejected in favor of the
  exact-whole-utterance whitelist; we prefer false negatives over false
  positives.
- **Capture buffer at every `ttsService.speak` callsite.** Today there is
  only one (`_handleReply`), but a decorator at the `TtsService` instance
  level would also capture future error/feedback speak calls. Rejected:
  the buffer must contain only successful agent replies, never error
  utterances. Wrap the decorator only around the instance used by
  `_handleReply`.
- **n ≥ 2 buffer to support "przedostatnią".** No production data
  supports demand; doubles the test surface; mis-indexing risk. Deferred
  to a follow-up if telemetry justifies it.

## Risk

Low — Tier 0. Voice-agent only. No backend contract change. No schema
change. The matcher is whitelist-only, so the failure mode for an
unrecognised replay phrase is the existing behavior (LLM round-trip).
The capture path is additive and isolated to a decorator wrapping a
single existing instance.

## Effort

5 PRs in voice-agent (T1–T5), each small and behavior-preserving up to
the wiring step.

## Non-goals

- No server-side replay endpoint.
- No replay across devices.
- No "show me the last reply text" — that is the chat history screen.
- **No "powtórz drugą ostatnią" / "powtórz przedostatnią" support in v1.**
  Originally proposed as T4; demoted because it requires a richer phrase
  set, indexing semantics, an ambiguity-fallback toast, and a buffer of
  size ≥ 2. Revisit only if production telemetry shows the request.
- No persisted buffer across app restarts.
