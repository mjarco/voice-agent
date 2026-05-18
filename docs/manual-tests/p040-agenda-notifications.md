# Manual test: P040 — Agenda notifications & background refresh

**Proposal:** [`docs/proposals/040-agenda-notifications-and-background-refresh.md`](../proposals/040-agenda-notifications-and-background-refresh.md)
**Why now:** P040 is code-complete and review-clean, but 11 contracts can only be verified on physical devices (notification delivery, OS-level scheduling, permission prompts, BGAppRefresh, WorkManager). This plan exists so the device pass can be run cold by anyone — no archaeology required.
**Time budget:** ~90 min total (60 min iOS + 30 min Android). Steps independent: skip any case the device can't exercise (e.g. Android-only on iPhone) without losing the rest.
**What we are testing:** the **delivery chain** — does the OS fire what the reconciler scheduled, does the tap route correctly, does the permission flow degrade gracefully. Unit tests already cover the reconciler logic (1030 cases on main); this plan only covers what unit tests can't.

---

## Setup

### S1 — Backend & accounts

**Do:** make sure your personal-agent has at least one **routine occurrence with `start_time`** scheduled for today plus 2–3 action items for today. Use the web UI to create these if not already present. Routine occurrences without `start_time` are *expected* not to produce per-occurrence reminders — they only show up in summaries (P040 §Time Resolution).

**Why:** without a today routine with `start_time`, you can't verify T5 / T11 (per-occurrence reminder firing).

### S2 — Install on device

**iOS:**
```bash
flutter build ios --flavor stable --no-codesign
# Open ios/Runner.xcworkspace, run on a real device with your personal cert.
```

Or for the dev flavor with telemetry:
```bash
flutter run --flavor dev --target lib/main_dev.dart \
  --dart-define=API_URL=https://<your-personal-agent>/api/v1 \
  --dart-define=API_TOKEN=<token> \
  --dart-define=GROQ_API_KEY=<groq-key> \
  -d <ios-device-id>
```

**Android:**
```bash
flutter run --flavor stable --target lib/main_stable.dart \
  --dart-define=API_URL=... --dart-define=API_TOKEN=... --dart-define=GROQ_API_KEY=... \
  -d <android-device-id>
```

Per [[no_apple_developer_account]]: iOS testing is always personal-cert + physical iPhone. iOS Simulator does NOT support `BGTaskScheduler` (T9 will reject the registration with `unhandledMethod`) — that's documented behavior, not a bug. Skip BG-task cases on Simulator.

### S3 — Inspector tools

- **iOS:** `xcrun simctl push` is irrelevant here (we're testing local notifications). Use Xcode's "Notifications" tab in Devices window to view delivered notifications. For schedule inspection, add a temporary debug screen reading `FlutterLocalNotificationsPlugin().pendingNotificationRequests()` — OR just observe delivery times.
- **Android:** `adb logcat | grep -E "WM-WorkSpec|FlutterLocalNotifications"` for WorkManager + plugin diagnostics. Notification shade gives delivery confirmation.

---

## Tests

The cases below are ordered "fastest first" — quick smoke checks at top, longer waits at the bottom. Mark each `[ ] PASS / FAIL / N/A` as you go.

### T1 — First-launch permission prompt fires once (both platforms, ~2 min)

**Do:**
1. Delete the app if previously installed (clean state).
2. Reinstall and launch.
3. Watch for the iOS / Android 13+ permission prompt.

**Why:** ADR-PLATFORM-008 ordering fix (#307) moved the cold-start read before `coreBoot`. Cosmetic regression here would be: prompt not appearing, or appearing twice.

**Expected:** Exactly one prompt within ~1 s of launch. Tap **Allow**. Confirm the prompt does NOT reappear on subsequent launches.

**On failure:** check `flutter logs` for an exception thrown around `core.notifications.requestPermission()`. iOS-specific: confirm `NSUserNotificationUsageDescription` is set in Info.plist (it is — P040 T1).

---

### T2 — Open Agenda tab → 4 daily summaries scheduled (both platforms, ~2 min)

**Do:**
1. Tap the **Agenda** tab (calendar icon, leftmost).
2. Wait for the screen to populate (status: Loaded).
3. From a debug build (or temporary debug widget): inspect `pendingNotificationRequests()` count.

**Why:** verifies P040 §Reconciler Triggers #1 — foreground fetch fires the reconciler, which schedules at least the 4 summary IDs (1000–1003).

**Expected:** at least 4 pending notifications. IDs 1000 (Morning), 1001 (Noon), 1002 (Afternoon), 1003 (Evening). One additional ID ≥ 3,000,000 per future today routine occurrence with `start_time`.

**On failure:** check that `lastAgendaFetchAt` is being written (Settings → debug screen, or `await AppConfigService().getLastAgendaFetchAt()`). If it's null after Agenda load, the notifier wiring is broken.

---

### T3 — Tap notification → app launches on `/agenda` (iOS + Android, ~3 min)

**Do:**
1. Force-quit the app (swipe up in app switcher).
2. From Xcode Devices → trigger a test notification, OR wait for a real scheduled summary to fire.
3. Tap the delivered notification banner.

**Why:** verifies ADR-PLATFORM-008 cold-start deep-link. The app should open directly on the Agenda screen, NOT default to the Record tab.

**Expected:** App opens, agenda screen is visible in the first frame (cached snapshot from `ApiAgendaRepository._getCachedAgenda`). No "Loading…" spinner.

**On failure:** Check `LocalNotificationService.readColdStartPayload()` is being called BEFORE `runApp` in `app_main.dart` line ~53. If the app lands on Record tab, the `pendingDeepLinkProvider` override was missed or the post-frame callback isn't firing.

---

### T4 — Warm tap → routes to `/agenda` (both platforms, ~2 min)

**Do:**
1. With the app running on a non-Agenda tab (e.g. Record), trigger a notification (wait for next summary at 09/12/15/19, or use Xcode Devices to deliver a custom one).
2. Tap the banner / notification shade entry.

**Why:** ADR-PLATFORM-008 warm-path channel (`notificationTapStreamProvider`). Routes via `_router.go('/agenda')` from `app.dart` listener.

**Expected:** App switches to Agenda tab. Same screen state as T3.

**Pitfall:** if you double-tap, GoRouter will navigate twice but the second is a no-op since same route.

---

### T5 — Routine occurrence reminder fires at `start_time` (iOS + Android, time-of-day-dependent)

**Do:**
1. Schedule (via personal-agent web UI) a routine occurrence for today at **3 minutes from now**, with `start_time` set.
2. Open the app's Agenda tab to trigger a reconcile (this schedules the reminder).
3. Lock the device. Wait.

**Why:** verifies the most user-visible P040 promise — per-occurrence reminders at exact times. Tests both reservation of the 3,000,000+ ID range AND `AndroidScheduleMode.exactAllowWhileIdle` / `UILocalNotificationDateInterpretation.absoluteTime`.

**Expected:** notification fires within ±15 s of the configured `start_time` (iOS) or ±60 s (Android). Title = routine name. Body = `start_time` (HH:MM). Tap → routes to `/agenda`.

**On failure:**
- **iOS late by >2 min:** likely scheduled with `AndroidScheduleMode.inexactAllowWhileIdle` by mistake; check the ID branch in `LocalNotificationService.schedule()` (summaries get inexact, routines get exact).
- **Android no fire on Android 13+:** `USE_EXACT_ALARM` not granted. Check `AndroidManifest.xml` (it is declared — P040 T2). Some OEMs require user-side battery whitelist; document the device and move on.

---

### T6 — Timezone correctness in non-UTC zone (both platforms, ~5 min)

**Do:**
1. With device set to a non-UTC zone (e.g. Europe/Warsaw, currently CEST = UTC+2): verify above tests fired at the *local* wall-clock time.
2. Optional: change device timezone to America/New_York, reopen Agenda tab to re-reconcile, observe new summaries scheduled at the NEW zone's 09/12/15/19.

**Why:** verifies the `flutter_timezone` fix (T1 commit `40fb10b`). The PoC's bug was `tz.local == UTC` because `tz_data.initializeTimeZones()` alone is insufficient. P040 added `tz.setLocalLocation` via the plugin.

**Expected:** all scheduled fire-times match the device's local zone, not UTC.

**On failure:** check `LocalNotificationService.init()` actually calls `tz.setLocalLocation(...)` after `FlutterTimezone.getLocalTimezone()`. If the device shows a system time of `09:00 CEST` and Morning fires at `11:00 CEST` (= `09:00 UTC`), the fix didn't land.

---

### T7 — Permission denial path (both platforms, ~3 min)

**Do:**
1. Delete the app. Reinstall.
2. On the permission prompt: tap **Don't Allow**.
3. Open the Agenda tab — does it load normally?
4. Try to trigger a manual reconcile (pull-to-refresh).

**Why:** verifies P040 §Permission Flow — denied permission must not crash the app and must not block the agenda flow.

**Expected:**
- Agenda screen loads normally (network fetch + cache work).
- No scheduled notifications (`pendingNotificationRequests()` returns empty).
- No exception, no error toast about notifications.

**On failure:** the reconciler's `if (!await service.isPermitted()) return;` early-return is broken, OR the agenda fetch is somehow tied to notification permission.

---

### T8 — Permission revocation between sessions (iOS, ~5 min)

**Do:**
1. With permission GRANTED, open Agenda tab to schedule notifications.
2. Confirm at least one item is in `pendingNotificationRequests()`.
3. Go to **Settings → Voice Agent → Notifications → Allow Notifications: OFF**.
4. Return to the app, pull-to-refresh Agenda.
5. Inspect `pendingNotificationRequests()` count.

**Why:** verifies ADR-NOTIF-001 rule 6 (revocation handling — false-after-true → `cancelAll()` once) and the clarification from PR #307 (tracking lives in `AgendaNotificationScheduler`, execution lives in `LocalNotificationService`).

**Expected:** after step 4, the pending count drops to **0**. No OS-side queue divergence from in-memory snapshot.

**On failure:** the `_previouslyPermitted` tracking in the scheduler isn't firing the cancelAll edge.

---

### T9 — Workmanager BG task registers on Android (Android only, ~3 min)

**Do:**
1. Launch the app on a real Android device.
2. From shell: `adb logcat | grep -E "WM-(WorkSpec|WorkContinuationImpl|GreedyScheduler)"`.

**Why:** verifies P040 T2 — `registerAgendaRefresh()` succeeds and WorkManager picks up the periodic task.

**Expected:** within ~10 s of launch, logcat shows a `WM-WorkSpec` row for `agenda-refresh` with `state=ENQUEUED` and interval `3600000` ms.

**On failure:** check `pubspec.yaml` has `workmanager: ^0.5.2`. Check the AndroidManifest has `RECEIVE_BOOT_COMPLETED`.

---

### T10 — iOS BGTask registration succeeds (iOS only, ~3 min)

**Do:**
1. Launch the app on a real iPhone (NOT Simulator — Simulator doesn't support BGTaskScheduler).
2. Watch `flutter logs` or Xcode console.

**Why:** verifies the Info.plist `BGTaskSchedulerPermittedIdentifiers` accepts the workmanager identifier (`be.tramckrijte.workmanager.iOSBackgroundAppRefresh`). On Simulator or on iPhone with a missing identifier, `registerPeriodicTask` throws `unhandledMethod` — P040 T2 caught this in `app_main.dart` lines 67–73 with a try/catch, so the app continues.

**Expected:** on a real iPhone, no exception logged for `registerAgendaRefresh`. On Simulator, the catch swallows the exception silently (`registerAgendaRefresh failed (continuing): ...` only in dev build).

**Note:** iOS BGAppRefresh is **opportunistic** — the system decides when to run it. You cannot force it. Even with registration succeeding, the task might never fire in a given 24-h window. That's documented in ADR-NET-002 P040 amendment as acceptable. Foreground triggers (T11) compensate.

---

### T11 — Foreground >1h staleness trigger (both platforms, requires 1h+ wait, ~5 min active)

**Do:**
1. Open Agenda tab (loads, sets `lastAgendaFetchAt`).
2. Background the app (home button). Wait **>1 hour**.
3. During the wait, add an action item via the personal-agent web UI for today.
4. Foreground the app — do NOT manually pull-to-refresh.
5. Open the Agenda tab. Is the new item visible without an explicit user action?

**Why:** verifies `AppShellScaffold.didChangeAppLifecycleState(resumed)` staleness check — the only mechanism that guarantees agenda freshness on iOS when BGAppRefresh declines to run. This is P040's primary user-facing reliability guarantee.

**Expected:** the new item is present in the Agenda tab without a manual refresh. New notifications (if the item is for later today with a `start_time`-equipped routine) are scheduled.

**On failure:** the `_kickRefreshIfStale` path in `app_shell_scaffold.dart` isn't reaching the notifier. Most likely cause: provider promotion (ADR-ARCH-009) didn't take effect — verify `ref.watch(agendaNotifierProvider)` is called in `AppShellScaffold.build`.

---

### T12 — Session gating end-to-end (iOS preferred, ~10 min)

**Do:**
1. Schedule a routine occurrence for **8 minutes from now** with `start_time` set. Open Agenda tab to register the reminder.
2. Confirm in `pendingNotificationRequests()` that the 3M+ ID for this occurrence is present.
3. Go to Record tab. Start a hands-free session (tap to engage).
4. Within the next 8 minutes, the reminder time arrives.
5. Observe: does the OS notification banner fire? Does it interrupt the active hands-free capture?
6. Stop the hands-free session.
7. Check `pendingNotificationRequests()` again.

**Why:** verifies the most subtle P040 contract — session gating (P040 §Session Gating). When `sessionActiveProvider == true`, per-occurrence reminders are cancelled from the OS queue (so they DON'T fire mid-session), and re-added on session end via a fresh fetch+reconcile.

**Expected:**
- Step 5: notification does NOT fire (session was active).
- Step 7: pending count for this occurrence is either:
  - present again if `start_time` is still in the future (session ended before reminder time), OR
  - absent if `start_time` has passed (the moment slipped during the session).

**On failure:** the `ref.listen<bool>(sessionActiveProvider, ...)` in `AgendaNotifier._setupSessionListener` isn't reacting. Check `_setupSessionListener` is called from the constructor.

---

## Cleanup

- Cancel pending notifications by deleting + reinstalling the app, or hit a debug "cancel all" widget if you wired one.
- Reset `lastAgendaFetchAt` by clearing `SharedPreferences` (uninstall is simplest).

---

## Reporting

For each test case, capture:

- `[ ]` PASS / `[ ]` FAIL / `[ ]` SKIPPED (with reason)
- Device + OS version + zone (e.g. "iPhone 12 Pro, iOS 18.3, Europe/Warsaw")
- For failures: short note + `flutter logs` excerpt + steps to reproduce

If 2+ cases fail, open a GitHub issue referencing this doc and the specific case numbers. If 0–1 cases fail and they have OEM-specific causes (Android battery saver, iOS low-power mode), document them as known limitations in the proposal §Risks rather than re-opening P040.

---

## When this plan is "done"

- Cases T1, T2, T6, T7, T8 must PASS — these are platform-portable and any failure is a real bug.
- Cases T3, T4, T5, T11, T12 should PASS on the user's daily-driver device. Failures on edge-case Android OEM builds are documented, not blocking.
- Cases T9, T10 are environment-conditional (need Android device / non-Simulator iOS) — N/A is acceptable if hardware unavailable.

After at least the "must PASS" set is green, P040 can be considered shipped without disclaimer.
