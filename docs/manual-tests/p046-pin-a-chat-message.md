# Manual test: P046 — Pin a chat message from the app

**Proposal:** [`docs/proposals/046-pin-a-chat-message.md`](../proposals/046-pin-a-chat-message.md)
**Overall status:** **pending** — no case yet executed on a physical device.
**Why now:** P046 is code-complete and review-clean (T1 + T2 merged, `make verify` green). The suggest→confirm→create flow, the `{"data":…}` envelope, and the create→navigate→appears-on-pinboard loop can only be verified end-to-end against a live personal-agent with the pin write endpoints deployed. Unit + widget tests already cover the notifier logic, the icon gating, the dialog seeding, and the exact request payload (65 chat-feature cases on `main`); this plan covers only what those can't — the real network round-trip and cross-screen navigation.
**Time budget:** ~20 min, single platform is enough (this is API + navigation, not OS-level behavior). Run on iOS or Android.
**What we are testing:** the **write round-trip** — does a tap fetch a real suggestion, does confirming create a pin the backend accepts, does the just-created pin show up on the pinboard, and does an offline failure degrade cleanly.

## Status legend

See the canonical legend in [`p040-agenda-notifications.md`](p040-agenda-notifications.md#status-legend). Each step has a `**Status:**` line using the same vocabulary (`pending` / `in-progress` / `passed (YYYY-MM-DD, <device + OS>)` / `failed (…)` / `skipped (…)`).

## Status summary

| # | Case | Status |
|---|---|---|
| S1 | Backend with pin endpoints reachable | pending |
| S2 | Install on device + configure API | pending |
| T1 | Pin icon appears on agent bubbles only | pending |
| T2 | Tap → suggestion pre-fills the confirm dialog | pending |
| T3 | Confirm → pin created, appears on pinboard via "Open" | pending |
| T4 | Pinned icon stays filled for the session | pending |
| T5 | In-app-created conversation shows the icon | pending |
| T6 | Cancel pins nothing | pending |
| T7 | Offline / server error degrades cleanly | pending |

---

## Setup

### S1 — Backend with pin endpoints reachable

**Status:** pending

**Do:** point the app at a personal-agent whose pin write endpoints are deployed
(`POST /api/v1/pins/suggest` and `POST /api/v1/pins` — N003 + N005, live on prod
since 2026-06-17). Confirm quickly from a shell:

```bash
curl -s -H "Authorization: Bearer $API_TOKEN" \
  -X POST https://<host>/api/v1/pins/suggest \
  -H 'Content-Type: application/json' \
  -d '{"conversation_id":"<real-conv>","event_id":"<real-agent-event>"}' | head
```

Expect a `{"data":{"name":…,"topic_label":…}}` body. A `404` here means the
ids are wrong; a `404`-for-all or default-404 means the pin service isn't
mounted on that deployment (`a.Pins == nil`) — pick a deployment that has it.

**Why:** T2–T7 all hit the live endpoints. Without them the feature can't be
exercised (there is no offline queue — pinning requires connectivity by design).

### S2 — Install on device + configure API

**Status:** pending

```bash
flutter build ios --flavor stable --no-codesign   # then run from Xcode on device
# or Android:
flutter run --flavor stable --target lib/main_stable.dart \
  --dart-define=API_URL=https://<host>/api/v1 \
  --dart-define=API_TOKEN=<token> --dart-define=GROQ_API_KEY=<key> -d <device>
```

Then open **Settings** in the app and confirm the API URL + token are set (the
same config the read pinboard uses). Open a chat with at least one agent reply.

**Why:** the pin affordance lives in the chat thread and needs a configured API.

---

## Test cases

### T1 — Pin icon appears on agent bubbles only

**Status:** pending

**Do:** open a chat thread that has both your messages and agent replies. Look
at the bottom-right of each bubble.

**Why:** verifies the role gate (`event.role == agent && conversationId
notEmpty`) renders on real backend events — proposal §Solution Design, AC-1.

**Expected:** an outlined pin icon (`push_pin_outlined`) sits at the bottom-right
of every **agent** bubble. **User** bubbles have no icon.

**On failure:** if user bubbles show an icon, the `role` gate regressed; if no
agent bubble shows one, check the events actually carry a non-empty
`conversation_id` (S1 curl) — the icon is gated on it.

### T2 — Tap → suggestion pre-fills the confirm dialog

**Status:** pending

**Do:** tap the pin icon on an agent message that contains something nameable
(a list, a snippet, a pinout). Watch the icon, then the dialog.

**Why:** verifies the `POST /pins/suggest` round-trip and that its `name` +
`topic_label` seed the editable dialog — AC-3.

**Expected:** the icon briefly becomes a small spinner, then a "Pin this
message" dialog opens with the **Name** field pre-filled with a sensible name
and the **Topic** field pre-filled when the backend matched one (may be empty).

**On failure:** dialog never opens + a "Could not prepare pin: …" SnackBar →
suggest failed (check S1). Dialog opens but fields are blank → the `data`
envelope wasn't unwrapped or the keys drifted (`name` / `topic_label`).

### T3 — Confirm → pin created, appears on pinboard

**Status:** pending

**Do:** in the dialog, optionally edit the name/topic, then tap **Pin**. When the
"Pinned as …" SnackBar appears, tap **Open**.

**Why:** verifies `POST /pins` with `{conversation_id, event_id, name,
topic_label?}` succeeds and the create→navigate→appears loop closes — AC-4.

**Expected:** a SnackBar reads `Pinned as "<name>"`. Tapping **Open** navigates
to the pinboard (`/pins`), where the new pin is present in the list. Opening it
shows the verbatim message body.

**On failure:** "Could not pin: …" SnackBar → create rejected (a `404` means the
message/conversation id was stale). Pin missing from the list → the list didn't
refresh on entry (ADR-ARCH-011) or the create 2xx'd without persisting.

### T4 — Pinned icon stays filled for the session

**Status:** pending

**Do:** after T3, go **back** to the chat thread (don't kill the app). Look at
the pinned message's icon.

**Why:** verifies the session-local `_pinnedEventIds` filled-icon state — AC-5.

**Expected:** that bubble's icon is now the **filled** `push_pin` and is not
tappable. (Note: this is session-local — after a full thread reload/app restart
it reverts to outlined. That's the documented V1 compromise, not a failure.)

### T5 — In-app-created conversation shows the icon

**Status:** pending

**Do:** start a **new** chat in the app, send a message, wait for the agent
reply, then look at the reply's bottom-right.

**Why:** the route param stays `'new'` after the first send; the guard must key
on the event's real conversation id, not the route param — AC-2. This is the
case that would silently break if the guard were wrong.

**Expected:** the agent reply in the freshly-created conversation shows the pin
icon and pins successfully (repeat T2–T3 against it).

**On failure:** no icon on the new conversation's agent reply → the guard
regressed to `widget.conversationId == 'new'`; the feature would be dead for all
in-app-created chats.

### T6 — Cancel pins nothing

**Status:** pending

**Do:** tap a pin icon, wait for the dialog, tap **Cancel**.

**Why:** verifies the cancel path leaves no pin and no filled icon — AC-6.

**Expected:** dialog closes, no SnackBar, the icon returns to outlined, and the
pinboard has no new entry.

### T7 — Offline / server error degrades cleanly

**Status:** pending

**Do:** enable airplane mode (or point at an unreachable host), then tap a pin
icon. Then, if you can, force a create-time failure (airplane mode *after* the
dialog opens) and tap **Pin**.

**Why:** verifies the split suggest-vs-create failure handling — AC-6. There is
no offline queue; failures must surface immediately.

**Expected:** suggest failure → no dialog, a readable "Could not prepare pin: …"
SnackBar, icon returns to outlined. Create failure → dialog dismisses, a "Could
not pin: …" SnackBar, nothing pinned. The app never hangs on the spinner.

**On failure:** a stuck spinner → the in-flight mark wasn't cleared in the
`finally`; a crash → an unhandled exception type escaped the generic
`on Exception` catch.

---

## When this plan is done

All cases are must-pass for a single platform — this is API + navigation, not
OS-specific behavior, so passing on one platform is sufficient (note the device
+ OS in the status). There are no OEM-conditional cases. Once every case is
`passed`, drop any "manual device verification pending" note from the proposal
status.
