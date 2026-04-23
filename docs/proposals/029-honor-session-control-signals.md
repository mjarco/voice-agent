# Proposal 029 — Honor Session-Control Signals from Backend Metadata

## Status: Implemented

## Origin

Conversation 2026-04-22. After a farewell or an explicit "start a new
session" ask, the backend agent will know the conversation is over but there
is currently no channel to tell voice-agent to release the mic or swap to a
new session. voice-agent must learn to honour two new signals the backend
will emit.

## Prerequisites

- 015-tts-response-playback and 024-chat-screen — the existing chat reply
  consumption path
- 025-shared-api-layer — the shared response model that will carry the new
  metadata fields
- 014-recording-mode-overhaul — recording lifecycle the signals will control

All three are implemented.

**Cross-project pair:** personal-agent proposal P049
(`session-control-signals.md`) defines the server contract. Both must ship
together.

## Scope

- Risk: Medium — signals alter microphone and session lifecycle from a
  remote source; silent mishandling confuses the user
- Layers: core/network (response parsing), core/session_control (new
  dispatcher + bus; see architecture caveat below), features/api_sync
  (wires sync worker into the bus), features/recording (session + recorder
  handlers)
- Expected PRs: 1

## Problem Statement

Today the voice-agent is the sole authority on session and recorder state.
The backend can detect end-of-conversation and new-session intents, but has
no way to act on them. Consequences:

- After a farewell, the recorder keeps listening; ambient noise becomes
  input for the same conversation.
- Voice-only requests like "zacznij nową sesję" cannot be fulfilled — the
  user must tap the mobile UI.
- No hook exists for future proactive agent behaviour (e.g. agent-initiated
  conversation close after extended idle).

## Are We Solving the Right Problem?

**Root cause:** The voice-agent process is the sole authority over both
`conversation_id` and the microphone/VAD session lifecycle. The backend
sends a text reply that the client plays through TTS; nothing else travels
back. There is no declarative channel for the backend to advise the client
to release the mic or open a fresh conversation. The `ApiClient.post()`
response body contains only `message` and `language`
(`lib/features/api_sync/sync_worker.dart:184-201`); `SyncWorker._handleReply()`
ignores anything else. P025 extends the shared domain models but does not
yet carry session-control metadata.

**Alternatives dismissed:**

- *Client-side heuristic for farewell detection.* Rejected. Requires the
  client to re-run NLP (or string matching) on either user input or agent
  reply. That logic already lives on the backend as a deterministic
  post-processor inside `chat.Service.Chat` (P049 §Classifier
  Responsibility — `DefaultSessionControlEmitter`, a server-side rule-based
  emitter; **not** a ChatAgent prompt-level classifier, the LLM is not
  involved). Duplicating a server-side classifier on a mobile device wastes
  CPU, battery, and introduces a second place for farewell rules to drift.
- *User-only control (keep status quo; require the user to stop recording
  or tap "new session").* Rejected. Breaks the hands-free contract set by
  P019/P026/P028 — the user's phone is in their pocket. Forcing a tap to
  close the session defeats the reason voice mode exists.
- *Separate websocket/long-poll channel for out-of-band control messages.*
  Rejected. Adds a second network channel, a second auth surface, a second
  reconnect policy, and a race where a control message can arrive before
  the reply it is bound to. The natural carrier is the already-round-tripping
  reply — one request, one response, signals attached to the same frame.

**Smallest change:** extend the existing chat reply response body with two
optional boolean fields (`reset_session`, `stop_recording`), parse them in
the response-mapping layer, dispatch them after TTS completes to the
`HandsFreeController` and to a new session-id coordinator. No new transport,
no new auth surface, no new backend endpoint.

## Goals

- Parse the `session_control` object (with boolean `reset_session` and
  `stop_recording` keys) from the chat reply response body. In v1 the
  primary carrier is `POST /api/v1/voice/transcript` (the path
  `SyncWorker` uses today); the same `session_control` envelope is also
  emitted by `/api/v1/chat` blocking and `/api/v1/chat/stream` SSE
  `event:result` frames per P049, so the shared parser works for the
  `features/chat` `ThreadNotifier` forward-compat path too.
- When `stop_recording` is true: tear down the hands-free session after TTS
  finishes; leave the app in an idle state that requires a user gesture
  to re-arm.
- When `reset_session` is true: close the current conversation, generate a
  fresh `conversation_id` on next send, keep the hands-free session alive
  (no mic restart).
- When both are true: apply `reset_session` first, then `stop_recording`
  against the new (empty) session.
- When neither is present (or both false): behave exactly as today.
- Confirm the applied signal to the user with a toast and a short haptic so
  the state change is observable without looking at the screen.

## Non-goals

- No backend protocol change beyond the two optional booleans defined by
  P049 — no semantic version bump, no new envelope, no new endpoint.
- No telemetry ping back to personal-agent confirming the signal was
  honoured (deferred; v1 writes only local debug logs).
- No user-visible toggle to ignore signals ("never auto-stop"). If users
  report friction after ship, add it in a follow-up — the setting
  framework already exists (P015 `ttsEnabled`).
- No changes to VAD, STT, Groq, or the transcript sync queue behaviour.
- No scheduling of signals ("stop recording in 30 seconds"). Signals apply
  once, immediately after the current TTS utterance finishes or a bounded
  timeout fires.
- No queueing or replay of signals across app restarts — signals are
  consumed in-memory and discarded.

## User-Visible Changes

A user holding a hands-free conversation with the backend will observe:

- After saying "goodbye" (or any farewell the backend classifies as
  end-of-conversation), the agent replies with a spoken farewell, then the
  hands-free green mic indicator disappears and a short toast
  "Session ended" plus a single haptic tap confirms the mic has been
  released. To resume, the user must tap the mic button — identical to the
  post-error recovery path already established by P014.
- After saying "start a new session" (or any intent the backend classifies
  as new-conversation), the agent replies with a confirmation ("Starting a
  new conversation."), the toast reads "New conversation", the haptic fires,
  the green mic indicator stays on, and the next utterance is tagged with a
  fresh `conversation_id` invisibly to the user.
- After the rare double-signal (both booleans true), the user hears the
  farewell, sees "New conversation" then "Session ended" in rapid
  succession (or a single consolidated toast — see Solution Design), the
  mic releases, and the next session opens a fresh conversation.

No new screens, no new settings, no new icons. The only new UI surface is
two short transient toasts and two short haptic taps.

## Solution Design

### Architecture caveat (dependency rule)

`voice-agent/CLAUDE.md` is explicit: **features cannot import other
features**. The signals originate in `features/api_sync` (`SyncWorker`)
and, later, `features/chat` (`ThreadNotifier`, P024). They must act on
`features/recording` (`HandsFreeController`). A direct import from one
feature to another is a blocker.

We resolve this by placing the dispatcher and the signal bus in `core/`.
`features/api_sync` and `features/chat` *produce* signals into a core bus;
`features/recording` *subscribes* to the same bus via a Riverpod provider.
Neither importer references the other. This follows the same pattern P015
used for `TtsService` — a shared concern promoted to `core/` so multiple
features can consume it without cross-feature imports.

### Directory layout (new + changed)

```
lib/core/
  session_control/
    session_control_signal.dart       — new: Dart model + fromMap
    session_control_dispatcher.dart   — new: ordering + TTS-wait + toast/haptic
    session_control_provider.dart     — new: Riverpod providers (dispatcher + bus)

lib/core/network/
  api_client.dart                     — unchanged (body is already forwarded)

lib/features/api_sync/
  sync_worker.dart                    — _handleReply parses session_control and
                                         forwards to SessionControlDispatcher

lib/features/recording/
  presentation/
    hands_free_controller.dart        — new handlers exposed (see below)
```

The `core/session_control/` directory is new and mirrors the structure of
`core/tts/` introduced by P015. The dispatcher lives in `core/`, not in
`features/api_sync/`, because P024's `ThreadNotifier` also needs to produce
these signals once the /chat/stream path carries them. Placing the
dispatcher in `features/api_sync/` would force `features/chat/` to import
from another feature.

### Response model extension

The signals arrive in the JSON body of the transcript-sync response (v1
primary carrier: `POST /api/v1/voice/transcript`) and, via the shared
parser, in the SSE `result` event carried by P024 (forward-compat). The
extension lives in `core/session_control/session_control_signal.dart`:

- `SessionControlSignal` — immutable value object with two non-nullable
  fields: `resetSession: bool`, `stopRecording: bool`; convenience
  `isNoop` getter (true when both booleans are false).
- `SessionControlSignal.fromBody(Map<String, dynamic> body)` — reads the
  `session_control` key. Returns `null` only when the key is **absent**
  or the value is **not a `Map`**. Returns a non-null
  `SessionControlSignal` whenever the envelope is present as a map — even
  if both booleans resolve to false. This distinguishes "field absent"
  (null, backend emitted nothing) from "field present but no-op"
  (non-null signal with `isNoop == true`, backend emitted an empty
  envelope) for audit/debug traceability. Parses strictly `value == true`
  (no truthy-ness tricks; missing keys → false); unknown keys are ignored
  (forward-compat: a future third boolean keeps this call non-null even
  when the current two are false).

**Why `core/session_control/` and not `core/models/`?** The signal type is
inseparable from the dispatcher — a value object that exists solely to
drive `SessionControlDispatcher`. `core/models/` is reserved for
persistence-layer DTOs (`Transcript`, `SyncQueueItem`, `Conversation`,
etc.) that match a wire schema and round-trip through SQLite. Grouping the
signal type with its dispatcher mirrors the layout of `core/tts/`
(`TtsService` + `FlutterTtsService` + `tts_provider`).

The field naming uses camelCase in Dart and maps to snake_case on the
wire, consistent with every other DTO (`RecordType`, `ConversationEvent`,
etc.). The wire field names (`session_control`, `reset_session`,
`stop_recording`) are exactly those defined by P049.

### Dispatcher

The dispatcher lives in
`lib/core/session_control/session_control_dispatcher.dart`.

**Contract (signatures only, bodies are implementation):**

- `SessionControlDispatcher` constructor takes: `TtsService`,
  `HandsFreeControlPort`, `SessionIdCoordinator`, `Toaster`,
  `HapticService`, and an optional `ttsTimeout: Duration` (default 3s,
  matches P049 §5 "3 seconds, whichever comes first").
- `Future<void> dispatch(SessionControlSignal signal)` — single entry
  point. When `signal.isNoop` is true, the dispatcher returns early
  without waiting for TTS and without firing toast/haptic (no-op
  envelope is recorded only via `debugPrint` at the entry seam for
  audit).
- Concurrent `dispatch` calls are serialised through an internal
  `Future` chain: a second `dispatch` invocation while a first is in
  flight queues and runs only after the first settles (including its
  `_waitForTtsToFinish` stage). This prevents duplicate toast/haptic
  when the backend emits back-to-back replies each carrying a signal
  within a single TTS window. Worst case: the second signal observes a
  ~3s delay while the first's TTS wait plays out.

**Ordering guarantee (canonical — matches P049 §5 byte-for-byte):** when
both signals are true, the client applies them as:

1. Wait for the current TTS utterance to finish, or 3 seconds, whichever
   comes first.
2. Apply `reset_session` — the voice-agent drops its current
   `conversation_id` **locally** and generates a fresh one on its next
   outbound request. No new request field; no client-advertised
   `conversation_id`; the backend does not echo a successor id.
3. Apply `stop_recording` — stop the mic against the (now empty) session.

Both signals in one reply always land in the correct order. Sequencing is
enforced inside `dispatch` via `await` between steps; no parallelism.

**Apply-after-TTS guarantee:** the dispatcher observes
`TtsService.isSpeaking` (already exposed as `ValueListenable<bool>` at
`core/tts/tts_service.dart:9`) and proceeds either when it flips to
`false` or when the 3s ceiling fires — whichever comes first. The
timeout is a safety ceiling: if TTS is stuck, the signal still applies,
which is the safe default (releasing the mic is better than holding it
forever).

**Signal bus (core → feature):** Producers call
`SessionControlDispatcher.dispatch(signal)` directly — the provider
exposes a single dispatcher instance, so there is no explicit
Stream-based bus. Riverpod resolution supplies the recording-feature
handlers via thin `core/`-owned ports (`HandsFreeControlPort`,
`SessionIdCoordinator`). See below.

**Toast and haptic:** A lightweight `Toaster` abstraction wraps
`SnackBar` via a `GlobalKey<ScaffoldMessengerState>` owned by
`app/app.dart`. A parallel `HapticService` wraps `HapticFeedback.lightImpact`
from `services.dart`. Both live in `core/session_control/` because the
dispatcher is the only caller; promoting either to a wider `core/ui`
location is a follow-up. If both signals are true, the dispatcher emits
two toasts (250 ms apart via the natural sequencing of the `await`s); if
this reads as noisy in manual smoke, collapse to a single "Session ended,
new conversation ready" string in a follow-up — not worth the extra
conditional branching in v1.

### Recorder + session-handler contracts per signal

`HandsFreeController` already exposes:

- `startSession()` (`hands_free_controller.dart:167`) — opens mic + FG service
- `stopSession()` (`hands_free_controller.dart:229`) — closes mic + FG service,
  drains in-flight jobs
- `suspendForTts()` / `resumeAfterTts()` — already used by P028 TTS path
- `isSuspendedForManualRecording` getter — guard for lifecycle edges

For `stop_recording` we reuse `stopSession()` unchanged. It already flips
`sessionActiveProvider` to false, stops the foreground service, cancels the
engine, and drains in-flight jobs — exactly the "release the mic" contract.
The post-stop state is `HandsFreeIdle`, identical to the state after a
`HandsFreeSessionError` retry. The mic button on `RecordingScreen` is
already wired to re-arm from this state on tap (P014 gesture table).

For `reset_session` we need a minimal client-local coordinator. Per the
canonical contract (P049 §5): reset is entirely client-local — no
request-side wire change, no client-advertised `conversation_id`, no
header. The voice-agent drops its local `conversation_id` and generates a
fresh one on its next outbound request; the backend's existing
device-id-based conversation stitching handles the new conversation on
the server side.

**`SessionIdCoordinator` contract** (lives in
`core/session_control/session_id_coordinator.dart`):

- Holds a private `String?` current conversation id; initial value null
  (meaning "fresh — backend will create one").
- `Future<void> resetSession()` — clears the id. Purely client-local:
  subsequent diagnostic logs tag the new turn as a new conversation.
  This has no wire effect — no outbound request ever carries the id —
  so clearing is a signal-of-intent, observable only in logs and
  telemetry.
- `String? get currentConversationId` — reads the id for
  diagnostics/logs.
- `void adoptConversationId(String id)` — called by `SyncWorker` after a
  successful reply that returns `conversation_id`, so subsequent sends
  keep the same local tag.

`SyncWorker` adopts the returned `conversation_id` from each reply and
uses it purely for client-side correlation (logs, telemetry). **The
request body shape is unchanged** — no `conversation_id` field is added
to outbound requests. Reset is observable to the backend only indirectly:
after reset, the voice-agent's `SyncWorker` allows the backend's existing
10-minute-inactivity session rollover heuristic to run on the next send,
or emits a backend-initiated reset on its own follow-up cue.

**No new method on `HandsFreeController` is required for `reset_session`.**
The hands-free session is conversation-agnostic from the mic's perspective;
the mic stays open, the VAD stays running, only the local tag changes.

**For `stop_recording`, a port interface is introduced:**
`HandsFreeControlPort` — a minimal interface placed in `core/` so the
dispatcher depends on core only, preserving the CLAUDE.md dependency
rule.

- Port: `lib/core/session_control/hands_free_control_port.dart`
  (`HandsFreeControlPort`) declares: `Future<void> stopSession()`,
  `bool get isSuspendedForManualRecording`. (`isSessionActive` is not
  required by the dispatcher in v1 and is omitted to keep the port
  minimal; if a future caller needs it, add it via a port extension.)
- Adapter: `features/recording/presentation/hands_free_controller.dart`
  declares `implements HandsFreeControlPort`. `HandsFreeController`
  already exposes `stopSession` and `isSuspendedForManualRecording`
  (verified at `hands_free_controller.dart:65` and the existing
  `stopSession` around line 229), so no method-body changes are needed
  on the controller.
- Provider: `core/session_control/session_control_provider.dart` declares
  `handsFreeControlPortProvider`; `app/app.dart` overrides it to delegate
  to `handsFreeControllerProvider.notifier`.

This is the ports-and-adapters shape CLAUDE.md's architecture implies:
`core/` owns the port; `features/` owns the adapter; the app wires them.
No cross-feature import occurs. The GlobalKey backing `Toaster` is owned
by `_AppState` and exposed through the `toasterProvider` override, not a
module-level singleton — the Riverpod provider is the DI seam.

### Toast/haptic UX

Toasts use the existing `ScaffoldMessenger` via a global key owned by
`app/app.dart`. Strings:

- `reset_session` applied → "New conversation"
- `stop_recording` applied → "Session ended"
- both → two toasts in sequence (see above)

Each toast has duration `Duration(seconds: 2)` and the default
`SnackBarBehavior.floating`. Haptic is
`HapticFeedback.lightImpact()` (Android) / UIImpactFeedbackGenerator light
(iOS) — the Flutter `HapticFeedback` API already handles both.

Rationale: a screenless user needs a non-visual confirmation; the haptic
is the primary channel. The toast is redundant for hands-free use but
useful for a user who happens to be looking at the screen, and costs
nothing.

### Failure modes

**Signal arrives mid-recording.** Example: VAD is actively capturing a new
segment (`HandsFreeCapturing`) when the previous segment's reply carrying
`stop_recording=true` arrives. The dispatcher `await`s TTS completion; by
the time TTS finishes, the mid-recording segment has either finished
(engine returned to `HandsFreeListening`) or is still capturing. In either
case `stopSession()` is safe: it interrupts the engine, drains in-flight
jobs (with the same 10-second bounded drain already in
`hands_free_controller.dart:_drainInFlightJobs`), and emits `HandsFreeIdle`.
The in-flight segment's transcript is preserved if it reaches `Persisting`
before the drain deadline; otherwise its WAV file is cleaned up.

**Signal conflicts with user action.** Example: user taps the mic button
during TTS to force manual recording (P014 interrupt path). The dispatcher
is still `await`ing TTS. When the user taps:

1. `RecordingScreen._onTap` calls
   `ttsService.stop()` — TTS flips to `isSpeaking=false` — dispatcher's
   listener resolves the completer and the dispatcher proceeds to
   `stopSession()`.
2. But before the dispatcher acquires `HandsFreeControlPort`, the user's
   `suspendForManualRecording()` has already fired.
3. The dispatcher's `stopSession()` runs anyway. The controller handles
   this: it no-ops on `HandsFreeIdle`, and from
   `HandsFreeSuspendedForManualRecording` it tears down the manual
   recording path cleanly via `RecordingController.cancelRecording` (the
   existing background-pause path) plus controller-level teardown.

Solution: the dispatcher reads
`HandsFreeControlPort.isSuspendedForManualRecording` before calling
`stopSession()`. Canonical authority statement (mirrored byte-for-byte
in personal-agent P049): **Backend emits signals advisory; client may
honor with delay or fail-safely. On `stop_recording`, the client always
honors (no opt-out in V1). On `reset_session`, the client honors after
TTS completion.** Concretely, the suspended-for-manual-recording branch
is a *delayed* honor on `stop_recording` — the client still honors the
signal, but only after the user-initiated manual segment completes; the
dispatcher does not call `stopSession()` mid-manual-recording because
the already-active `HandsFreeController` teardown from the manual path
will handle the mic release on its own. Toast and haptic are suppressed
in that branch so the user sees no conflicting feedback.

For `reset_session` the conflict is simpler: resetting the
`currentConversationId` has no user-visible effect until the next send,
and any in-flight user-initiated send has already captured the previous
id — no race.

**TTS fails or never starts.** Example: TTS is disabled in settings
(`getTtsEnabled() == false`), or `flutter_tts` throws silently, or the
reply body has no `message` field (TTS is not invoked). The dispatcher's
`_waitForTtsToFinish` checks `ttsService.isSpeaking.value` first; if
already false, it returns immediately. If the listener never fires (TTS
stuck mid-utterance), the 3-second timeout (canonical per P049 §5) fires and
the signal applies anyway.

Order-of-signal-arrival edge: the signal must be handed to the
dispatcher only *after* the reply's TTS utterance has actually started,
so the dispatcher's first read of `isSpeaking.value` reliably observes
`true` (when TTS plays) or `false` (when TTS is disabled / silently
dropped).

The current `_handleReply` calls
`unawaited(ttsService.stop().then((_) => ttsService.speak(...)))` —
`isSpeaking` does not flip to `true` synchronously on return from
`stop()`, and the `.then(speak)` callback runs several event-loop
turns later. If `dispatcher.dispatch(signal)` is scheduled between
`stop()` returning and `speak()` actually starting, the dispatcher can
observe `isSpeaking == false`, return immediately, and apply the
signal before the farewell utterance is produced — cutting off the TTS
the user is supposed to hear.

**V1 fix (adopted):** `_handleReply` is changed to
`await ttsService.stop()` first, then `await ttsService.speak(...)` to
the point where `speak()` has returned (which resolves after the
TTS engine's start-handler has flipped `isSpeaking` to `true`), and
only then calls `dispatcher.dispatch(signal)` via `unawaited(...)`.
This makes the dispatcher's first `isSpeaking.value` read
deterministic: `true` when TTS is playing, `false` only when TTS is
disabled or threw. No dispatcher-side grace window is needed.

### Integration point: `SyncWorker._handleReply`

The current handler
(`lib/features/api_sync/sync_worker.dart:184-201`) parses `message` and
`language` and calls `ttsService.speak`. The contract change:

- Change the existing TTS invocation from fire-and-forget
  `unawaited(ttsService.stop().then((_) => ttsService.speak(...)))` to
  a sequenced `await ttsService.stop(); await ttsService.speak(...)`
  so that by the time the next line runs, `ttsService.isSpeaking` has
  deterministically flipped to `true` (or stayed `false` if TTS is
  disabled / threw). See §Failure modes "Order-of-signal-arrival edge".
- After the sequenced TTS kick, call
  `SessionControlSignal.fromBody(json)` on the decoded body.
- When non-null, dispatch via the injected
  `SessionControlDispatcher.dispatch(signal)`. The call is `unawaited` so
  the sync drain loop does not block on TTS completion + signal handling
  (which can take seconds). Dispatch exceptions must be caught inside
  `dispatch` (or logged via `debugPrint` at the catch seam) so
  `unawaited` does not swallow errors silently.
- The existing catch-all (non-JSON/unexpected shape → stay silent) is
  preserved.

`sessionControlDispatcher` is injected into `SyncWorker` via the
constructor; `syncWorkerProvider` supplies
`ref.watch(sessionControlDispatcherProvider)`.

### Chat feature hook (forward-compat, deferred to Known Compromises)

When `features/chat` P024 `ThreadNotifier` handles the SSE `result` event,
it will call `SessionControlSignal.fromBody(resultJson)` on the decoded
`result` payload and dispatch through
`sessionControlDispatcherProvider` (same shared instance). No
feature-to-feature import: both features reach into
`core/session_control/`. This hook is out of scope for the three
in-scope tasks below because the chat feature does not currently drive
the hands-free recorder; the dispatcher's `stopSession` is a no-op on
`HandsFreeIdle`, so wiring it later is safe. Called out here so the
design is forward-compatible.

## API Contracts

Wire format (matches P049 T1/T3 exactly):

```json
{
  "message": "Goodbye.",
  "language": "en",
  "session_control": {
    "reset_session": false,
    "stop_recording": true
  }
}
```

- `session_control` is optional; absence (key missing or value is not a
  `Map`) is parsed as `null` on the client and carries no side effect.
- When the envelope is present as a map, both booleans default to false
  if missing. Missing keys are not an error. The client parses this as
  a non-null no-op `SessionControlSignal` (`isNoop == true`) — the
  dispatcher returns early without side-effects but the envelope's
  presence is recorded for audit/debug. This preserves the distinction
  between "backend sent nothing" and "backend sent an empty envelope"
  and keeps forward-compat when a third boolean lands.
- Per P049 the backend only attaches the envelope when at least one
  known boolean is true, so the no-op branch is defensive: it becomes
  reachable if a future backend version emits an envelope whose only
  `true` key is one this client does not yet understand.
- Any extra keys in `session_control` are ignored (forward-compat).

Dart type shape (declared in
`core/session_control/session_control_signal.dart`):

- `class SessionControlSignal` — fields `resetSession: bool`,
  `stopRecording: bool`; getter `isNoop` (true when both booleans are
  false); static factory
  `SessionControlSignal? fromBody(Map<String, dynamic> body)` parsing the
  canonical envelope. Returns `null` only for absent key or non-`Map`
  value; returns a non-null signal (possibly with `isNoop == true`) when
  the envelope is present. The dispatcher is responsible for handling
  the no-op branch (early return, no toast/haptic, no side-effect).

No change to `ApiResult` / `ApiSuccess.body` — the body is already
forwarded raw to `_handleReply`.

No change to outbound request bodies — `reset_session` is client-local
per canonical (P049 §5).

No change to backend wire format beyond what P049 defines. P049 is the
server contract source of truth; this document records the expected
shape for verification.

## Affected Mutation Points

**New files:**

- `lib/core/session_control/session_control_signal.dart` — value object
  and `fromBody` constructor (see code above).
- `lib/core/session_control/hands_free_control_port.dart` — `HandsFreeControlPort`
  interface with two methods: `Future<void> stopSession()` and
  `bool get isSuspendedForManualRecording`. (`isSessionActive` is tracked
  in a separate Riverpod provider, not on the controller — omitted from
  the port to keep it minimal.)
- `lib/core/session_control/session_id_coordinator.dart` — holds
  `currentConversationId`; exposes `resetSession()` and a getter.
- `lib/core/session_control/toaster.dart` — wraps
  `ScaffoldMessengerState` via a global key; `show(String message,
  {Duration duration})`.
- `lib/core/session_control/haptic_service.dart` — wraps
  `HapticFeedback.lightImpact`.
- `lib/core/session_control/session_control_dispatcher.dart` — the
  dispatcher class described above; owns TTS-wait, ordering, toast/haptic.
- `lib/core/session_control/session_control_provider.dart` — Riverpod
  providers: `sessionControlDispatcherProvider`,
  `sessionIdCoordinatorProvider`, `handsFreeControlPortProvider`
  (overridden in `app/app.dart`), `toasterProvider`, `hapticServiceProvider`.

**Needs change:**

- `lib/features/api_sync/sync_worker.dart` — add `sessionControlDispatcher`
  and `sessionIdCoordinator` constructor parameters; extend
  `_handleReply` to parse the `session_control` envelope and dispatch.
  Preserve every existing behaviour — TTS playback, `onAgentReply`
  callback, error handling on malformed body. On successful reply that
  carries `conversation_id`, call `adoptConversationId` for client-side
  correlation (no request-side change).
- `lib/features/api_sync/sync_provider.dart` — wire
  `sessionControlDispatcherProvider` and `sessionIdCoordinatorProvider`
  into `syncWorkerProvider`.
- `lib/features/recording/presentation/hands_free_controller.dart` — add
  `implements HandsFreeControlPort` to the class declaration. No method
  body changes — `stopSession` and `isSuspendedForManualRecording` are
  already implemented.
- `lib/app/app.dart` — hold the `GlobalKey<ScaffoldMessengerState>`, pass
  it to `MaterialApp.scaffoldMessengerKey`, expose it via
  `toasterProvider` override; override `handsFreeControlPortProvider` to
  delegate to `handsFreeControllerProvider.notifier`.
- `lib/features/recording/presentation/recording_providers.dart` — nothing
  structural; the `handsFreeControllerProvider` already exists.

**No change needed:**

- `lib/core/network/api_client.dart` — request body shape is unchanged.
  Reset is client-local per canonical (P049 §5); no `conversation_id`
  request field is added.
- `lib/features/recording/data/hands_free_orchestrator.dart` — lifecycle
  is driven entirely by `HandsFreeController`; no need to teach the
  orchestrator about signals.
- `lib/core/tts/*.dart` — TTS interface already exposes
  `isSpeaking` as a `ValueListenable<bool>`.
- `lib/features/chat/` — no v1 change; forward-compat integration noted
  in Solution Design is deferred.

## Test Impact / Verification

**Dispatcher unit tests (T1)** (new,
`test/core/session_control/session_control_dispatcher_test.dart`):

One test per signal combination:

- `dispatch(signal(reset=true, stop=false))` → after fake TTS finishes,
  `sessionIdCoordinator.resetSession` called once, `stopSession` not
  called, toaster.show called with "New conversation", haptic fires.
- `dispatch(signal(reset=false, stop=true))` → `resetSession` not called,
  `stopSession` called once, toast "Session ended", haptic fires.
- `dispatch(signal(reset=true, stop=true))` → both called, `resetSession`
  fires strictly before `stopSession` (verified via a recorded call-log
  list).
- `dispatch(noop signal)` → dispatcher returns early; `resetSession`
  not called, `stopSession` not called, no toast, no haptic, no TTS
  wait. Separate test on `SessionControlSignal.fromBody` asserts
  `{"session_control": {"reset_session": false, "stop_recording": false}}`
  returns a **non-null** `SessionControlSignal` with `isNoop == true`
  (distinguishing "envelope present but no-op" from "envelope absent").
- TTS never starts (`isSpeaking` starts false) → dispatcher applies
  immediately.
- TTS stuck (`isSpeaking` stays true for > 3s timeout) → dispatcher
  applies after timeout fires.
- `isSuspendedForManualRecording == true` before `stopSession` call →
  `stopSession` is not invoked; toast/haptic are also suppressed.
- Concurrent `dispatch` calls: two back-to-back `dispatch` invocations
  are serialised — the second does not start its TTS-wait / side-effect
  stage until the first's `Future` resolves. Recorded call log asserts
  ordering.

**`sync_worker_test.dart` updates (T2)**
(`test/features/api_sync/sync_worker_test.dart`):

- New case: `ApiSuccess.body` containing
  `{"message": "...", "session_control": {"reset_session": false, "stop_recording": true}}` →
  mocked `sessionControlDispatcher.dispatch` called once with
  `stopRecording: true, resetSession: false`.
- Existing case: body with only `message` → dispatcher NOT called (asserted).
- Existing case: malformed JSON body → dispatcher NOT called, no
  exception bubbles up.
- Replace the `FakeSessionControlDispatcher` (v1 test double) with a
  recorded-calls list so ordering of TTS vs dispatch is asserted where
  relevant.

**Widget integration tests per signal combination (T3)**
(`test/features/api_sync/sync_worker_integration_test.dart`, pumps a
minimal `ProviderScope` with overrides):

- Combo A — stop-only: `ApiClient` returns body with
  `session_control.stop_recording=true` → `HandsFreeController` transitions
  to `HandsFreeIdle`, `ScaffoldMessenger` shows "Session ended", one
  haptic fires.
- Combo B — reset-only: body with
  `session_control.reset_session=true` → `sessionIdCoordinator` cleared,
  `ScaffoldMessenger` shows "New conversation", session stays active.
- Combo C — both: body with both booleans true → reset applied first,
  then stop; both toasts in order; both haptics fire.
- Combo D — envelope present but both false: `fromBody` returns a
  non-null no-op signal; dispatcher is invoked but returns early
  (`isNoop` branch) without calling `stopSession`/`resetSession` and
  without showing a toast/haptic; behaviour observable to the user is
  identical to today.

**Unit test** (`test/core/session_control/session_control_signal_test.dart`):

- `fromBody` with full payload (both true) → non-null signal, both
  booleans true, `isNoop == false`.
- `fromBody` with absent `session_control` key → null.
- `fromBody` with `session_control` value that is not a `Map` (e.g. list,
  string) → null.
- `fromBody` with `session_control` present as a map but both booleans
  false (`{"reset_session": false, "stop_recording": false}`) → non-null
  signal, `isNoop == true` (distinguishes envelope-present-no-op from
  envelope-absent; forward-compat for a future third boolean).
- `fromBody` with missing `reset_session` or `stop_recording` keys inside
  a present map → treat as false; non-null signal returned.
- `fromBody` with extra unknown keys inside a present map → ignored;
  non-null signal returned.

**Manual smoke** (required before marking implemented):

- iOS iPhone 12 Pro and Android 14+ release builds.
- Scenario 1: "goodbye" → backend (P049) emits `stop_recording: true` →
  TTS farewell plays → toast + haptic → green mic disappears → tap mic →
  session re-arms.
- Scenario 2: "zacznij nową sesję" → backend emits `reset_session: true`
  → TTS confirms → toast + haptic → next utterance lands on a new backend
  conversation id (verified by checking personal-agent logs).
- Scenario 3: a reply that carries both signals → both toasts + haptics
  fire in order; session is ended; next tap opens a fresh conversation.
- Scenario 4: a reply with no `session_control` → identical to today (no
  toast, mic stays).
- Scenario 5: with TTS disabled in settings → signal still applies after
  ~100ms (immediate return from `_waitForTtsToFinish`).

**Commands:** `flutter analyze && flutter test`. The dependency-rule
check script in `voice-agent/CLAUDE.md:40-51` must still print OK for
`lib/features/api_sync/` and `lib/features/recording/`.

## Risks

| Risk | Mitigation |
|------|------------|
| **Dependency-rule violation.** `SyncWorker` (api_sync) acting on `HandsFreeController` (recording) is a cross-feature import. | Mandatory: dispatcher + ports live in `core/session_control/`. `features/recording` implements `HandsFreeControlPort`; `features/api_sync` depends only on the core dispatcher. Run the `grep` checks in `voice-agent/CLAUDE.md` as part of CI before merge. |
| TTS race: signal applies before farewell finishes, cutting off the user's last feedback. | `SessionControlDispatcher._waitForTtsToFinish` listens on `TtsService.isSpeaking` and waits up to 3 seconds (canonical per P049 §5). Unit tests cover both the "TTS finishes normally" and "TTS timeout" paths. |
| TTS failure: `flutter_tts` silent drop leaves `isSpeaking=true` forever, stalling the signal. | 3-second hard timeout in `_waitForTtsToFinish` (canonical). The signal applies regardless — releasing the mic on timeout is strictly safer than holding it. |
| User taps mic during TTS, overriding signal. | Dispatcher reads `HandsFreeControlPort.isSuspendedForManualRecording` before calling `stopSession`. Per canonical (P049 §Are We Solving the Right Problem?): backend emits signals advisory; client honors `stop_recording` always, honors `reset_session` after TTS completion — when the user has entered manual recording the dispatcher skips the direct `stopSession()` call and lets the manual-recording teardown handle mic release, which preserves the "always honor" guarantee with delay. |
| iOS audio-session conflict (TTS `playback` ↔ mic `playAndRecord`) when `stopSession` fires immediately after TTS. | `HandsFreeController.stopSession` stops the foreground service and engine in the correct order already established by P026/P028 — the same flow that runs on user-initiated stop. No new conflict is introduced. |
| Android 14+ foreground-service killer fires when `stopSession` tears down the service right after TTS. | `stopService` is idempotent; the FG service type set by P028 covers both `microphone` and `mediaPlayback` simultaneously. Post-stop, no FG service is required (app can be backgrounded or foregrounded). No new constraint. |
| Backend emits conflicting signals rapidly (e.g. two replies in < 1s each carrying different signals). | Dispatcher serializes concurrent `dispatch()` calls via an internal `Future` chain (or a short queue), so the second waits for the first's `_waitForTtsToFinish` to return. Worst case: a ~3s delay on the second signal. Duplicate toasts/haptics are avoided by design. |
| `reset_session` is purely client-local (no request-side wire change per canonical P049 §5). Observable behaviour depends on the backend's device-id-based conversation stitching on the next send. | Unit test on `SessionIdCoordinator.resetSession()` asserts the local id is cleared; integration test asserts the dispatcher calls `resetSession()` once. End-to-end new-conversation behaviour is verified via manual smoke scenario 2 (checking personal-agent logs). |
| P049 names its fields differently at ship time (`session_control` → `client_commands`, etc.). | `SessionControlSignal.fromBody` is a single-file change. Coordination is handled by T1 (below) which explicitly couples the two PRs' merge timing. |
| Toasts are noisy for users who happen to be looking at the screen when both signals fire. | v1 accepts two sequential toasts. If field reports call this out, follow up by merging the strings into one toast. Not worth a branch in v1. |
| `flutter_tts` may not call `setCompletionHandler` on some Android devices (known quirk). | The 3-second timeout protects against this. Separately, manual smoke on Android 14 during implementation T1 verifies the happy-path firing. If widespread, we add an additional TTS-finished signal based on `tts.awaitSpeakCompletion`. |

## Alternatives Considered

- **Client-side farewell detection.** See "Are We Solving the Right
  Problem?" — rejected. Duplicates logic, drifts from backend rules,
  wastes battery.
- **Separate websocket for control messages.** Rejected. Two network
  channels; new auth surface; out-of-order risk.
- **User-only control (do nothing).** Rejected. Defeats the hands-free
  contract.
- **Eager signal application (skip TTS wait).** Rejected. Cutting off
  the farewell is worse UX than a 1–2s delay; the farewell is the signal
  to the user that the session is ending.
- **Persist signals across app restarts.** Rejected. A signal observed
  but not applied during a crash is irrecoverable context — the next app
  start is a new universe; if the backend still wants the session reset
  or mic released, it will emit the signal again on the next reply.
- **One-shot bus (Stream + broadcast) instead of direct dispatcher.**
  Considered and rejected. A Stream bus adds a subscriber lifecycle that
  the dispatcher's `async` method already provides in-line. Direct method
  call on the singleton dispatcher is simpler and test-friendlier.
- **Put the dispatcher in `features/api_sync/`.** Rejected — violates the
  dependency rule once P024's `ThreadNotifier` needs to emit signals too.
  See "Architecture caveat".
- **Use a sealed class hierarchy for signals (`class
  ResetSessionSignal`, `class StopRecordingSignal`).** Considered. A flat
  struct with two booleans is simpler for a value object defined by two
  independent booleans. If a third signal arrives that cannot be
  orthogonal (e.g. "continue session with a new persona"), promote to
  sealed at that time — pure refactor, no contract change.

## Known Compromises and Follow-Up Direction

- **Chat feature not wired in v1.** `features/chat` P024 `ThreadNotifier`
  can reach the same dispatcher (the provider is in `core/session_control/`)
  but does not currently drive the hands-free recorder. The dispatcher
  will no-op on `stopSession` when the session is already idle, so a
  future hook is safe. Follow-up: when `ThreadNotifier` parses
  `session_control` in `ChatResult`, wire it into the same dispatcher.
- **No telemetry on signal-applied.** Backend cannot verify the client
  honoured the signal. Acceptable for v1; if abuse/misbehaviour appears
  in production we add a `POST /api/v1/session-control/ack` ping.
- **Toast copy is hard-coded English.** `voice-agent/CLAUDE.md` requires
  English in code; user-visible strings will be localised in a future
  proposal that introduces an ARB/i18n infrastructure. Until then, the
  same English strings ship to all users.
- **`SessionIdCoordinator.currentConversationId` is a plain field, not
  persisted.** An app restart forgets the id — but that also implies a
  fresh hands-free session, which implies a fresh backend conversation,
  so the observable behaviour is correct. Follow-up if this ever needs
  to survive process death.
- **`HapticService` is a thin wrapper.** If we add more haptic patterns
  (long press, success pattern), promote to `core/platform/haptic/`.
- **Toast throttling.** Back-to-back dispatches may stack two toasts
  before the first is dismissed. `ScaffoldMessenger` handles that via its
  internal queue; the visual effect is one toast replacing another
  quickly. Acceptable for v1.
- **No rate-limit on backend signals.** If the backend ever emits
  `stop_recording` on every reply (bug), the client honours each one.
  Harmless (second `stopSession` on an already-idle session is a no-op)
  but worth catching in an observability pass.
- **3-second TTS ceiling is shorter than typical Polish farewells.**
  P049 §5 sets the apply-after-TTS ceiling at 3s. A Polish confirmation
  utterance like "Jasne, zaczynamy od nowa, powiedz o czym chcesz
  pogadać dzisiaj" runs ~8–9s at normal TTS cadence, so in the common
  case the 3s ceiling fires *before* natural TTS completion and the
  farewell is cut short (mic releases while the utterance is still
  playing — the farewell continues on the speaker but the recorder
  stops). This is accepted for v1 as a predictability-over-polish
  trade-off: a hard ceiling prevents a stuck TTS from holding the mic
  forever, and the 3s value is canonical cross-project. If field
  feedback flags this as jarring, widen to 15s in a coordinated
  follow-up with P049 (both sides of the contract must agree).
- **Forward-compat chat feature hook is deferred.** When
  `features/chat` P024 `ThreadNotifier` gains the ability to drive the
  hands-free recorder (not today), wire it to call
  `SessionControlSignal.fromBody` on the SSE `result` payload and
  dispatch through the same `sessionControlDispatcherProvider`. The
  dispatcher no-ops on `stopSession` when the session is already idle,
  so wiring later is safe. This was previously listed as T4 in the
  Tasks table; it is not in-scope work for v1 and moves here to avoid
  blocking reviewers on deferred surface.

## Tasks

Each task is an independently mergeable PR with tests. Implementation
order: T1 → T2 → T3. Each compiles and passes CI on its own when merged
alone.

| # | Task | Layer | Notes |
|---|------|-------|-------|
| T1 | **Core skeleton.** Define `SessionControlSignal` + `fromBody`, `HandsFreeControlPort`, `SessionIdCoordinator`, `Toaster`, `HapticService`, `SessionControlDispatcher`, and the Riverpod providers in `lib/core/session_control/`. Unit tests: `SessionControlSignal.fromBody` (envelope parsing incl. absent-key → null, non-Map → null, present-with-both-false → non-null noop signal, missing inner keys → false, extra keys → ignored) and `SessionControlDispatcher` (all eight scenarios in Test Impact: TTS-wait, 3s timeout, suspended-for-manual override, reset-only, stop-only, both, noop-early-return, concurrent-dispatch serialisation). No feature wiring; dispatcher is unreachable from production code. | core/session_control (new), test | Mergeable alone. Same pattern as P049 T1 on the backend. |
| T2 | **SyncWorker wiring.** Extend `SyncWorker` to take `SessionControlDispatcher` + `SessionIdCoordinator` via constructor; change `_handleReply` to `await ttsService.stop(); await ttsService.speak(...)` before parsing `session_control` and dispatching (deterministic `isSpeaking` observation — see §Failure modes). Update `syncWorkerProvider` to inject both. Extend `sync_worker_test.dart` with: (a) body containing `session_control.stop_recording=true` → dispatcher called once with matching flags; (b) body with only `message` → dispatcher NOT called; (c) malformed JSON → dispatcher NOT called, no exception bubbles; (d) dispatch is scheduled only after `ttsService.speak` has returned. **Coordinate merge with personal-agent P049 T4** (voice transport); the wire contract must match byte-for-byte. | features/api_sync, test | Depends on T1. Coordination gate with P049 T4. |
| T3 | **HandsFreeController port + app wiring.** Add `implements HandsFreeControlPort` to `HandsFreeController` (no body changes; the two methods already exist). Wire `GlobalKey<ScaffoldMessengerState>` into `app/app.dart`, pass to `MaterialApp.scaffoldMessengerKey`, and register the `handsFreeControlPortProvider` override plus `toasterProvider` override. Decomposed widget integration tests (`test/features/api_sync/sync_worker_integration_test.dart`, pumps a minimal `ProviderScope` with overrides): (a) `stop_recording=true` only → controller goes to `HandsFreeIdle`, "Session ended" toast shown, one haptic; (b) `reset_session=true` only → coordinator cleared, "New conversation" toast shown, session remains active; (c) both → reset applied first then stop, both toasts in order. | features/recording, app, test | Depends on T1 + T2. Decomposed widget tests enforce the dispatch plumbing per signal combination. |

The forward-compat chat hook that previously appeared here as T4 has
moved to Known Compromises and Follow-Up Direction. It is not a tracked
task for this proposal's ship; see that section for the deferral
rationale.

## Acceptance Criteria

1. Reply carrying `session_control.stop_recording=true` stops the
   recorder after TTS finishes and leaves the session idle, requiring a
   user tap to resume.
2. Reply carrying `session_control.reset_session=true` clears
   `SessionIdCoordinator.currentConversationId` locally. The outbound
   request body is unchanged (no `conversation_id` request field per
   canonical P049 §5); there is no interruption in the audio session.
3. A reply carrying both signals applies `reset_session` first, then
   `stop_recording`, with both toasts and both haptics firing in the same
   order.
4. A reply carrying no `session_control` key (absent) behaves exactly
   as today: `SessionControlSignal.fromBody` returns `null`, the
   dispatcher is never invoked, no toast, no haptic, session continues.
5. A reply with `session_control` present as a map but both booleans
   false is observably equivalent to no signal, but the parsing path is
   distinct: `SessionControlSignal.fromBody` returns a non-null signal
   with `isNoop == true`, the dispatcher is invoked and returns early
   (no TTS wait, no toast, no haptic, no `stopSession`/`resetSession`
   call). This asymmetry-by-design preserves the "envelope present but
   no-op" audit trail and keeps forward-compat: when a third boolean is
   added to the envelope, a current-generation client parses the new
   envelope as a non-null signal (third field unknown, current two
   false) instead of silently dropping it.
6. If TTS is still speaking when the signal is handed to the dispatcher,
   the signal waits for `ttsService.isSpeaking` to flip false, or for 3
   seconds — whichever comes first (canonical per P049 §5).
7. If the user manually suspends the hands-free session (tap-to-record
   or press-and-hold) before the dispatcher reaches `stopSession`, the
   dispatcher skips `stopSession` (user wins).
8. `flutter analyze` passes with zero issues. `flutter test` passes. The
   `voice-agent/CLAUDE.md` dependency-rule grep check reports OK for
   every feature directory.
9. Manual smoke on iPhone 12 Pro and an Android 14+ device reproduces
   each scenario in Test Impact.

## Review Notes (2026-04-23)

Reviewed as Tier 2. Verdict: Ready with caveats. P1 fixed (port method
list). P2 findings accepted as implementation notes:

- **`_handleReply` async + drain interaction:** `_drain()` should `await`
  `_handleReply` up to and including `speak()` (fast — platform ack only),
  then `unawaited(dispatcher.dispatch(signal))` for the TTS-wait stage.
- **`speak()` does not guarantee `isSpeaking == true` on return:** The
  `setStartHandler` fires asynchronously after `_tts.speak()` resolves.
  Mitigated by the 3-second timeout ceiling — if the dispatcher observes
  `isSpeaking == false` and the start handler fires within that window,
  the dispatcher catches it. Worst case: signal applies immediately
  (farewell cut short) — still safe (mic released).
- **ProviderScope override:** `handsFreeControlPortProvider` override must
  live in `main.dart` where `ProviderScope` is created, not in `app.dart`.
- **`reset_session` client-side behavior in v1:** Beyond the toast, the
  only observable effect is clearing `SessionIdCoordinator.currentConversationId`.
  This has no wire effect — the backend manages conversation boundaries
  via device-id stitching. The coordinator is a future extensibility point
  and a log/telemetry tag.

## Related

- personal-agent proposal P049 session-control-signals (counterpart — wire
  contract source of truth)
- 014-recording-mode-overhaul
- 015-tts-response-playback
- 024-chat-screen
- 025-shared-api-layer
- 028-background-tts
- P000-backlog entry "Honor session-control signals from backend metadata"
