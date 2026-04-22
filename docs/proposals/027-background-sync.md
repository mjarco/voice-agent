# Proposal 027 — Background Sync While Hands-Free Session Active

## Status: Implemented (PRs #236, #240, #241)

## Prerequisites

- P026 (Remove Wake Word, Rewire FG Service) — FG service start/stop is tied
  to hands-free session lifecycle; VAD + STT + local enqueue work in the
  background. Sync is still gated to foreground.

## Scope
- Risk: Medium — amends ADR-NET-002 (foreground-only sync); changes the
  predicate used by `SyncWorker._drain()`
- Layers: `features/api_sync`, `core/providers`
- Expected PRs: 2

## Problem Statement

After P026 a hands-free session continues running while the phone is locked:
Silero VAD captures speech, Groq STT transcribes it, and the transcript is
saved to the local `sync_queue`. But `SyncWorker._drain()` early-returns when
`isAppForegrounded()` returns false (`sync_worker.dart:100`, per ADR-NET-002).
Transcripts pile up locally and only flush to personal-agent when the user
unlocks the phone.

Observed (iOS 26.3, iPhone 12 Pro, after P026 + AudioSessionBridge fix):

> Locking the phone during an active hands-free session. Speak a sentence.
> Unlock. Only after unlock do I see the transcript arriving at
> personal-agent, and the reply reads back in-app.

Desired: transcripts flow to personal-agent within the normal ~5-second sync
cadence regardless of app visibility, as long as the user has started a
hands-free session.

## Are We Solving the Right Problem?

**Root cause:** ADR-NET-002 ("foreground-only sync") was written for the
original use case — manual tap-to-record, app always foregrounded during
recording. P026 made hands-free sessions continue in the background. The
sync gate should follow the session, not the app's visibility state.

**Alternatives dismissed:**
- *Keep sync gated, add a "flush on unlock" animation.* Masks the gap rather
  than fixing it; defeats the "phone in pocket" flow.
- *Gate behind a new user-facing toggle.* The setting's semantics collapse
  into "do you want your hands-free session to work end-to-end?" — busywork
  with no real user choice.
- *Event-driven sync (on enqueue).* Larger refactor. The 5 s cadence is
  acceptable for V1; event-driven is a separate future improvement.

**Smallest change:** Replace the `isAppForegrounded()` gate in `_drain()`
with a predicate that also considers whether a hands-free session is active,
and amend ADR-NET-002 with the carve-out.

## Goals

- Transcripts captured during a hands-free session reach personal-agent
  within one sync cycle (~5 s) regardless of app visibility.
- Sync behavior when no session is active is unchanged from ADR-NET-002
  semantics — manual recording, agenda, and general app usage are not
  affected.

## Non-Goals

- TTS playback in background. Scope of P028.
- Android `FOREGROUND_SERVICE_MEDIA_PLAYBACK` permission. Scope of P028.
- General-purpose background sync (e.g. sync without any active session).
- Cellular vs. Wi-Fi controls, data-saver toggle.
- Event-driven sync / lower latency than the current 5 s timer.
- Changes to retry, backoff, or failure semantics.

## User-Visible Changes

After P027 (but before P028), with a hands-free session active and the phone
locked:

- The user speaks → a transcript arrives at personal-agent within ~5 s →
  the agent reply appears in `latestAgentReplyProvider` and is visible when
  the user unlocks the app.
- TTS playback of the reply still requires foreground (P028 lifts that
  restriction for Android; iOS already supports it via `UIBackgroundModes:
  audio` but without sync there was nothing to play).

No new settings, no new UI.

## Solution Design

### Scope the sync gate to hands-free lifecycle

Today `SyncWorker._drain()` short-circuits on `!isAppForegrounded()`. Change
the predicate to:

```
shouldProcessQueue() =>
    isAppForegrounded() || isHandsFreeSessionActive()
```

"Hands-free session active" means `HandsFreeController.state` is any of the
mic-holding variants (`HandsFreeListening`, `HandsFreeCapturing`,
`HandsFreeStopping`, `HandsFreeWithBacklog`). `HandsFreeIdle` and
`HandsFreeSessionError` both mean inactive — matching the FG service
predicate already established in P026's ADR-PLATFORM-006.

Expose the predicate via a new core-layer `StateProvider<bool>` —
`sessionActiveProvider` — written by `HandsFreeController` on state
transitions and read by `SyncWorker` through its constructor callback.
Placing it in `core/providers/` avoids the CLAUDE.md dependency-rule
violation a derived provider would trigger (core must not import from
features). This mirrors the existing `appForegroundedProvider` pattern.

`SyncWorker` takes a `shouldProcessQueue` callback that reads both
`appForegroundedProvider` and `sessionActiveProvider`.

### Kick on session-active transition

Without a kick, worst-case latency for the first utterance in a session is
~5 s of capture + up to ~5 s until the next sync tick = up to ~10 s. Add a
public `SyncWorker.kickDrain()` method (immediate drain, returns early if a
drain is already in progress) and wire a `ref.listen(sessionActiveProvider,
...)` inside `sync_provider.dart` that calls `kickDrain()` on the
idle→active transition. First-utterance end-to-end latency becomes
"capture + one HTTP round trip." Subsequent utterances within the same
session rely on the existing 5 s timer.

Keeping the listener inside `sync_provider.dart` preserves one-directional
coupling — `features/recording` does not depend on `features/api_sync`.

### Guard TTS to foreground until P028 ships

`_handleReply()` at `sync_worker.dart:167` calls
`unawaited(ttsService.speak(...))`. Post-P027, `_drain()` also runs while
backgrounded, so `_handleReply()` runs backgrounded too. Until P028 adds
`FOREGROUND_SERVICE_MEDIA_PLAYBACK` on Android, backgrounded TTS may fail
silently or throw on Android 14+. Add an explicit foreground gate on the
TTS branch inside `_handleReply()` (without gating storage writes or
`latestAgentReplyProvider`):

```
if (isAppForegrounded()) {
    unawaited(ttsService.speak(message, languageCode: language));
}
// else: reply is stored; user hears nothing until foreground, sees it on return
```

P028 removes this gate. Document the sequencing in both proposals.

### ADR-NET-002 amendment

Current: "Sync runs only while the app is in the foreground."
After P027: "Sync runs while the app is in the foreground OR while a
hands-free session is active." The ADR's motivation (no surprise background
data usage) is preserved — the user explicitly started the session.

## Affected Mutation Points

**Needs change:**
- `lib/core/providers/session_active_provider.dart` (NEW) — a
  `StateProvider<bool>` defaulting to `false`, written by
  `HandsFreeController` on lifecycle transitions. Mirrors the
  `appForegroundedProvider` pattern to keep `core/providers/` free of
  `features/` imports.
- `lib/features/recording/presentation/hands_free_controller.dart`:
  - `startSession()` (after guards pass, before `bg.startService()`): set
    `_ref.read(sessionActiveProvider.notifier).state = true`.
  - `stopSession()` (start of method): set `sessionActiveProvider` to
    `false` before the idle guard returns.
  - `_terminateWithError()`: set `sessionActiveProvider` to `false` before
    the service stop.
- `lib/features/api_sync/sync_worker.dart:22,33` — swap the
  `isAppForegrounded` constructor param/field for `shouldProcessQueue`.
- `lib/features/api_sync/sync_worker.dart:100` — replace
  `if (!isAppForegrounded()) return;` with `if (!shouldProcessQueue()) return;`.
- `lib/features/api_sync/sync_worker.dart` — add public `Future<void>
  kickDrain()` that calls `_drain()` if no drain is in progress (idempotent
  with existing `_draining` flag).
- `lib/features/api_sync/sync_worker.dart:167` — foreground-gate the TTS
  call inside `_handleReply()` until P028 ships. Storage writes and
  `latestAgentReplyProvider` updates remain unconditional.
- `lib/features/api_sync/sync_provider.dart:30` — wire the
  `shouldProcessQueue` callback to read both `appForegroundedProvider` and
  `sessionActiveProvider`. Also add a `ref.listen(sessionActiveProvider,
  ...)` that calls `syncWorker.kickDrain()` on idle→active edge.
- `docs/decisions/ADR-NET-002-*.md` — amend Decision section with the
  "or while a hands-free session is active" carve-out. Note that TTS
  playback during backgrounded drain is explicitly gated until P028.

**No change needed:**
- `handsFreeControllerProvider` itself — the StateProvider pattern means
  `HandsFreeController` writes to the separate `sessionActiveProvider`
  directly; no derived provider.
- Connectivity / retry / backoff logic in `SyncWorker`.
- `flutter_foreground_task_service.dart` — FG service lifecycle is unchanged.

## Tasks

| # | Task | Layer | Notes |
|---|------|-------|-------|
| T1 | Add `lib/core/providers/session_active_provider.dart` as a `StateProvider<bool>` defaulting to `false`. Wire `HandsFreeController.startSession()/stopSession()/_terminateWithError()` to write it. Extend `hands_free_controller_test.dart` with transition tests verifying the provider value at each edge. | core/providers, features/recording, test | ~60 LOC |
| T2 | Swap `SyncWorker.isAppForegrounded` callback for `shouldProcessQueue`. Add `SyncWorker.kickDrain()` public method (idempotent via existing `_draining` flag). Foreground-gate the TTS call in `_handleReply()`. In `sync_provider.dart`, wire `shouldProcessQueue` to read both flags, and `ref.listen(sessionActiveProvider, ...)` to call `kickDrain()` on idle→active edge. Rename the existing `foreground gating` test group to cover the 2D matrix `(foregrounded, sessionActive) → shouldProcess` (4 cases). Amend **ADR-NET-002** — Decision + Rationale + Consequences per ADR Impact section below. Amend **ADR-PLATFORM-006** — one-line Consequences cross-reference. | features/api_sync, test, docs | Single PR. |

## Test Impact / Verification

**Existing tests affected:**
- `sync_worker_test.dart` — any test asserting "sync skipped when
  backgrounded" needs a two-dimensional matrix now:
  `(foregrounded, sessionActive) → shouldProcess`. Existing foreground cases
  stay; add two background cases.

**New tests:**
- Provider test for `sessionActiveProvider` covering the 6
  `HandsFreeSessionState` variants.
- `sync_worker_test.dart`:
  - `(background, sessionActive)` → processes queue
  - `(background, sessionIdle)` → skips queue
  - `(foreground, sessionIdle)` → processes queue (regression)

**Manual verification:**
- iOS, release build, iPhone 12 Pro: start hands-free session, lock screen,
  speak, observe personal-agent logs receiving the transcript within 10 s.
  Unlock — no "burst" flush, because it already happened.
- iOS, same setup: enable airplane mode mid-session, speak (transcript
  enqueues but fails to sync). Disable airplane mode with screen still
  locked. Verify transcript reaches personal-agent within the next tick or
  kick. (Acceptable if connectivity-stream delays push this to ~5 s.)
- Android (when device available): same flow on Android 14+ device. Verify
  no `ForegroundServiceTypeException` in logcat. (TTS remains foreground-only
  in P027; P028 adds Android mediaPlayback.)

**Commands:** `flutter analyze && flutter test`.

## Acceptance Criteria

1. With a hands-free session active and the phone locked, a spoken utterance
   is transcribed locally and the transcript reaches personal-agent within
   10 s (first utterance after session start, thanks to `kickDrain()`).
2. Subsequent utterances within the same session reach personal-agent within
   one 5 s sync cycle.
3. With NO session active and the app backgrounded, sync remains gated —
   existing ADR-NET-002 behavior for all non-hands-free code paths.
4. TTS playback during a backgrounded drain is skipped (gated to foreground
   until P028). Reply text is still stored in `latestAgentReplyProvider`
   and visible on return to foreground.
5. Re-entering a hands-free session after a previous one ended does not
   reprocess previously-synced items (regression check).
6. `flutter analyze` and `flutter test` both pass.
7. ADR-NET-002 status field reflects the amendment ("Amended in P027").

## Risks

| Risk | Mitigation |
|------|------------|
| Cellular data usage while backgrounded during long hands-free sessions | Acceptable — user opted into the session. Existing 5 s cadence rate-limits. |
| **Privacy expectation gap** — user locks phone during sensitive dictation, assumes data transmission stops, but the session keeps syncing | Document in release notes: "while a hands-free session is active, transcripts are sent to your personal-agent API regardless of screen state. Stop the session (switch tab off Record, or force-close) to pause transmission." |
| Battery drain | Already present post-P026 for VAD; P027 adds periodic network calls on top. Tab-switch and manual stop end the session and restore battery behavior. |
| Android OEM-specific FG service killers (Xiaomi, OPPO) may kill the service despite correct types | Out of scope — Android ecosystem problem that existed pre-P027. Documented. |
| `sessionActiveProvider` writes fire too often and generate spurious drain attempts | `kickDrain()` is idempotent (short-circuits when `_draining == true`). State writes happen at 3 fixed controller methods; the listen fires only on `true ← false` edge. |
| **Connectivity stream may not deliver events reliably when the app is backgrounded** (iOS drops Wi-Fi, OS delays delivery) | Existing pause/resume coordination in `SyncWorker` is unchanged. Document as known limitation: if connectivity is lost while backgrounded and recovers before the next 5 s tick, `kickDrain()` is not called on recovery. The next tick catches it. If this becomes a real issue, a follow-up can wire connectivity changes to `kickDrain()` via `sync_provider.dart`. |
| Session transitions through `HandsFreeStopping` before `HandsFreeIdle` — predicate still true during stopping | Correct behavior — drain the queue during the ~500ms stopping window. Document. |
| In-flight `kickDrain()` when session goes active→idle mid-drain | Drain continues to completion. Individual HTTP requests already have independent state; the `_draining` flag resets naturally when the current iteration finishes. If `shouldProcessQueue()` returns false on the next iteration inside `_drain()`, the loop exits. No partial state corruption. |

## Known Compromises and Follow-Up Direction

- **Sync cadence is still 5 s.** A user speaking immediately at session
  start may see the reply up to ~5 s after the ideal moment. Event-driven
  sync (on enqueue) is a natural follow-up but not required for V1.
- **Only hands-free sessions get background sync.** Any other long-running
  user-initiated background activity that needs sync would need its own
  carve-out — OK, there is no such other case today.

## ADR Impact

**Amends ADR-NET-002 (foreground-only sync).** Three sections need edits, not
just the Decision line:

1. **Decision** — widen the predicate to "foreground OR session active,"
   name `SyncWorker.kickDrain()` as the canonical event-triggered drain
   entry point for future triggers.
2. **Rationale** — the current ADR cites "iOS severely restricts background
   execution (~30 seconds, requires BGTaskScheduler)". Rewrite: P026
   eliminated that restriction for hands-free sessions by tying the
   foreground service + `playAndRecord` audio session (ADR-AUDIO-009,
   ADR-PLATFORM-006) to session lifecycle. Sync riding on that keepalive
   has the same survivability as capture itself.
3. **Consequences** — add that sync runs during background hands-free
   sessions, that TTS is temporarily foreground-gated until P028, and that
   `latestAgentReplyProvider` is always populated so the user sees the
   reply on return to foreground regardless of whether TTS plays.

**Amends ADR-PLATFORM-006 (controller-owned FG service lifecycle).** One-
line cross-reference in Consequences: "P027 reuses this explicit-boundary
pattern for `sessionActiveProvider` writes at the same three call sites
(`startSession`, `stopSession`, `_terminateWithError`)." No Decision change.

**No new ADR.** `kickDrain()` is named inside ADR-NET-002 as the canonical
pattern for future event-triggered drains; if a second trigger lands
(connectivity-up being the most likely), it reuses the method without a
new ADR.
