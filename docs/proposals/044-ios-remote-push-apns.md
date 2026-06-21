# Proposal 044 — iOS Remote Push via APNs (client side)

## Status: Draft

## Prerequisites
- Paid Apple Developer Program membership (team `N6GT5R9SZ5`) — **met** as of 2026-06-20; this is what unblocks the Push Notifications capability.
- personal-agent **P093** (APNs Push Delivery, backend) — defines the `POST /api/v1/devices/apns` registration endpoint this proposal calls, and the sender that delivers the pushes this proposal receives. The two proposals are co-dependent and ship as a coordinated pair (one PR set per repo).

## Scope
- Tasks: ~3
- Layers: core (new push module), iOS platform (AppDelegate + entitlements), app (startup wiring), settings (status surface)
- Risk: Medium — first native remote-notification integration; new cross-repo API contract; sandbox/production APNs split is a known footgun.

---

## Problem Statement

Today voice-agent can only show **local** notifications: `flutter_local_notifications`
schedules them on-device (P040 agenda notifications, the come-back PoC), and
`workmanager` can wake the app for background refresh. There is no way for the
backend (personal-agent) to *initiate* a notification. If the agent produces
something the user should see — a morning warm-up nudge in the inbox
(`GET /api/v1/inbox`, P064) — the phone only finds out if the app happens to be
foregrounded or a background-refresh tick happens to fire. Background refresh on
iOS is best-effort and throttled by the OS, so timely delivery while the app is
killed is not achievable with the current stack.

Until 2026-06-20 this was also *blocked by account type* — remote push requires
the Push Notifications capability, which needs a paid Apple Developer Program
membership (the reason archived P061 was parked). That blocker is now gone.

---

## Are We Solving the Right Problem?

**Root cause:** The app has no APNs device token and no remote-notification entitlement,
so the server has no address to push to. The delivery gap is not a polling-tuning
problem — it is the absence of a server-initiated channel.

**Alternatives dismissed:**
- *Finish the P064 poller + local notifications:* Lower cost (no Apple key, no new
  secret), and genuinely sufficient for non-urgent nudges. Dismissed for this
  proposal because the user explicitly chose server-initiated push for
  low-latency delivery while the app is killed, which polling cannot guarantee on
  iOS (Background App Refresh is throttled/non-deterministic). The poller remains
  a valid fallback and is not removed.
- *FCM (Firebase Cloud Messaging) as a unified gateway (archived P061):* One SDK
  for iOS+Android. Dismissed because the user chose to avoid a Firebase/Google
  dependency and the app is iOS-first; we talk to APNs directly from the Go
  backend instead. Android push is a non-goal here.

**Smallest change?** The minimal client surface is: (1) register for remote
notifications and obtain the raw APNs token, (2) send it to the backend, (3)
render incoming pushes. We reuse the existing `flutter_local_notifications`
rendering and `ApiClient` transport rather than adding new infrastructure.

---

## Goals

- Acquire the raw APNs device token on iOS without adding a Firebase dependency.
- Register that token with personal-agent so the backend can address this device.
- Receive and present remote notifications (foreground, background, terminated),
  reusing existing notification rendering.
- Keep the registered token fresh across reinstalls, token rotation, and the
  yearly provisioning refresh.

## Non-goals

- **Android push.** iOS-only. No FCM, no `firebase_messaging`.
- **Rich/actionable notifications, notification categories, badges-as-state.**
  V1 delivers a simple alert (title + body) that opens the app.
- **Deciding *what* to push or *when*.** Trigger logic and payload content are
  owned by the backend (P093). This proposal only transports and renders.
- **Silent/background-data push** (`content-available`). V1 is user-visible alerts
  only; silent push (to refresh inbox quietly) is a named follow-up.

---

## User-Visible Changes

After granting notification permission, the user receives push notifications from
their own agent even when voice-agent is backgrounded or closed — e.g. a morning
warm-up nudge — and tapping one opens the app. Settings gains a small read-only
"Push notifications" status row (Authorized / Denied / Not registered) so the user
can see whether their device is reachable. If permission is denied or the backend
is unconfigured, behavior is unchanged from today.

---

## Solution Design

**Token acquisition (native, no Firebase).** Direct APNs requires the *raw* APNs
token (hex), which `firebase_messaging` does not expose. We add a thin native
hook in `ios/Runner/AppDelegate.swift`. **The app runs on the UIScene lifecycle**
(`Info.plist` declares `UIApplicationSceneManifest`; `SceneDelegate:
FlutterSceneDelegate` exists), so the legacy `window?.rootViewController`
messenger is nil — the `MethodChannel` MUST be registered through the same
`engineBridge.pluginRegistry.registrar(forPlugin:)` path the existing native
bridges use (`AudioSessionBridge`, `MediaButtonBridge` in `AppDelegate.swift`,
wired from `didInitializeImplicitFlutterEngine` / the
`FlutterImplicitEngineDelegate` path). `registerForRemoteNotifications` callbacks
are `UIApplicationDelegate` methods and fire correctly under UIScene; only the
channel messenger must follow the bridge pattern.

- After notification authorization is granted, call
  `UIApplication.shared.registerForRemoteNotifications()`.
- Implement `didRegisterForRemoteNotificationsWithDeviceToken` → encode the
  `Data` token as lowercase hex → forward to Dart over a `MethodChannel`
  (`voice_agent/push`, method `onApnsToken`) created via the bridge registrar.
- Implement `didFailToRegisterForRemoteNotificationsWithError` → forward the
  error so Dart can record "not registered".

**Entitlements / capability.** Two distinct files (they are NOT the same place):
- `ios/Runner/Runner.entitlements` — add `aps-environment` (Xcode sets value
  `development` for development-signed builds, `production` for distribution builds).
- `ios/Runner/Info.plist` — add `remote-notification` to the `UIBackgroundModes`
  array (needed later for silent push; harmless for alerts). Background modes live
  in `Info.plist`, not in the entitlements file.

With automatic signing + the paid team, Xcode adds the Push Notifications
entitlement to the App ID `com.voiceagent.voiceAgent`.

**Environment reporting.** Development-signed builds (how we install today via
`make install-ios`) register with the **APNs sandbox**; distribution builds use
**production**. The token alone does not reveal which. The client therefore reports
an `environment` hint with each registration, derived from build config
(`"sandbox"` when `kDebugMode` or a `--dart-define=APNS_ENV=sandbox`, else
`"production"`). The backend treats this as a hint and may fall back on
`BadDeviceToken` (see P093).

**Dart push module** (`lib/core/push/`, parallel to `lib/core/notifications/`):
- `PushTokenService` (domain interface) + `ApnsPushTokenServiceImpl` (data impl)
  wrapping the MethodChannel; exposes `Stream<PushRegistration>` (`{token,
  environment, bundleId}` or a failure state). `bundleId` is read natively (the
  running app's bundle identifier — distinct per dev/stable flavor) and carried in
  the emitted model so the controller has every field the registration body needs.
- A `PushRegistrationController` (presentation/controller) that registers on the
  backend. It depends on the existing `StorageService.getDeviceId()` for
  `device_id` and on `ApiClient` for transport; it calls
  `apiClient.postJson('/devices/apns', data: …)` **directly** (matching every
  existing feature repository) — no bespoke method is added to `ApiClient`.
- Dedup: the last-registered value is persisted in `SharedPreferences` keyed on
  the pair `(token, environment)`, so a sandbox→production transition re-registers
  even when the token is unchanged.

**Registration contract (client → backend, owned by P093):**

The *wire* endpoint is `POST {host}/api/v1/devices/apns`. But `ApiClient.baseUrl`
already includes `/api/v1` (`deriveBaseUrl()`), and all existing calls pass a path
*relative* to it (`postJson('/chat/cancel')`, `get('/conversations')`). The
client therefore calls **`apiClient.postJson('/devices/apns', …)`** — NOT the full
`/api/v1/...` path, which would double-prefix to `…/api/v1/api/v1/devices/apns`
and 404.
```
POST {host}/api/v1/devices/apns        (client call: postJson('/devices/apns'))
Authorization: Bearer {token}
Content-Type: application/json
{
  "device_token": "<lowercase hex APNs token>",
  "environment": "sandbox" | "production",
  "device_id": "<StorageService.getDeviceId()>",
  "bundle_id": "<running app bundle identifier, read natively>"
}
→ 200 {"data": {"registered": true}}
```
`bundle_id` is read from the running app's bundle identifier (the app has dev/stable
flavors with distinct ids — `com.voiceagent.voiceAgent` / `.dev`), not hardcoded as
a Dart literal, and must agree with the backend's `PA_APNS_BUNDLE_ID` per build.
Readiness/defer semantics: `ApiClient` returns `ApiNotConfigured` **only when
`baseUrl` is null** (no `apiUrl` configured) — in that case the controller defers and
retries next launch. A configured URL with a **missing/invalid token** does NOT
surface as `ApiNotConfigured`; the request is sent without `Authorization` and the
backend returns 401 (`ApiPermanentFailure`). The controller treats a 401 on
registration as "not yet authorized → defer and retry next launch" (not a permanent
failure), so a partially-configured app does not burn its dedup state or spin.

**Receiving & rendering.** For alert pushes, iOS shows the system banner natively
when the app is backgrounded/terminated. **Foreground decision: we let iOS present
the alert natively** — the `UNUserNotificationCenterDelegate.willPresent`
implementation returns `[.banner, .sound]` and does **not** round-trip the push
through `flutter_local_notifications`. This avoids (a) contending with
`flutter_local_notifications`, which already installs itself as the
`UNUserNotificationCenterDelegate` and owns `willPresent` for its own local
notifications, and (b) synthesizing a fake local notification whose tap would
double-fire the local-notification tap channel.

**Delegate-ownership strategy (concrete).** The app does **not** simply reassign
`UNUserNotificationCenter.current().delegate` (that would displace the plugin and
break its local-notification taps). Instead, after the plugin has installed its
delegate, the native code installs a **proxy delegate**: it captures the
plugin-installed delegate, sets itself as `UNUserNotificationCenter.current().delegate`,
and for every `UNUserNotificationCenterDelegate` callback it (1) handles the case
where the notification is a **remote** push (return `[.banner, .sound]` from
`willPresent`; route the tap per ADR-PLATFORM-008), and (2) **forwards all other
callbacks to the captured original delegate** so the plugin's local-notification
handling is untouched. This is the highest-risk native seam and is specified, not
left to implementer discretion (T3).

**Tap routing (ADR-PLATFORM-008).** A push tap is a new app-entry vector and MUST
flow through the existing two-channel deep-link infrastructure established by P040
(ADR-PLATFORM-008). Those channels are **`String`-route channels**: today
`LocalNotificationService.readColdStartPayload()` feeds `pendingDeepLinkProvider`
(cold) and `LocalNotificationService.tapStream` feeds `notificationTapStreamProvider`
(warm), each carrying a route string that `App` passes straight to `router.go(...)`.
V1 does **not** introduce structured deep-link payloads. Instead, an APNs tap
**resolves to a fixed, valid route string** (`'/record'` — the app's primary entry)
on **both** paths, and the raw APNs `data` payload is dropped for V1 (carrying it
would require redesigning the providers from `String` to a structured value — out of
scope). The native bridge populates the same channels: on cold start it exposes the
tap-launch route **before `runApp`** (read into `pendingDeepLinkProvider`); while
warm it emits the route onto a stream merged into `notificationTapStreamProvider`.
The "exactly one channel, never both" invariant holds. (Per-screen deep-linking
later = populating the existing channel with a real destination once the providers
carry structured values — see Known Compromises.)

**Permission flow.** Reuse the existing notification-permission request
(`flutter_local_notifications` already requests alert/badge/sound, P040). The
registration trigger fires on **every app start where permission is already
granted** (not only at first grant): the controller checks `isPermitted()`, and if
true invokes the native `registerForRemoteNotifications()` and reconciles the
resulting token against the persisted `(token, environment)`. This is what keeps
the token fresh and makes the dedup criterion exercisable. Denied permission →
record "Denied", skip registration, no push.

---

## Affected Mutation Points

State being changed: (a) the registered-token record sent to the backend, (b) app
startup wiring, (c) notification permission/registration path.

**Needs change:**
- `ios/Runner/AppDelegate.swift` — add remote-registration callbacks + MethodChannel via `engineBridge.pluginRegistry` (bridge pattern); call `registerForRemoteNotifications()` post-authorization; set the `UNUserNotificationCenter` delegate behaviour for remote `willPresent` without displacing the plugin's local-notification handling.
- `ios/Runner/Runner.entitlements` (+ Xcode project capability) — add `aps-environment`.
- `ios/Runner/Info.plist` — add `remote-notification` to `UIBackgroundModes`.
- App startup (`lib/app/app.dart` / bootstrap) — initialize `PushTokenService` and `PushRegistrationController` after notification init; read the cold-start push payload before `runApp` (ADR-PLATFORM-008).
- Notification permission path in `lib/core/notifications/` — on every start, if permitted, kick off remote registration (rendering unchanged).
- `lib/core/push/` (new) — `PushTokenService`, `ApnsPushTokenServiceImpl`, `PushRegistrationController`; controller calls `apiClient.postJson('/devices/apns', …)` and depends on `StorageService.getDeviceId()`.

**No change needed:**
- `lib/core/network/api_client.dart` — reused via `postJson`; **no** bespoke `registerApnsDevice` method added (keeps the transport class feature-agnostic, matching existing repositories).
- `flutter_local_notifications` rendering (`local_notification_service.dart`) — retains ownership of its own local notifications; not used to re-present remote pushes.
- `agenda_notification_scheduler.dart` (P040) — local scheduling is orthogonal.
- `ios/Runner/SceneDelegate.swift` — scene lifecycle owner; not modified (registration callbacks live on `AppDelegate`), confirmed not touched.
- Existing transcript sync (`features/api_sync`) — unrelated transport.

---

## Tasks

| # | Task | Layer |
|---|------|-------|
| T1 | iOS native token acquisition: add Push Notifications capability + entitlements, `registerForRemoteNotifications()` post-auth, AppDelegate callbacks, MethodChannel via `engineBridge.pluginRegistry`; `PushTokenService` + `ApnsPushTokenServiceImpl` exposing a registration stream; unit tests for the Dart service with a mocked channel | core/push, iOS platform |
| T2 | Backend registration: `PushRegistrationController` posting via `apiClient.postJson('/devices/apns', …)` (deviceId from `StorageService`, environment hint), `(token, environment)` dedup persisted in SharedPreferences, `ApiNotConfigured` defer-and-retry; tests for the controller (mocked ApiClient + storage) and dedup logic | core/push |
| T3 | Receive & route: foreground `willPresent` returns native presentation for remote pushes (no plugin round-trip), tap routed through ADR-PLATFORM-008 channels (cold-start + warm), "not registered/denied" state as a read-only Settings status row; widget/controller tests | core/push, core/notifications, settings |

### T1 details
- `aps-environment` resolves automatically per signing (dev → sandbox, dist → production); do not hardcode.
- MethodChannel registered via the `engineBridge.pluginRegistry.registrar(forPlugin:)` path (UIScene-safe), matching `AudioSessionBridge`/`MediaButtonBridge`.
- Token is encoded lowercase hex; emit a failure state on `didFailToRegister`.
- Dart-side tests cover token → `PushRegistration` mapping and environment derivation (`kDebugMode` / dart-define); native callbacks are device-only (note in the manual test plan, below).

### T3 details
- Install a **proxy `UNUserNotificationCenterDelegate`**: capture the plugin's delegate, set self as delegate, handle remote `willPresent` (return `[.banner, .sound]`) and remote taps, and **forward every other callback to the captured original** so `flutter_local_notifications` is untouched. The app does **not** synthesize a local notification from the APNs payload, so the plugin's local-notification tap channel is never double-fired.
- APNs taps resolve to the fixed route string `'/record'` and feed the existing ADR-PLATFORM-008 channels: cold start via a native-read launch route into `pendingDeepLinkProvider` (before `runApp`), warm via a stream merged into `notificationTapStreamProvider`. Raw APNs `data` is dropped for V1 (providers carry `String` routes, not structured payloads).

---

## Test Impact

### Existing tests affected
- Notification permission tests in `test/core/notifications/` — extend to assert that remote registration is triggered on start when already permitted (mock the new service; assert no call on deny).
- App bootstrap/smoke tests — assert `PushTokenService` is initialized without error when push is unconfigured (`ApiNotConfigured` defers cleanly).

### New tests
- `test/core/push/apns_push_token_service_test.dart` — channel → registration stream mapping, environment derivation, failure state.
- `test/core/push/push_registration_controller_test.dart` — posts on first `(token, environment)`, skips on unchanged pair, re-posts on token OR environment change, defers on `ApiNotConfigured`; backend error handling.
- Run with `flutter test`; `make verify` for analyze + test.

**Device-only contracts** (native registration callbacks, real APNs token,
end-to-end delivery) cannot run in `flutter test`. They go into a manual test plan
at `docs/manual-tests/p044-ios-remote-push.md` per the CLAUDE.md template
(must-pass: token acquired on device, registration reaches backend, a test push
from P093 is delivered foreground/background/terminated).

---

## Acceptance Criteria

*Unit-testable (must pass in `flutter test`):*
1. `environment` is derived as `sandbox` under `kDebugMode`/`--dart-define=APNS_ENV=sandbox`
   and `production` otherwise (unit test on the derivation).
2. The controller calls `apiClient.postJson('/devices/apns', …)` (relative path) with
   `device_token`, `environment`, `device_id`, `bundle_id`; a registration whose
   `(token, environment)` matches the persisted pair does **not** re-POST; a change in
   either re-POSTs. `ApiNotConfigured` defers without error.
3. With permission denied, no registration call is made and Settings shows "Denied".
4. Settings shows a read-only "Push notifications" status row reflecting
   Authorized / Denied / Not registered.
5. `flutter test` and `flutter analyze` pass with no new issues.

*Manual verification (device-only — see `docs/manual-tests/p044-ios-remote-push.md`):*
6. On a device build with permission granted, the app obtains a non-empty hex APNs
   token and registration reaches the backend.
7. A foreground remote notification is presented natively (`willPresent` returns
   `[.banner, .sound]`) without synthesizing a local notification, and the proxy
   delegate forwards local-notification callbacks to the plugin unchanged.
8. A remote alert push sent by the backend (P093) is delivered foreground (native
   banner), backgrounded, and terminated; tapping it opens the app via the
   ADR-PLATFORM-008 channel.

---

## Risks

| Risk | Mitigation |
|------|------------|
| Sandbox vs production APNs mismatch silently drops pushes | Client reports `environment`; backend (P093) routes per-token and falls back on `BadDeviceToken`. Documented in both proposals + manual test plan. |
| Token churn (reinstall, restore, OS rotation) leaves stale tokens on the backend | Re-register on every launch; backend prunes on APNs `410 Unregistered` (P093). |
| User denies notification permission | Graceful: record "Denied", skip registration, no crash; poller fallback (P064) still works. |
| Native callbacks are untestable in CI | Covered by a manual device test plan; Dart logic isolated behind a mockable channel. |
| Adding `remote-notification` background mode invites App Store scrutiny later | Harmless for alert-only V1; only matters if/when we ship silent push (named follow-up) and distribute. |

---

## Alternatives Considered

- **`firebase_messaging`** — rejected (introduces Firebase/Google dependency; the
  user chose direct APNs; would also pull in Android wiring we don't want here).
- **A community APNs-token plugin** (e.g. `flutter_apns_only`) vs a hand-rolled
  MethodChannel — the hand-rolled channel is ~30 lines, avoids an unmaintained
  dependency, and keeps the native surface auditable. Revisit if the native code
  grows beyond token plumbing.

---

## Known Compromises and Follow-Up Direction

### iOS-only (V1 pragmatism)
No Android push. The `lib/core/push/` abstraction is platform-neutral at the Dart
boundary, so an Android/FCM data implementation could slot in later without
touching the controller or backend contract. Named so it is not mistaken for a
cross-platform design.

### Alert-only, no silent push
We add the `remote-notification` background mode but do not use silent
(`content-available`) push in V1. The follow-up direction is silent push to refresh
the inbox quietly before showing a local notification — deferred until the visible-
alert path is proven on-device. The natural seam for it is the same
`voice_agent/push` MethodChannel + `PushRegistrationController` introduced here.

### No deep-linking
Tapping a push routes to the fixed `'/record'` route; the APNs `data` payload is
dropped for V1 because the ADR-PLATFORM-008 channels carry a `String` route, not a
structured payload. The routing substrate already exists — **ADR-PLATFORM-008**'s
two-channel deep-link infrastructure (P040). Per-screen routing later means
promoting those providers from `String` to a structured deep-link value and
populating them from the push `data` — extending the existing layer, not building a
new one.
