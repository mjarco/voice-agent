# Proposal 032 — New Conversation Button

## Status: Implemented

## Origin

Conversation 2026-04-22. The user decided the "new conversation" action
belongs in the mobile client (voice-agent), not in the web UI. Rationale:
the primary flow is voice-first, on mobile — the web UI is a secondary view.

## Prerequisites

- 014-recording-mode-overhaul — recording lifecycle and gesture table
- 024-chat-screen — chat UI with conversation context
- 025-shared-api-layer — shared API client
- **029-honor-session-control-signals — provides `SessionIdCoordinator` in
  `core/session_control/`**. P032 reuses this coordinator for the manual
  reset. Without it, there is nothing to clear — neither the recording
  nor the api_sync feature currently maintains a local `conversation_id`.
  The backend assigns conversations via device-id-based stitching with a
  10-minute gap heuristic. P029's `SessionIdCoordinator` is the first
  client-side conversation identity.

P014, P024, P025 are implemented. **P029 is draft — this proposal depends
on P029 shipping first** (or at minimum the `SessionIdCoordinator` class
from P029 T1 being merged).

**Cross-project relationship:** personal-agent P049 (session-control-signals)
and voice-agent P029 define the automated conversation reset triggered by the
backend. This proposal covers the manual, user-initiated reset — a
complementary mechanism.

## Scope

- Risk: Low — UI-only change with local state reset; no API contract change,
  no storage schema change, no platform behavior change
- Layers: `features/recording/presentation/` (recording screen widget),
  `features/chat/presentation/` (chat screen widget),
  `core/session_control/` (reuses P029's `SessionIdCoordinator`)
- Expected PRs: 1

## Problem Statement

Currently the user cannot start a fresh conversation from the mobile app
without stopping and restarting the hands-free session. The backend's
10-minute gap heuristic handles session rollover passively, but:

- The user must wait 10 minutes of silence for an automatic rollover, or
- Tap stop, wait, tap start — friction that breaks the voice-first promise.

A single-tap "new conversation" action would let the user explicitly close
the current context and start fresh.

## Proposed Solution

### Recording Screen

An icon button (refresh icon) in the AppBar, alongside the existing history
button. Tap calls `sessionIdCoordinator.resetSession()`, shows a "New
conversation" toast and a light haptic.

**State guard:** The button is disabled when:
- `RecordingState` is `RecordingActive` or `RecordingTranscribing` (manual
  recording in progress)
- `HandsFreeSessionState` is `HandsFreeCapturing` or `HandsFreeStopping`
  (VAD segment being captured or written)

In all other states (`HandsFreeIdle`, `HandsFreeListening`,
`HandsFreeWithBacklog`, `RecordingIdle`), the button is active.

Reference: P014 gesture guard table for canonical state combinations.

### Chat Screen

From within a thread: navigate to `/chat` (conversations list) and let the
user tap the existing "+" button to start a new conversation. This reuses
the flow already established by P024's `ConversationsScreen`.

Adding a separate "new conversation" action inside a thread is deferred —
the recording screen button covers the primary voice-first use case, and
the chat screen already has the "+" flow.

### State Reset

On tap, call `sessionIdCoordinator.resetSession()` from P029's
`core/session_control/` package. This clears the local `conversation_id`
— the backend's existing device-id-based stitching handles the new
conversation on the server side.

Keep the hands-free session alive (mic stays open, VAD stays running).
Only the conversation identity changes, not the audio session.

### Toast and Haptic

If P029's `Toaster` and `HapticService` are available (they live in
`core/session_control/`), reuse them. The toast text is "New conversation",
matching P029's `reset_session` signal feedback.

## Acceptance Criteria

1. Tapping the "new conversation" button on the recording screen while in
   idle/listening state calls `SessionIdCoordinator.resetSession()` and
   shows a "New conversation" toast with a light haptic.
2. The button is disabled (not tappable, visually dimmed) when
   `RecordingState` is `RecordingActive` or `RecordingTranscribing`, or
   when `HandsFreeSessionState` is `HandsFreeCapturing` or
   `HandsFreeStopping`.
3. The hands-free session (mic, VAD, foreground service) remains alive
   after the reset — only the conversation identity changes.
4. No cross-feature imports. The button uses only `core/session_control/`
   providers.
5. `flutter analyze` passes with zero issues. `flutter test` passes.

## Tasks

| # | Task | Layer | Notes |
|---|------|-------|-------|
| T1 | Add "new conversation" icon button to RecordingScreen AppBar. Wire to `SessionIdCoordinator.resetSession()` via provider. Disable during active recording/capturing states. Show toast + haptic via P029's abstractions. Widget test for button state and tap behavior. | features/recording/presentation | Depends on P029 T1. |
| T2 | (Optional) If chat-screen "new conversation" action is needed beyond the existing "+" flow, add an AppBar action to ThreadScreen that navigates to `/chat` (conversations list). | features/chat/presentation | Low priority. |

## Dependencies

| Dependency | Status | Blocking? |
|---|---|---|
| 014-recording-mode-overhaul | Implemented | No |
| 024-chat-screen | Implemented | No |
| **029-honor-session-control-signals (T1)** | **Draft** | **Yes — provides SessionIdCoordinator, Toaster, HapticService** |
| personal-agent P049 | Draft | Not blocking — independent mechanism |

## When to Address

After P029 T1 (core skeleton) is merged. At that point this becomes a
trivial UI addition on top of the existing `SessionIdCoordinator`.

## Related

- P000-backlog entry "New conversation button in voice agent UI"
- 029-honor-session-control-signals (automated reset, shared coordinator)
- 014-recording-mode-overhaul (gesture table, state guards)
- 024-chat-screen (ConversationsScreen "+" flow)
