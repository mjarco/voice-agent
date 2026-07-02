# Proposal 046 — Pin a Chat Message from the App

## Status: Draft

## Prerequisites
- P045 (Pins Screen) — Implemented. Provides the `features/pins` module, the
  `PinSummary`/`PinDetail` models, `ApiPinsRepository`, and the pins list/detail
  screens. This proposal adds the *create* half to that read-only feature.
- P024 (Chat Screen) — Implemented. Provides `ThreadScreen`, `_MessageBubble`,
  `ConversationEvent` (which already carries `event_id`, `conversation_id`,
  `role`), and `ApiChatRepository`.
- personal-agent pin write endpoints — deployed to prod (N003 create, N005
  suggest; per memory, live since 2026-06-17):
  - `POST /api/v1/pins` — create a pin from a specific message.
  - `POST /api/v1/pins/suggest` — propose a name + matching topic (writes nothing).

## Scope
- Tasks: ~3
- Layers: core/network (new `PinWriter` port + provider), core/models (new
  request/result DTOs), features/pins/data (`ApiPinWriter` impl), features/chat
  (`ThreadNotifier` orchestration + `_MessageBubble` affordance), app (bind the
  port at the composition root).
- Risk: Tier 2 — additive write path consuming a deployed API. Reuses the
  existing `core`-port-with-feature-adapter seam (cf. `HandsFreeControlPort`) so
  chat can invoke the pins write path without a cross-feature import — no new
  architectural pattern; governed by ADR-ARCH-003/004/006/007. No storage schema,
  no audio/session behavior, no route changes.

---

## Problem Statement

P045 gave the app a read-only pinboard: the user can browse, open, and unpin
saved references. But it left the *creation* of a pin entirely to voice — the
user has to say "zapamiętaj ten pinout" mid-conversation for a pin to exist. The
empty state even instructs them to do so: "Say \"zapamiętaj ...\" in a chat to
save a reference."

That is a real gap. After an agent reply lands in the chat thread — a wiring
pinout, a recipe, a config snippet, a checklist — the user is looking straight at
the exact text they want to keep, but there is no way to pin *that message*. They
must either have known to say the magic phrase beforehand, or re-dictate the
request so the agent reproduces the artifact and they catch the phrasing. Both
are worse than a single tap on the message that is already on screen.

Meanwhile the backend already exposes the missing capability: `POST
/api/v1/pins` pins an explicit message (`conversation_id` + `event_id` + `name`),
and `POST /api/v1/pins/suggest` proposes a good name and a matching existing
topic for that message. The web UI uses both (the "pin this message" button,
N003 + N005). The app simply never learned to call them.

Concrete example: the user asks for a GPIO pinout, the agent replies with a
markdown table, and the user thinks "I want that." Today they cannot keep it
without re-prompting. After this change they tap the pin icon on that reply, the
app suggests a name ("ESP32 GPIO pinout") and drops it under a matching topic,
they confirm, and it is on the pinboard.

---

## Are We Solving the Right Problem?

**Root cause:** The app consumes only the *read* subset of the backend pin API
(list / detail / unpin). Pin *creation* has one and only one trigger — the voice
`pin_reference` chat tool fired by the phrase "zapamiętaj …". There is no
UI-initiated create path, because P045 deliberately scoped itself read-only (its
model header states "pins are created only by voice in chat; the client never
writes them"). The symptom (can't keep a message I'm looking at) traces directly
to that missing write path, not to anything in the chat or pins rendering.

**Alternatives dismissed:**
- *Rely on the voice phrase only (do nothing):* The phrase must be uttered
  *before* or *as* the agent produces the artifact, and it pins only the most
  recent agent message. It cannot retroactively pin a message the user scrolls
  back to. It is a create-at-dictation mechanism, not a keep-what-I-see one.
- *Plain name-entry dialog, skip `/pins/suggest`:* Cheaper (one fewer call) but
  drops the topic association and makes the user invent a name every time. The
  backend already computes a good name + matching topic; not using it produces
  worse-organized pins and more typing. Rejected in favor of suggest-then-confirm
  (see §Solution Design; this was the explicit product choice).
- *A global "pin last agent message" button (mirror the voice tool over HTTP):*
  Still can't pin an arbitrary scrolled-back message and adds a floating action
  with ambiguous target. Per-message affordance is clearer and strictly more
  capable.

**Smallest change?** The chat read-model already carries everything `POST
/pins` needs (`event_id`, `conversation_id`, `role` on every `ConversationEvent`)
— verified in code, no read-model extension required. The minimal change is: a
request DTO + two repository methods (suggest, create) + threading `eventId` into
the existing `_MessageBubble` so it can raise an `onPin` callback, plus a confirm
dialog. No new routes, no schema, no new screens.

---

## Goals

- Let the user create a pin from any **agent** message in a chat thread with a
  single tap, without leaving the thread.
- Use the backend's `POST /api/v1/pins/suggest` to pre-fill an editable name and
  a matching topic, so the common path is "tap → glance → confirm".
- Keep the write path in the `pins` feature (it owns pins); the `chat` feature
  only renders the affordance and forwards the message identity.
- Give clear, non-blocking feedback: success confirmation with a way to open the
  pinboard, and a readable error on failure.

## Non-goals

- No pinning of **user** messages in V1 (the affordance appears on agent bubbles
  only — pins are for durable agent artifacts; the backend permits any role, so
  this is a UI scoping choice, not a contract limit).
- No editing of pin *body text* from the app — pins remain verbatim copies of
  the source message; the confirm dialog edits only name/topic, not content.
- No changes to the voice "zapamiętaj …" path, the pins list/detail screens, or
  the `append_reference` / recall-by-name capabilities (those are chat-tool-only
  on the backend and out of scope).
- No offline queueing of pin creation — pinning requires connectivity; failures
  surface immediately (consistent with the read pins feature, which is also
  online-only).

---

## User-Visible Changes

Each **agent** message bubble in a chat thread gains a small pin icon
(`Icons.push_pin_outlined`). Tapping it shows a brief loading state while the app
fetches a suggested name and topic, then opens a confirm dialog pre-filled with
an editable **name** field and the **suggested topic** (shown, editable/clearable).
Confirming saves the pin and shows a SnackBar ("Pinned as \"<name>\"") with an
"Open" action that navigates to the pinboard; the icon on that bubble switches to
the filled `Icons.push_pin` for the rest of the session to signal it was pinned.
Cancelling or an error leaves nothing saved. No other screen changes.

---

## Solution Design

### Backend contract consumed (already deployed; documented here for the reviewer)

All bodies are wrapped in `{"data": …}`; all errors are
`{"error": {"code", "message"}}`; all require `Authorization: Bearer`.

**`POST /api/v1/pins/suggest`** — proposes name + topic, writes nothing.

Request:
```
{ "conversation_id": "<string>", "event_id": "<string>" }
```
Response `200` (`data`):
```
{
  "name":        "<proposed recall name, ≤60 runes; deterministic fallback if LLM unwired>",
  "aliases":     ["…"],            // may be null/absent
  "topic_label": "<matching EXISTING topic canonical name, or \"\" if none similar enough>",
  "topic_ref":   "<topic record ref, or \"\">"
}
```
Errors: `400 invalid_request` (missing field), `404 not_found` ("message not
found in conversation"), `500 internal_error`.

**`POST /api/v1/pins`** — creates the pin.

Request:
```
{
  "conversation_id": "<string, required>",
  "event_id":        "<string, required>",
  "name":            "<string, required>",
  "topic_label":     "<string, optional/omitempty>",
  "aliases":         ["…"]          // optional/omitempty
}
```
Response `201` (`data`):
```
{
  "pin":                   <pinDTO>,        // full pin: record_id, pin_name, topic_label, text, …
  "created":               true|false,      // false on idempotent re-pin
  "superseded_record_id":  "<id or \"\">"   // prior same-name pin replaced
}
```
Errors: `400 invalid_request`, `404 not_found` ("message not found in
conversation"), `500 internal_error`.

The `pin` object in the create response is exactly the existing `PinDetail`
shape (`record_id`, `pin_name`, `topic_label`, `text`, `aliases`,
`conversation_id`, `source_event_ids`, `created_at`) — so we reuse `PinDetail`
for parsing it and only add the two thin wrappers (suggestion, create-result).

**`aliases` is out of scope for V1.** Both endpoints allow `aliases`, but the
confirm dialog only edits name + topic, so the client neither parses the
suggested `aliases` nor sends any on create (the backend `omitempty` makes an
absent field a no-op). `PinSuggestion` and `PinCreateRequest` therefore carry no
`aliases` field — this keeps the create payload exactly
`{conversation_id, event_id, name, topic_label?}` and matches AC-3. (Preserving
backend-suggested aliases for recall-by-name is named as a follow-up in §Known
Compromises.)

### Data flow

The **`ThreadNotifier` owns the orchestration and the pinned-state**, mirroring
its existing `toggleEndorse` (an async notifier method that calls a repository
and mutates state; the widget only forwards the call). The `ThreadScreen` widget
renders the affordance and the dialog/SnackBar (UI concerns) and delegates the
network calls to the notifier.

**Effective conversation id.** The pin action must key on the *server* conversation
id, not the `widget.conversationId` route param. That param stays the literal
`'new'` for the whole life of a screen opened on a fresh thread — the real id only
appears in the loaded state after the first send (`thread_notifier.dart` sets it
on the `Conversation`, and every `ConversationEvent` also carries its own
`conversationId`). The notifier resolves the effective id from loaded state /
the event, and the pin icon is shown only when that real id exists.

1. User taps the pin icon on an agent `_MessageBubble`. The bubble raises
   `onPin(eventId)` (new callback), threaded from `ThreadScreen` the same way the
   endorse callback is today, calling `notifier.pinMessage(eventId)`.
2. If no effective server conversation id is available for that event (the `'new'`
   / not-yet-sent case), the icon is not rendered, so the tap cannot fire. The
   notifier also defends the same guard (no-op if called without a real id).
3. **In-flight guard.** The notifier marks that `eventId` as pin-in-flight (a
   `Set<String> _pinInFlight`); the bubble renders a small spinner in place of the
   icon and ignores further taps for that event until the flow resolves. This
   single-flights the suggest call and prevents double dialogs.
4. The notifier calls `PinWriter.suggestPin(conversationId, eventId)` → returns
   `PinSuggestion { name, topicLabel }`.
   - **Suggest failure** (404/5xx/transient): clear the in-flight mark, no dialog
     opens; the screen shows a SnackBar with the classified message.
5. On suggest success the screen shows the confirm dialog seeded with the
   suggestion (editable **name**; **topic** shown, editable/clearable). On confirm
   the notifier calls
   `PinWriter.createPin(PinCreateRequest{conversationId, eventId, name, topicLabel})`
   → returns `PinCreateResult { pin, created, supersededRecordId }`.
   - **Create failure**: clear the in-flight mark, dialog is dismissed, SnackBar
     with the classified message; nothing is pinned.
6. Success → the notifier adds `eventId` to `Set<String> _pinnedEventIds` (part of
   the loaded thread state) so the bubble shows the filled pinned icon; clears the
   in-flight mark. The screen shows a SnackBar ("Pinned as \"<name>\"") with an
   "Open" action → `context.push('/pins')`.

Error classification reuses the notifier's existing `ApiResult`→message mapper
where possible (the same one `toggleEndorse` / streaming errors use), falling back
to the `PinsException` messages surfaced by the `PinWriter` implementation.

### Ownership / layering — the cross-feature boundary (resolved)

The chat notifier must invoke the pin write path, but `features/chat` must not
import `features/pins`. This is resolved with a **`core`-level `PinWriter` port
bound at the app composition root** — the standard Riverpod DI seam, and the only
option that keeps `PinsRepository` where it is (no P045 refactor). Concretely:

- **`core/network/pin_writer.dart` — new.** Declares
  `abstract class PinWriter { Future<PinSuggestion> suggestPin(String conversationId, String eventId); Future<PinCreateResult> createPin(PinCreateRequest request); }`
  and a `Provider<PinWriter> pinWriterProvider` whose default body
  `throw UnimplementedError('pinWriterProvider must be overridden')`. `core`
  imports nothing from `features/`, so this is dependency-rule-clean. The
  request/result models stay in `core/models/pin.dart` alongside
  `PinSummary`/`PinDetail`.
- **`features/pins/data/api_pin_writer.dart` — new.** `class ApiPinWriter
  implements PinWriter`, backed by `ApiClient.postJson('/pins/suggest')` and
  `postJson('/pins')`, unwrapping `data` and classifying errors through the
  existing `PinsException` path — exactly like `ApiPinsRepository`. (All pin API
  knowledge stays in `features/pins/data/`.)
- **`app_main.dart` (the root `ProviderScope`, the composition root) overrides
  `pinWriterProvider`** with `ApiPinWriter(core.api)` — sitting right beside the
  existing `apiClientProvider.overrideWithValue(core.api)` override there. `app`
  is allowed to import both `core` and `features`, so this binding is legal.
  Widget/notifier tests override `pinWriterProvider` with a fake — no
  `features/pins` dependency leaks into `features/chat` or its tests.
- **`ThreadNotifier` depends only on `core`.** Its provider (`chat_providers.dart`)
  additionally `ref.watch(pinWriterProvider)` and passes the `PinWriter` into the
  notifier constructor next to the existing `ChatRepository`. `features/chat`
  imports `core` only — the grep gate (`import.*features/` in `lib/features/chat/`)
  stays clean.

Invariant enforced by AC-7 / the CLAUDE.md grep gate: **no
`import '…/features/pins/…'` from `features/chat/`**, and **no `import '…/features/…'`
from `core/`**.

This is **not a new pattern**: it is a second application of the `core`
port-with-feature-adapter seam that already ships as `HandsFreeControlPort`
(abstract port + `handsFreeControlPortProvider` in `core/session_control/`,
adapter `HandsFreeController` in `features/recording/`, bound by override in
`app_main.dart`). See §Alternatives Considered for the two rejected options.

> **ADR:** Governed by existing decisions — ADR-ARCH-003 (feature isolation
> mandates communicating through `core` providers, never direct imports),
> ADR-ARCH-004 (default-throws provider overridden at boot), ADR-ARCH-006
> (domain-port pattern), ADR-ARCH-007 (inject via override on the root
> `ProviderScope`). No new ADR. ADR-ARCH-006 gets a one-line amendment making
> explicit that a port's adapter may be **feature-owned** (not only a core
> platform adapter), citing `HandsFreeControlPort` + this proposal; committed
> alongside the proposal.

The chat feature also renders the affordance: `_MessageBubble` gains an optional
`onPin` callback + `pinned` flag (both null/false for user bubbles, which stay
unchanged).

### Constraints / invariants preserved

- The `{"data": …}` envelope unwrap convention (P025) is followed for both new
  calls.
- User message bubbles are visually and behaviorally unchanged (no icon).
- No message without a real server conversation id (the `'new'` / not-yet-sent
  case) reaches `POST /pins` — the icon is not rendered and the notifier no-ops.
- `features/chat` never imports `features/pins`; the write path is reached only
  through the `core` `PinWriter` port.
- Pin *content* is never sent by the client — only the message identity + name +
  topic; the backend copies the verbatim body server-side.

---

## Affected Mutation Points

State being changed: (1) the set of pins on the backend (via new writes), and
(2) the `ThreadNotifier`'s session-local "which messages are pinned / in flight"
view state.

**Needs change:**
- `core/network/pin_writer.dart` (**new**) — `abstract class PinWriter`
  (`suggestPin`, `createPin`) + `pinWriterProvider` (default throws
  `UnimplementedError`). `core`-only, no `features/` import.
- `core/models/pin.dart` — add `PinSuggestion` (`name`, `topicLabel?`) and
  `PinCreateRequest` (`conversationId`, `eventId`, `name`, `topicLabel?`, with
  `toMap()`) and `PinCreateResult` (`pin: PinDetail`, `created`,
  `supersededRecordId`). No `aliases` field (see contract note). The file header
  comment ("client never writes them; no `toMap`") is rewritten to reflect the
  new write DTOs — an intentional contract change, called out for the PR reviewer.
- `features/pins/data/api_pin_writer.dart` (**new**) — `class ApiPinWriter
  implements PinWriter` via `ApiClient.postJson`, `data` unwrap, `PinsException`
  classification (`404` → `PinNotFoundException`).
- `app_main.dart` — override `pinWriterProvider` with `ApiPinWriter(core.api)` in
  the root `ProviderScope` (beside the existing `apiClientProvider` override).
- `chat_providers.dart` — `threadNotifierProvider` also `ref.watch(pinWriterProvider)`
  and passes it to the `ThreadNotifier` constructor.
- `ThreadNotifier` (`features/chat/presentation/thread_notifier.dart`) — accept a
  `PinWriter`; add `pinMessage(eventId)` (suggest→[screen dialog]→create) plus the
  `_pinInFlight` and `_pinnedEventIds` sets exposed on the loaded state, mirroring
  `toggleEndorse`. Resolves the effective conversation id from loaded state / the
  event, not the route param.
- `_MessageBubble` (`thread_screen.dart`) — accept `eventId`, `onPin` callback,
  `pinned`, and `pinInFlight`; render the pin icon (outlined / filled / spinner)
  on agent bubbles only, and only when a real conversation id exists.
- `ThreadScreen` build loop — pass `event.eventId` + the callbacks/flags into
  `_MessageBubble`; own the confirm dialog + SnackBars (UI only), delegating the
  suggest/create calls to `notifier.pinMessage`.

**No change needed:**
- `ConversationEvent` (`core/models/conversation.dart`) — already parses
  `event_id`, `conversation_id`, `role`; nothing to add.
- `PinsRepository` / `ApiPinsRepository` / `PinView` / the `PinsException`
  hierarchy — **stay in `features/pins` unchanged** (the write path is a separate
  `PinWriter` port, so P045's read module is not refactored).
- Pins list/detail screens, `PinsNotifier`, `PinDetailNotifier` — untouched;
  a freshly created pin appears on next pinboard load (the list refreshes on
  entry per ADR-ARCH-011).
- `ApiChatRepository` / chat send path — untouched; pinning is independent of
  sending.

---

## Tasks

| # | Task | Layer |
|---|------|-------|
| T1 | `core` write seam: `PinWriter` abstract port + `pinWriterProvider` (default throws) in `core/network/pin_writer.dart`; `PinSuggestion`/`PinCreateRequest`/`PinCreateResult` models in `core/models/pin.dart` (rewrite the header comment); `ApiPinWriter` implementation in `features/pins/data/`; override `pinWriterProvider` in `app_main.dart`. Unit tests: model round-trips (`PinCreateRequest.toMap` omitempty; `PinCreateResult.fromMap` nested `PinDetail`), `ApiPinWriter` suggest/create parse + 400/404/500 classification + envelope unwrap + `ApiNotConfigured`. | core, features/pins/data, app |
| T2 | Chat affordance + notifier orchestration: inject `PinWriter` into `ThreadNotifier` (via `chat_providers.dart`); add `pinMessage(eventId)` + `_pinInFlight`/`_pinnedEventIds` on the loaded state; resolve the effective conversation id from state (not the `'new'` route param). Thread `eventId`/`onPin`/`pinned`/`pinInFlight` into `_MessageBubble`; render the icon (outlined/filled/spinner) on agent bubbles only when a real id exists; `ThreadScreen` owns the confirm dialog + success/error SnackBars. Notifier + widget tests. | features/chat |
| T3 | Version bump in `pubspec.yaml` (MINOR — new user-facing capability) + manual test plan `docs/manual-tests/p046-pin-a-chat-message.md` (tap → suggest → confirm → appears on pinboard; in-app-created conversation; double-tap; suggest-404; offline failure). | app, docs |

Task order: T1 → T2 → T3. T1 lands the `core` port + models + binding with tests
and is independently mergeable (the port simply has no caller yet — the `app`
override + tests exercise it, so no dead code). T2 wires the caller. T3 is
version + docs. If `/proposal-architectural-review` produces an ADR (see the ADR
note in §Solution Design), it is committed with the proposal, before T1.

### T1 details
- `core/network/pin_writer.dart`: `abstract class PinWriter { Future<PinSuggestion>
  suggestPin(String conversationId, String eventId); Future<PinCreateResult>
  createPin(PinCreateRequest request); }` and
  `final pinWriterProvider = Provider<PinWriter>((_) => throw UnimplementedError(
  'pinWriterProvider must be overridden in app composition root'));`.
- New models in `core/models/pin.dart` (no `aliases`, per the contract note):
  - `PinSuggestion { name, topicLabel? }` ← `fromMap` reading `name`,
    `topic_label` (ignore `topic_ref` and `aliases`).
  - `PinCreateRequest { conversationId, eventId, name, topicLabel? }` with
    `toMap()` emitting `conversation_id`, `event_id`, `name`, and `topic_label`
    **omitted when null/empty** (match backend omitempty).
  - `PinCreateResult { pin (PinDetail), created (bool), supersededRecordId }`
    ← `fromMap` reading `pin` (reuse `PinDetail.fromMap`), `created`,
    `superseded_record_id`.
- `ApiPinWriter` (`features/pins/data/api_pin_writer.dart`): `suggestPin` →
  `postJson('/pins/suggest', body)`, unwrap `data` Map → `PinSuggestion.fromMap`;
  `createPin` → `postJson('/pins', request.toMap())`, unwrap `data` →
  `PinCreateResult.fromMap`. Reuse the P045
  `ApiPermanentFailure`/`ApiTransientFailure`/`ApiNotConfigured` → `PinsException`
  classification; `404` → `PinNotFoundException`.
- `app_main.dart`: add `pinWriterProvider.overrideWithValue(ApiPinWriter(core.api))`
  to the existing root `ProviderScope(overrides: [...])` list.
- Covers mutation points: `pin_writer.dart`, `core/models/pin.dart`,
  `api_pin_writer.dart`, `app_main.dart`.

### T2 details
- `ThreadNotifier` constructor gains a `PinWriter`; `chat_providers.dart`'s
  `threadNotifierProvider` `ref.watch(pinWriterProvider)`. Add
  `Future<void> pinMessage(String eventId)`: resolve the effective conversation id
  (loaded `Conversation` / the event's `conversationId`); no-op if none. Mark
  `eventId` in `_pinInFlight`; call `suggestPin`; on failure clear in-flight +
  emit an error the screen surfaces (no dialog). This mirrors `toggleEndorse`.
- Dialog handoff: the screen watches for a pending suggestion (or `pinMessage`
  returns the `PinSuggestion` to the screen), shows the confirm dialog, and on
  confirm calls a `notifier.confirmPin(eventId, name, topicLabel)` that runs
  `createPin`, then on success moves `eventId` from `_pinInFlight` to
  `_pinnedEventIds`; on failure clears in-flight. The exact suggestion→dialog
  handoff (return value vs. transient state) is an implementation detail settled
  in T2, but network calls + both sets live in the notifier.
- `_MessageBubble` gains `final String? eventId; final VoidCallback? onPin;
  final bool pinned; final bool pinInFlight;`. Render on agent bubbles only when
  `onPin != null`: spinner when `pinInFlight`, filled `Icons.push_pin` when
  `pinned`, outlined `Icons.push_pin_outlined` otherwise. User bubbles pass
  nothing (unchanged).
- `ThreadScreen` shows the confirm dialog + the success SnackBar (with "Open" →
  `context.push('/pins')`) and error SnackBars — UI only.
- Covers mutation points: `ThreadNotifier`, `chat_providers.dart`,
  `_MessageBubble`, `ThreadScreen` build loop.

---

## Test Impact

### Existing tests affected
- `test/features/chat/…/thread_screen` + thread_notifier tests — `_MessageBubble`
  gains new optional params (existing constructions default them; user bubbles
  unchanged); `ThreadNotifier` gains a `PinWriter` constructor arg, so existing
  notifier-test setups add a fake `PinWriter`. Add assertions that agent bubbles
  render the pin icon and user bubbles do not.

### New tests
- `test/core/models/pin_test.dart` — round-trip `PinSuggestion.fromMap`,
  `PinCreateRequest.toMap` (omitempty: `topic_label` absent when null/empty),
  `PinCreateResult.fromMap` (nested `PinDetail`).
- `test/features/pins/data/api_pin_writer_test.dart` (new) — `suggestPin`/
  `createPin` success + `400`/`404`/`500` classification, `{"data":…}` unwrap,
  `ApiNotConfigured` (mock `ApiClient`).
- `ThreadNotifier` tests (fake `PinWriter`) — `pinMessage` sets/clears
  `_pinInFlight`, suggest-failure clears in-flight and opens no dialog, confirm
  calls `createPin` with the exact `{conversation_id, event_id, name,
  topic_label}` payload, success moves the id into `_pinnedEventIds`,
  create-failure clears in-flight; effective-id resolution shows the icon on an
  in-app-created (post-send, route param still `'new'`) conversation and hides it
  on an unsent thread; double `pinMessage` for the same in-flight id is a no-op.
- `ThreadScreen`/bubble widget tests — icon visibility by role and by
  real-id-present; spinner while in-flight; dialog seeded from the suggestion;
  success SnackBar "Open" pushes `/pins`; error SnackBar on failure.
- Run: `make verify` (flutter analyze + test). No E2E harness in this repo;
  device-only steps go to the manual test plan (T3).

---

## Acceptance Criteria

1. An agent message bubble whose event has a real server conversation id renders
   a pin icon; a user message bubble does not.
2. On a conversation created in-app (first agent reply received, `widget.
   conversationId` still `'new'`), agent bubbles render the pin icon — the guard
   keys on the effective conversation id from state, not the route param.
3. Tapping the icon shows a spinner on that bubble and calls
   `POST /api/v1/pins/suggest` with the bubble's `conversation_id` + `event_id`,
   then opens a confirm dialog pre-filled with the returned `name` and
   `topic_label`. A second tap while in flight fires no additional suggest call.
4. Confirming calls `POST /api/v1/pins` with exactly `{conversation_id,
   event_id, name, topic_label}` (`topic_label` omitted when empty; no `aliases`),
   and on `201` shows a success SnackBar whose "Open" action navigates to `/pins`,
   where the just-created pin is present in the list.
5. After a successful create, that bubble's icon shows the filled pinned state
   for the remainder of the session.
6. A `404`/`5xx`/transient failure from **suggest** clears the spinner, opens no
   dialog, and surfaces a readable SnackBar. The same failure from **create**
   clears the spinner, dismisses the dialog, and surfaces a readable SnackBar.
   Cancelling the dialog saves nothing. In all failure cases nothing is pinned.
7. When no real server conversation id exists (unsent `'new'` thread) no pin icon
   is shown and no pin call is made.
8. No `features/chat/` file imports `features/pins/`, and no `core/` file imports
   `features/` (dependency-rule grep gates pass); `make verify` passes with no
   new analyzer issues.

---

## Risks

| Risk | Mitigation |
|------|------------|
| Chat needs the pins write path → cross-feature import would break the architecture rule | Resolved by the `core` `PinWriter` port bound at the app composition root (§Solution Design): chat depends on `core` only; `ApiPinWriter` lives in `features/pins/data`; `app` binds them. Enforced by the grep gates + AC-8. |
| `'new'` guard keyed on the route param would disable the feature on every in-app-created conversation (param stays `'new'` after send) | Guard on the effective conversation id from loaded state / the event, not `widget.conversationId`. Covered by AC-2 and a dedicated notifier test. |
| Double-tap fires two suggest calls / two dialogs | Per-event `_pinInFlight` single-flight in the notifier; the bubble shows a spinner and ignores taps until resolved. AC-3. |
| `/pins/suggest` latency makes the tap feel slow | Spinner on the tapped bubble; suggest is one call and the backend uses a deterministic fallback if the LLM is unwired, so it returns promptly. |
| Suggested topic matches an unintended existing topic | The dialog shows the topic and lets the user clear/edit it before confirming; `topic_label` is optional on create. |
| Session-local pinned state is lost on thread reload | Accepted V1 — the authoritative record is the pinboard; the filled icon is a within-session convenience, not persisted state. Server-truth reconciliation named as a follow-up. |
| Re-pinning the same message returns `created:false` / supersedes a prior pin | Treated as success (still on the pinboard); SnackBar copy is neutral ("Pinned as …") and does not claim novelty. |

---

## Alternatives Considered

**UX choices** (settled with the user, recorded in §Are We Solving the Right
Problem): per-message pin icon on agent bubbles (vs. long-press menu / global
button), and suggest-then-confirm (vs. plain name entry).

**Cross-feature boundary — how chat reaches the pins write path.** Three options
were weighed (the chosen one reuses an existing seam, not a new pattern):

- **(Rejected) `features/chat` imports `features/pins`.** Simplest to write, but
  a direct violation of the dependency rule (features never import other
  features). Non-starter.
- **(Rejected) Promote `PinsRepository` (interface + `PinsException` +
  `pinsRepositoryProvider`) into `core`.** Lets chat depend on it, but drags the
  entire shipped P045 read module through a relocation refactor (data impl,
  providers, both notifiers re-import), enlarging blast radius well beyond this
  feature and contradicting the "P045 untouched" intent. Rejected as
  disproportionate.
- **(Chosen) A new `core` `PinWriter` port, bound at the app composition root.**
  Isolates exactly the write capability chat needs; leaves the P045 read module
  untouched; keeps the API implementation in `features/pins/data`; and uses the
  idiomatic Riverpod override seam (`app/` is the only layer allowed to see both
  `core` and `features`), already shipping as `HandsFreeControlPort`. Cost: one
  new port type + one override. This is the minimal change that honors the
  dependency rule — see §Solution Design.

---

## Known Compromises and Follow-Up Direction

### User-message pinning deferred (V1 scoping)
The backend accepts a pin on any role, but V1 shows the affordance on agent
bubbles only, because agent artifacts are the durable-reference use case. If
users ask to pin their own messages, dropping the role guard on the icon is a
one-line follow-up.

### Session-local pinned state (V1 pragmatism)
"Which messages are pinned" is held in thread state for the session only, not
reconciled against the backend on load. Making bubbles reflect server truth
(e.g. by matching `source_event_ids` from the pinboard) is a follow-up if the
transient signal proves insufficient.

### Suggested aliases dropped in V1 (V1 scoping)
`/pins/suggest` may return `aliases` and `/pins` accepts them, but the confirm
dialog edits only name + topic, so the client neither parses nor sends aliases.
Backend-suggested aliases improve recall-by-name; wiring them (parse in
`PinSuggestion`, add to `PinCreateRequest`, surface an editable aliases field) is
a self-contained follow-up.

### `PinWriter` as the shared write seam
With this change the pins capability is reachable from chat via the `core`
`PinWriter` port. If a third surface later needs to create pins, that port — not
a new cross-feature import — is the extension point; it is introduced now and only
named as the future home for any additional write operations (append/recall).
