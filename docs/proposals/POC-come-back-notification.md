# PoC — "Come back" notification on iOS

> **This is not a proposal.** It's a throwaway proof-of-concept doc to record
> what we tried, why, and what we learned. Do not run `/proposal-review` on it.
> If the PoC graduates into real work, write a proper proposal then.

## Status: Draft / not implemented

## Goal

Verify on a physical iPhone that the app can show a local notification 30
seconds after going to background, and that it gets cancelled if the user
returns sooner.

This is purely a learning exercise — to confirm the iOS local-notification
plumbing works for our stack before designing anything around it (e.g.
re-engagement nudges, abandoned-recording reminders).

## Non-goals

- Not a re-engagement feature design. No copy, no analytics, no scheduling
  rules.
- Not Android. iOS only for the PoC; Android wiring (and `POST_NOTIFICATIONS`
  runtime prompt) can come later if the PoC is promising.
- Not background work. We are not waking the app, not running code in
  background — just scheduling a local notification with the OS.

## Approach

Smallest path that exercises the real iOS APIs:

1. Add `flutter_local_notifications` dependency.
2. Create `lib/core/notifications/come_back_notifier.dart`:
   - `init()` — initializes the plugin, requests `alert + badge + sound`
     permission via the iOS-specific options.
   - `scheduleComeBack({Duration delay = const Duration(seconds: 30)})` —
     schedules a local notification with id `1`, title `"Come back"`,
     body `"You left voice-agent 30s ago."`.
   - `cancelComeBack()` — cancels id `1`.
3. Hook into app lifecycle in `lib/app/app.dart` via `WidgetsBindingObserver`:
   - `AppLifecycleState.paused` → `scheduleComeBack()`
   - `AppLifecycleState.resumed` → `cancelComeBack()`
4. Call `init()` once during app startup.

## What this deliberately skips (PoC discipline)

- No Riverpod provider. Direct singleton usage in the observer is fine for a
  throwaway test; if it stays, refactor to a provider later.
- No tests. Lifecycle-driven local notifications are device-only behavior;
  unit tests would mock everything that matters and prove nothing.
- No settings UI, no on/off toggle, no copy variants.
- No Android manifest changes. iOS only.
- No `Info.plist` changes — local notifications don't need an entitlement, the
  permission prompt is enough.

## Manual verification (the only verification that counts here)

On a physical iPhone, debug build:

1. First launch → permission prompt appears → tap **Allow**.
2. Send app to background (home gesture). Wait 30s. → Notification appears.
3. Tap notification → app returns to foreground (default behavior, no custom
   handler).
4. Repeat: send to background, return within ~10s. → No notification fires.
5. Permission denied path: deny in Settings → no notification, no crash.
6. Lock screen path: send to background, lock device, wait 30s. → Notification
   shows on lock screen.

## Open questions to answer with the PoC

- Does iOS actually deliver close to 30s, or is there noticeable drift in
  low-power mode?
- Does it still fire if the app is force-quit (swiped away in the app
  switcher) within the 30s window? Expected: yes — schedule is owned by the
  OS.
- Permission prompt timing: do we want to ask on first launch, or defer until
  the first time the user backgrounds the app?

## Decision after PoC

After running the manual checks above, decide one of:

- **Drop** — delete the branch and this file. Notifications aren't worth it
  for our use cases.
- **Promote** — write a real proposal (`039-…`) that defines the actual
  re-engagement behavior, copy, settings, Android parity, ADR for permission
  ownership, and tests for the controller logic.
- **Park** — keep the code behind a debug-only flag while we figure out what
  re-engagement should actually do.

Until that decision is made, this doc is the only artifact. No ADR, no
proposal review, no implementation review.
