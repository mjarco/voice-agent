# Proposal 040 — Agenda Notifications & Hourly Background Refresh

## Status: **Implemented (manual device verification pending)** — 2026-05-18

Code shipped across PRs **#297** (proposal + ADRs), **#298** (T1 notification service + reconciler), **#299** (T2 coreBoot + workmanager + parity gate), **#300** (T3 PoC removal + wiring + deep-link), **#307** (close-out: ordering fix + missing notifier tests), **#309** (chore unblocking `make verify`).

Review gates clean: `/proposal-review` (R0→R1→R2), `/proposal-architectural-review` (two passes), `/proposal-implementation-review` with fixes applied. `make verify` green. 1030 unit tests passing.

**Manual device verification:** see [`docs/manual-tests/p040-agenda-notifications.md`](../manual-tests/p040-agenda-notifications.md) for the 11-case verification plan covering timezone correctness, BG refresh delivery, permission flows, deep-link routing, session gating, and platform-specific OEM behavior. Per CLAUDE.md "Close Out" workflow, the proposal is marked **Implemented** after review gates pass; device-only verification cases are tracked separately and do not block the merged code from being considered done.

---

*Draft history preserved below. The body documents what was intended and decided during design; the status block above is the canonical close-out summary.*

## Prerequisites

- P021 (Agenda Screen, Implemented) — `AgendaResponse`, `AgendaItem`, `AgendaRoutineItem` models; file-based cache (`agenda_cache_{date}.json` in documents dir, 7-day TTL); `AgendaNotifier` flow with `loading(cached)` state.
- P025 (Shared API Layer, Implemented) — `ApiClient.get('/agenda', ...)`.
- P027 (Background Sync, Implemented) — `sessionActiveProvider` in `core/providers/`, written by `HandsFreeController`. Pattern reused for session gating.
- PoC `POC-come-back-notification` — `flutter_local_notifications: ^18.0.1`, `timezone: ^0.10.0`, iOS permission prompt and Android `POST_NOTIFICATIONS` already in place.

## Scope

- Risk: **Medium** — new platform integration (background tasks, exact alarms), new permission flows, replaces the live PoC, amends ADR-NET-002. No API contract or persistence schema changes in this proposal.
- Layers: `core/notifications/` (new), `core/background/` (new), `core/providers/` (last-sync-at timestamp), `features/agenda/presentation/`, `app/`, `ios/Runner/`, `android/app/`, `pubspec.yaml`.
- Expected PRs: 3 (notification service + reconciler with tests; workmanager + platform plumbing; PoC removal + foreground triggers + deep-link wiring).

---

## Problem Statement

The voice-agent app has no way to remind the user about what is coming up or what has accumulated during the day. Today, the only nudge is a throwaway PoC ("Come back" 30 s after backgrounding) which is noise — it fires every time the user switches apps, regardless of whether anything actually demands attention.

Concrete example: the user has a routine occurrence scheduled at 14:30 ("Take the dog out") and three open action items for the day. Today these are visible only if the user opens the app and taps the Agenda tab. The phone — which should be the fastest path to today's plan — stays silent.

Three specific gaps:

1. **No periodic visibility into the day.** No signal at common time-of-day inflection points (morning start, midday check-in, afternoon, evening wrap-up).
2. **No per-occurrence reminders.** Scheduled routines pass by without any nudge.
3. **Stale schedule when offline.** Even if reminders were scheduled, items added by the user via the personal-agent web UI would not propagate until the next foreground fetch.

The PoC's local-notification plumbing works on iOS (verified manually) but solves the wrong problem. This proposal repurposes it for the right one and removes the PoC.

---

## Are We Solving the Right Problem?

**Root cause:** The app fetches the agenda only when the user actively opens it. Nothing maps agenda data to OS-scheduled reminders, and nothing keeps that mapping fresh when the app is closed.

**Alternatives dismissed:**

- *APNs / FCM push.* The natural fit (server schedules, server pushes) but ruled out — no Apple Developer account ([[project_no_apple_developer_account]] in memory). FCM alone would cover only Android.
- *Calendar integration (write items to iOS/Android Calendar).* Heavyweight, requires new permissions, surfaces our agenda inside a UI we don't control. Out of scope.
- *In-app reminders only (no OS notifications).* Defeats the point — user needs the nudge when *not* in the app.
- *Foreground-only scheduling (no background refresh).* Works if the user opens the app at least once per relevant change. Fails when the user adds an item via the web UI mid-day without opening the mobile app.
- *Per-action-item reminders at exact times.* Backend currently exposes only `scheduled_for` (date) for action items; no time-of-day. See **Time Resolution** below. Tracked as future direction in §Known Compromises.

**Smallest change** that delivers periodic visibility and a self-maintaining schedule:

- One `NotificationService` over `flutter_local_notifications` (already a dep).
- One pure reconciler that maps an `AgendaResponse` to a desired set of scheduled notifications and diffs against what is currently scheduled.
- Four fixed-time daily summaries (morning / noon / afternoon / evening) that report current action-item activity.
- Per-occurrence reminders for routines (which carry `start_time`).
- A best-effort background refresh (workmanager) plus a foreground "fetch if stale" trigger to keep the schedule fresh.

---

## Goals

- Send **four daily summaries** at fixed local times — 09:00 (morning), 12:00 (noon), 15:00 (afternoon), 19:00 (evening) — each summarizing action-item activity for today (counts: open, done, dismissed). Tap → `/agenda`.
- Send a **per-occurrence reminder** at the exact `start_time` of every non-skipped routine occurrence for today. Tap → `/agenda`.
- Keep the scheduled set fresh by re-running the reconciler:
  - Every time the agenda is fetched in the foreground (P021 flow on Agenda tab open / pull-to-refresh).
  - On app foreground if >1 hour has passed since the last successful agenda fetch.
  - At least once per hour in the background, best-effort (workmanager).
- Provide a fast notification-tap path: from cold start, opening via notification deep-links to `/agenda`, which renders cached data immediately (P021 cache).
- Skip reminder delivery while a hands-free session is active to avoid interrupting capture; reconcile on session end to surface what was suppressed.
- Replace the PoC ("Come back" 30 s after pause) entirely.
- Work on iOS 16+ and Android 7+ with graceful degradation when the OS denies background execution or notification permission.

## Non-Goals

- Configurable summary times in V1 — hardcoded 09:00 / 12:00 / 15:00 / 19:00. Follow-up if requested.
- Per-action-item reminders at exact times — blocked on backend exposing a timestamp. Tracked in §Known Compromises and §Open Questions.
- Notification actions ("Mark done" / "Skip" inline) — tap deep-links to agenda only.
- Push channel (APNs / FCM).
- Multi-day summaries (tomorrow / week) — today only.
- Per-template reminders inside a routine occurrence — only the occurrence itself fires once.
- LLM-generated summary copy — deterministic count format in V1.
- Calendar integration / `EKEventStore`.
- Master in-app notification toggle in Settings — V1 relies on the OS-level toggle. Follow-up if needed.

## User-Visible Changes

After P040, with notifications permitted:

- **Four times a day** the user gets a notification like **"Morning: 3 open, 2 done, 1 dismissed"** (or **"Morning: nothing scheduled today"** if zero). Tap → app opens directly on `/agenda`.
- **At each routine occurrence `start_time`** the user gets a notification with the routine name (e.g. **"Morning routine"**). Tap → `/agenda`.
- The "Come back 30 s after you left" notification is gone.
- Tapping any notification from a force-quit state opens to a fully populated `/agenda` (cached snapshot from last fetch) within one frame — no blank loading state.

First launch after upgrade:

- iOS: existing permission grant from the PoC is reused (same plugin).
- Android 13+: `POST_NOTIFICATIONS` runtime prompt appears on first reconciler run.
- Both: workmanager background task registers silently.

If notification permission is denied: app continues to work; no notifications fire; no crash, no nag.

---

## Solution Design

### Components

```
core/notifications/                          # NEW
  domain/
    notification_service.dart                # NotificationService + ScheduledNotification
  data/
    local_notification_service.dart          # flutter_local_notifications impl
  agenda_notification_scheduler.dart         # Pure reconciler (AgendaResponse → desired set, diff vs current)
  notification_providers.dart                # SERVICE providers only (no ephemeral state)

core/providers/                              # existing
  deep_link_providers.dart                   # NEW — pendingDeepLinkProvider + notificationTapStreamProvider
                                             # (ephemeral cross-feature state per ADR-ARCH-008)

core/background/                             # already exists (FG-service from P026/P027, see below)
  workmanager_core_boot.dart                 # NEW — core-only dep bundle (storage + config + ApiClient +
                                             # notification service). Does NOT import features/ —
                                             # respects ADR-ARCH-003. Called by foreground init AND
                                             # background isolate entrypoint.

features/agenda/presentation/
  agenda_notifier.dart                       # MODIFIED — call reconciler after fetch; write last-fetch-at;
                                             #            listen to sessionActiveProvider edge.

app/background/                              # NEW directory
  agenda_refresh_entrypoint.dart             # workmanager @vm:entry-point. App-layer code, allowed to
                                             # import features/agenda/ to wire AgendaRepository +
                                             # AgendaNotificationScheduler atop the core bundle.
  register_agenda_refresh.dart               # registerAgendaRefresh() — called from app_main.dart.

app/
  app_shell_scaffold.dart                    # MODIFIED — ref.watch(agendaNotifierProvider) to promote
                                             # it to app scope per ADR-ARCH-009 (criteria 1-3 satisfied).
  app_main.dart                              # MODIFIED — read pending deep link, init notif service,
                                             # registerAgendaRefresh, await coreBoot.
  app.dart                                   # MODIFIED — staleness check on resume; remove PoC hook;
                                             # consume pendingDeepLinkProvider on first frame.
```

Note on `core/background/` co-tenancy: the directory **already exists** with FG-service files (`flutter_foreground_task_service.dart`, `background_service.dart`, `background_service_provider.dart`) from P026/P027 — those are *foreground-service* abstractions (controller-owned per ADR-PLATFORM-006). The new `workmanager_core_boot.dart` is a *periodic background task* helper — a different mechanism with no shared code. Filename prefix `workmanager_` disambiguates intent; the two purposes coexist in the same directory without coupling.

Deleted:

- `lib/core/notifications/come_back_notifier.dart`
- `lib/app/app.dart` lifecycle switch arms for paused/resumed (the `WidgetsBindingObserver` itself stays — repurposed for the staleness foreground trigger).
- `docs/proposals/POC-come-back-notification.md` is **kept**; status updated to `Superseded by P040`.

### Time Resolution (addresses P0 from review)

Action items expose only `scheduled_for: YYYY-MM-DD` (per `personal-agent/docs/api.md`) — no time-of-day. Routine occurrences expose `start_time: "HH:MM"` (nullable) on top of their date.

**Decisions:**

1. **Action items** in V1 are *not* scheduled as per-item OS notifications. Instead, they are aggregated into the four fixed-time daily summaries (counts of open/done/dismissed). When the backend exposes a per-item timestamp, P041 will add direct per-item reminders.
2. **Routine occurrences** with `start_time != null` are scheduled as direct reminders at today + `start_time` parsed in the **device-local timezone** (see Timezone Handling below). Occurrences with `start_time == null` are *not* scheduled as direct reminders; they appear in the next summary's "open" count via the agenda screen.
3. **Status mapping** for the summaries (one row per recordable status of `RecordStatus`, defined in `core/models/conversation_record.dart`):
   - `open` = `RecordStatus.active`
   - `done` = `RecordStatus.done` ∪ `RecordStatus.promoted`
     (`promoted` is a positive resolution — the record was elevated to a routine; counting it as "done" matches user intuition.)
   - `dismissed` = `RecordStatus.superseded`
     (the record was replaced by a newer version of the same intent.)

If `RecordStatus` later adds a true `dismissed` variant or splits the semantics further, the reconciler's mapping changes in one place (a `Map<RecordStatus, SummaryBucket>` lookup table).

### Timezone Handling (addresses P1 from review)

The PoC initialized `timezone` with `tz_data.initializeTimeZones()` only — that leaves `tz.local == UTC`. P040 schedules absolute wall-clock times ("next 09:00 local"), so we must set the device IANA zone explicitly.

`LocalNotificationService.init()`:

1. `tz_data.initializeTimeZones()`
2. Read the device IANA zone name via `flutter_native_timezone` (new dep, see §Affected Mutation Points).
3. `tz.setLocalLocation(tz.getLocation(name))`.

The reconciler uses `tz.TZDateTime.now(tz.local)` for "now" and constructs all fire instants in `tz.local`. Unit tests inject a fixed `Clock now` and a fixed `Location` to make assertions deterministic.

### `NotificationService` (domain)

Contract (signatures only; no method bodies):

- `ScheduledNotification` value type — fields: `id (int)`, `title (String)`, `body (String)`, `fireAt (tz.TZDateTime)`, `payload (String)`.
- `Future<void> init()`
- `Future<bool> requestPermission()` — returns `true` iff granted.
- `Future<bool> isPermitted()`
- `Future<void> schedule(ScheduledNotification n)`
- `Future<void> cancel(int id)`
- `Future<Set<int>> currentlyScheduledIds()`
- `Future<void> cancelAll()`

The interface lives in `core/notifications/domain/`. Both feature code and the background entrypoint depend on the contract, not on the data adapter.

### `LocalNotificationService` (data)

Wraps `FlutterLocalNotificationsPlugin`. Implementation notes (not full code):

- `init()` performs the timezone setup above and wires `InitializationSettings` for iOS (DarwinInitializationSettings — alert, badge, sound) and Android.
- `requestPermission()` delegates to plugin's iOS and Android 13+ permission requests; returns OR of granted flags.
- `schedule()` uses `zonedSchedule()` with `AndroidScheduleMode.exactAllowWhileIdle` for routine-occurrence reminders, `inexactAllowWhileIdle` for summaries (drift of minutes is fine for summaries; an occurrence must be exact). `UILocalNotificationDateInterpretation.absoluteTime`. Payload stores the deep-link target string.
- `currentlyScheduled()` returns the **in-memory snapshot** `Map<int, ScheduledNotification>` (see Diff Strategy below). `currentlyScheduledIds()` is a thin wrapper returning the map's keys.
- Notification-tap callback (`onDidReceiveNotificationResponse`) pushes the payload to a `StreamController<String>` exposed via `notificationTapStreamProvider`.

**Diff Strategy.** The plugin's `pendingNotificationRequests()` returns IDs reliably across iOS and Android but body/fireAt fields are platform-inconsistent. To make the diff value-stable (catching summary-body drift, not just ID presence), `LocalNotificationService` maintains an in-memory `Map<int, ScheduledNotification> _scheduled` updated on every `schedule()`/`cancel()`/`cancelAll()`. The map is the source of truth for the reconciler diff.

On cold start the map is empty, so the first reconcile after launch computes `toCancel = ∅`, `toSchedule = desired`. Plugin semantics for `zonedSchedule` with an existing ID is "replace" — net effect: any OS-side stale body is overwritten with the fresh one, with no user-visible flicker. After force-quit-and-relaunch the same rebuild happens; we accept the one redundant OS write as the price of stateless cold-start.

iOS audio session note: `flutter_local_notifications` does not interfere with the existing `playAndRecord` session (ADR-AUDIO-009). Notification sounds use the OS notification channel.

### `AgendaNotificationScheduler` (pure reconciler)

Input: today's `AgendaResponse` + the current set of scheduled notification IDs.
Output: diff applied via the injected `NotificationService`.

Algorithm (pseudocode):

```
desired := { /* ScheduledNotification set */ }

for slot in [Morning(09:00), Noon(12:00), Afternoon(15:00), Evening(19:00)]:
  desired.add(summaryNotification(slot, response))   // id = SUMMARY_IDS[slot]

if sessionActiveProvider.value == false:           // session gating
  for occurrence in response.routineItems:
    if occurrence.status != skipped
       and occurrence.occurrenceId != null
       and occurrence.startTime != null:
      fireAt := todayAt(occurrence.startTime)      // tz.local
      if fireAt > now(tz.local):
        desired.add(routineReminder(occurrence, fireAt))   // id = routineId(occurrenceId)

current   := await service.currentlyScheduled()    // Map<int, ScheduledNotification>
toCancel  := { id for id in current.keys if id not in desired.ids }
toSchedule := { n for n in desired
                if n.id not in current
                   or current[n.id] != n }          // value-equality, catches body/fireAt drift

for id in toCancel:    await service.cancel(id)
for n  in toSchedule:  await service.schedule(n)    // plugin replaces on existing id
```

Idempotent. Diff-based — re-running with the same input yields zero plugin calls.

**Summary notification body**, given counts `(open, done, dismissed)`:
- All zero → `"<Slot>: nothing scheduled today"`.
- Otherwise → `"<Slot>: {open} open, {done} done, {dismissed} dismissed"`, eliding zero terms (e.g. `"Noon: 3 open, 1 done"`). Pluralization is not localized — single-form copy is acceptable in V1 ("1 open" reads as well as "1 open item" for a glanceable banner).

Because body is part of the diff value-equality, a reconciler run that observes new counts (e.g. user marked an item done between 11:00 and 11:30) cancels and re-schedules the 12:00 summary with updated copy. No stale-body drift through the day.

**Past slot handling**: if the reconciler runs at 13:00, the 09:00 and 12:00 slots are already past. Those summaries schedule for *tomorrow* at the same time, so the next day's morning/noon notifications are queued ahead. The reconciler runs every foreground fetch — tomorrow's queue stays fresh through the day.

**Non-today date guard** (addresses P2 from review): the reconciler operates only on today's response. The notifier calls it only when `_selectedDate == today`. When the user views tomorrow's agenda, no reconcile fires — that response is for browsing, not for scheduling.

**Stale-cache guard** (addresses P2): reconciler is called only from `AgendaState.loaded`, never from `error(cached)`. Stale data must not drive OS notifications.

### ID Mapping

`flutter_local_notifications` requires a stable `int` per notification.

```
SUMMARY_BASE = 1000
  Morning   = 1000
  Noon      = 1001
  Afternoon = 1002
  Evening   = 1003

routineReminderId(occurrenceId)  = 3_000_000 + crc32(occurrenceId) & 0x7FFFFFFF
```

Reserved range 2_000_000–2_999_999 left empty for future per-item action-item reminders (P041).

Collision risk for routine IDs is negligible at expected scale (birthday-paradox approximation: ~10⁻⁵ at the upper bound of ~200 simultaneously scheduled IDs). On collision, the plugin's `schedule()` replaces the existing entry — the second routine wins; previous one is silently dropped. Logged at debug level for visibility.

### Reconciler Triggers

For triggers #1, #2, and #4 to reach `AgendaNotifier` regardless of whether the Agenda tab has been visited, `agendaNotifierProvider` is **promoted to app scope per ADR-ARCH-009**. `AppShellScaffold` adds a single `ref.watch(agendaNotifierProvider)` to keep the notifier alive for the app's lifetime. ADR-ARCH-009 criteria are satisfied:

- Criterion 1 (cross-screen / cross-feature events) — yes: `sessionActiveProvider` edges and `WidgetsBindingObserver.resumed` are app-lifecycle triggers fired regardless of the visible screen.
- Criterion 2 (negligible idle cost) — yes: the notifier holds a single `AgendaState` snapshot; no streams, no timers, no open network connections.
- Criterion 3 (screen-level behavior preserved) — yes: `AgendaScreen` continues to read the same provider; `loadAgenda()` calls become idempotent (already are — same date re-fetch is a no-op via diff).

Triggers:

1. **Foreground — after successful `AgendaNotifier.loadAgenda()` for today's date.** Called fire-and-forget from the notifier after `state = loaded(...)`. Failure logged and swallowed; agenda screen still works.
2. **App-foreground staleness check.** In `app.dart`'s `WidgetsBindingObserver` (repurposed from the PoC), on `AppLifecycleState.resumed`: if `now - lastAgendaFetchAt > 1h`, call `ref.read(agendaNotifierProvider.notifier).refresh()`. Reachable because the provider is app-scoped.
3. **Background — every ~1h via workmanager.** Best-effort. Operates without `AgendaNotifier` (the bg entrypoint uses `coreBoot` + `wireAgendaForBackground` directly). See next section.
4. **App startup.** After `coreBoot()` completes in `app_main.dart`, kick `ref.read(agendaNotifierProvider.notifier).refresh()`. Provider exists from first frame because `AppShellScaffold` is in the widget tree.

`lastAgendaFetchAt` is **persisted in `core/config/app_config_service.dart`** — the same SharedPreferences-backed service that already stores API URL and token. New keys: `last_agenda_fetch_at` (ISO-8601 string, nullable). Chosen over the JSON cache file because (a) SharedPreferences is reachable from the workmanager isolate without re-parsing the cache file, (b) the value is config-shaped (one scalar timestamp), not cache-shaped, (c) `AppConfigService` is already on the foreground boot path and is part of the `HeadlessBoot` bundle.

The value is updated by `AgendaNotifier` on every successful `loaded` transition, and read by trigger #2 (foreground staleness check) and the workmanager entrypoint (50-min skip guard).

### Background Refresh (addresses P0 from review)

**ADR re-opening.** P005 §Alternatives and ADR-NET-002 previously dismissed `workmanager`. P040 amends ADR-NET-002 to permit `workmanager` **only** for agenda reconciliation (this proposal), not for sync. The carve-out is narrow: a single periodic task with one job — fetch today's agenda and reconcile notifications. Sync continues to be governed by foreground-or-active-session per ADR-NET-002 + P027.

**Plugin**: `workmanager: ^0.5.2`.

**Two-layer bootstrap (addresses ADR-ARCH-003 violation flagged by architectural review).**

The bootstrap splits along the dependency-rule line:

1. **`core/background/workmanager_core_boot.dart`** — `coreBoot()` returns `CoreBootBundle`, containing only `core/`-layer dependencies:

   ```
   class CoreBootBundle {
     StorageService storage;
     AppConfigService config;
     ApiClient api;
     NotificationService notifications;     // initialized
   }

   Future<CoreBootBundle> coreBoot();
   ```

   No imports from `features/`. Safe to live in `core/`.

2. **`app/background/agenda_refresh_entrypoint.dart`** — the workmanager `@pragma('vm:entry-point')` function. App-layer code, *allowed* to import `features/agenda/` to construct `ApiAgendaRepository` and `AgendaNotificationScheduler` atop the core bundle. The entrypoint composes feature-level wiring from the core bundle the same way `app_main.dart` does in the foreground.

3. **`app/background/register_agenda_refresh.dart`** — `registerAgendaRefresh()` calls `Workmanager().initialize(...)` with the entrypoint and `registerPeriodicTask(...)`. Called from `app_main.dart`.

This split ensures `core/` never imports `features/` (CLAUDE.md verification grep passes) while still providing the parity-gate property: foreground `app_main.dart` and the background entrypoint both call `coreBoot()` *and* both compose feature dependencies the same way (a small `wireAgendaForBackground(CoreBootBundle)` helper in `app/background/` is the second shared call). A unit test asserts both paths use these two helpers and nothing else for dependency construction.

**Isolate boot sequence** for `executeTask` (addresses the "fresh `ProviderContainer` won't hydrate" P0):

1. `WidgetsFlutterBinding.ensureInitialized()`.
2. `final core = await coreBoot();` — initializes SQLite, reads SharedPreferences-backed API config, builds `ApiClient`, builds + initializes `LocalNotificationService` (which sets up timezone via `flutter_native_timezone`).
3. `final agenda = wireAgendaForBackground(core);` — constructs `ApiAgendaRepository` and `AgendaNotificationScheduler` from the core bundle.
4. **Dev flavor only:** `Telemetry.bootIfEnabled(core.storage)` per ADR-OBS-001. Stable flavor: no-op. The flavor is detected via `const String.fromEnvironment('FLAVOR')` at build time (same mechanism as `main_dev.dart` / `main_stable.dart`).
5. If `now - core.config.lastAgendaFetchAt < 50 min`, return `true` — recently refreshed by foreground.
6. Else, inside a `Telemetry.span('bg.agenda_refresh')` (dev) or plain block (stable):
   `agenda.repository.fetchAgenda(today)` → `agenda.scheduler.reconcile(...)` → `core.config.setLastAgendaFetchAt(now)`.
7. On any throw, return `false` (workmanager retries with backoff).

**Parity-gate test.** A unit test (T2) asserts:
- `app_main.dart` foreground init calls `coreBoot()` then `wireAgendaForBackground()` (exact same pair).
- `app/background/agenda_refresh_entrypoint.dart` calls `coreBoot()` then `wireAgendaForBackground()` (exact same pair).
- Neither path open-codes dependency construction.

If a future foreground refactor adds a step outside these helpers, the test fails — drift is caught at CI, not on a device after iOS BGTask flakiness obscures it.

**Foreground bundle injection into ProviderScope** (addresses architectural-review P2-2). After `coreBoot()` and `wireAgendaForBackground()` return, `app_main.dart` injects the constructed instances as `ProviderScope` overrides so that providers consumed by widgets resolve to the *same* objects the helpers built. The override list is exhaustive (no provider that depends on these instances may be left to default construction). Overrides:

```dart
ProviderScope(
  overrides: [
    storageServiceProvider.overrideWithValue(core.storage),
    appConfigServiceProvider.overrideWithValue(core.config),
    apiClientProvider.overrideWithValue(core.api),
    notificationServiceProvider.overrideWithValue(core.notifications),
    agendaRepositoryProvider.overrideWithValue(agenda.repository),
    agendaNotificationSchedulerProvider.overrideWithValue(agenda.scheduler),
  ],
  child: const App(...),
);
```

`agendaNotifierProvider` is **not** overridden — it depends on `agendaRepositoryProvider` and `agendaNotificationSchedulerProvider` which already are, so the notifier constructs lazily with the correct dependencies on first read. The parity-gate test also asserts that this override list is exactly the set of providers whose values are constructed by the two helpers, so a future foreground-side provider added without corresponding override causes test failure.

**Scheduling**:

- `Workmanager().initialize(backgroundEntrypoint, isInDebugMode: kDebugMode)` from `app_main.dart`.
- `Workmanager().registerPeriodicTask('agenda-refresh', 'agendaRefresh', frequency: 1h, constraints: networkType=connected, existingWorkPolicy: KEEP)`.
- `@pragma('vm:entry-point')` on the entrypoint (required for tree-shaking).

**Platform realities (kept from R0):**
- **iOS**: BGAppRefreshTask is opportunistic. The system decides when to run. "Once per hour" is an upper bound that the OS may ignore. Documented as known limitation; foreground staleness trigger compensates.
- **Android**: WorkManager periodic minimum is 15 min and is reliable.

**iOS plist identifier**: workmanager 0.5.x uses a plugin-fixed identifier (`be.tramckrijte.workmanager.iOSBackgroundAppRefresh`). The exact string is verified in §Open Questions and pinned in T2.

### Deep Linking (addresses P1 from review)

Two channels with a single invariant: **`pendingDeepLinkProvider` is consumed exactly once on first frame; thereafter all taps route through `notificationTapStreamProvider`.**

**Cold start (force-quit + tap):**

1. In `app_main.dart`, *before* `runApp`:
   - `final launchDetails = await plugin.getNotificationAppLaunchDetails();`
   - `final pendingDeepLink = launchDetails?.didNotificationLaunchApp == true ? launchDetails!.notificationResponse?.payload : null;`
2. Store `pendingDeepLink` in `StateProvider<String?> pendingDeepLinkProvider` (StateProvider, so we can clear it).
3. In `App.build()`, register `addPostFrameCallback` on first frame:
   - read `pendingDeepLinkProvider`; if non-null, `router.go(value)`; then `ref.read(pendingDeepLinkProvider.notifier).state = null`.

**Warm start (tap while app is alive in background):**

1. `LocalNotificationService.init()` registers `onDidReceiveNotificationResponse` *after* `getNotificationAppLaunchDetails()` has been read — so the cold-start payload is never observed twice.
2. Each tap pushes payload to `notificationTapStreamProvider`.
3. `App` subscribes via `ref.listen` and routes accordingly.

**Init-window edge case:** if a notification arrives in the narrow window between `getNotificationAppLaunchDetails()` returning null and `onDidReceiveNotificationResponse` being registered, the tap is lost (no payload delivered to either channel). Acceptable for V1 — the window is <100 ms during boot. Manual test #5 covers cold and warm; we do not test the init-window case (impossible to reproduce reliably).

**Cache-first rendering** (addresses user requirement: "by po kliknięciu w powiadomienie można było do niej przekierować"): `/agenda` is owned by `AgendaScreen` which reads `AgendaState` from `AgendaNotifier`. The notifier already starts with `state = loading(cached)` if cache exists (P021). So a tap from cold start lands on a populated screen within one frame, even before the network fetch completes. No additional code is needed for this; just verified in acceptance criteria.

### Session Gating (addresses P1 from review)

When `sessionActiveProvider.value == true` (hands-free session running), the reconciler omits **routine-occurrence reminders** from the desired set. Summaries are still scheduled — they are best-effort heads-up texts, not session-disruptive.

On session end, `HandsFreeController._terminateWithError` and `stopSession` already flip `sessionActiveProvider` to `false`. The listener for `sessionActiveProvider` is registered inside `AgendaNotifier`'s constructor — reachable because the provider is app-scoped (see §Reconciler Triggers preamble). On the `true → false` edge it calls `refresh()` (full fetch-then-reconcile, not just reconcile-from-cache). Rationale: a session can last 30+ minutes, during which an occurrence may have been added via the web UI; only a fresh fetch surfaces it. Mirrors trigger #2 (>1h foreground staleness).

On the `false → true` edge, the listener triggers reconcile-only (no fetch — we already have the data and the session needs the network for its own work). The reconciler's session-aware branch then cancels per-occurrence reminders for the rest of today. They re-appear on the next `true → false` edge via the refresh path.

This keeps `sessionActiveProvider` as the single source of truth for "audio is primary." No new flag.

### Permission Flow

**Where the prompt fires** (addresses architectural-review P2-1). The reconciler's first action is `if (!await service.isPermitted()) return;`, so it cannot itself be the prompt site — a denied-state reconcile silently no-ops. The actual prompt is an explicit call to `notificationService.requestPermission()` issued from `app_main.dart` *after* `coreBoot()` completes and *before* the first reconcile is kicked. The call is fire-and-forget for the result; whatever the user picks, the next reconcile reads the resolved state via `isPermitted()` and either proceeds or short-circuits.

On subsequent app launches, `requestPermission()` is still called but is a no-op when permission is already granted or has been denied with "don't ask again" (Android). The user-facing flow:

- **First launch:** OS dialog appears once during `app_main.dart` boot.
- **Subsequent launches:** silent re-check, no UI.

Platform specifics:

- **iOS**: `requestPermission()` delegates to `flutter_local_notifications`' iOS permission API (alert + badge + sound). Reuses the PoC's existing grant when present.
- **Android 13+**: `requestPermission()` delegates to `requestNotificationsPermission()`. `POST_NOTIFICATIONS` already in manifest. Pre-13 devices don't need a runtime prompt.
- **Android 12+ exact alarm**: per-occurrence reminders use `exactAllowWhileIdle`. Add `USE_EXACT_ALARM` (granted by default for alarm/reminder apps under Play's policy). If Play later flags the use-case, fall back to `inexactAllowWhileIdle` (~10 min drift acceptable).
- **Revocation handling**: on every reconcile, if `isPermitted()` returns `false` and the previous run was `true` (tracked in a small state-bit in `LocalNotificationService`), call `cancelAll()` once to clean the OS queue (per ADR-NOTIF-001).

The background isolate path **does not call** `requestPermission()` — it cannot show UI. It only reads `isPermitted()` and short-circuits if false. The first foreground launch after install is the only prompt site; if the user denies, the bg path will repeatedly short-circuit until the user opens the app again (which calls `requestPermission()` again — no-op if Android "don't ask again" was selected; OS dialog otherwise).

### Removal of PoC

- Delete `lib/core/notifications/come_back_notifier.dart`.
- Repurpose `lib/app/app.dart` `WidgetsBindingObserver`: keep the observer, replace the paused/resumed switch arms with the staleness check (trigger #2 above).
- Replace `ComeBackNotifier.instance.init()` call in `app_main.dart` with the new init sequence (notification service init, workmanager register, pending-deep-link read).
- Update `docs/proposals/POC-come-back-notification.md` Status to `Superseded by P040`.

---

## Affected Mutation Points

**Needs change:**

- `lib/core/notifications/come_back_notifier.dart` — **delete**.
- `lib/core/notifications/domain/notification_service.dart` — **new**. Interface + `ScheduledNotification` value type.
- `lib/core/notifications/data/local_notification_service.dart` — **new**. Plugin wrapper, timezone init, permission, schedule/cancel/list.
- `lib/core/notifications/agenda_notification_scheduler.dart` — **new**. Pure reconciler with injected `Clock` for testability.
- `lib/core/notifications/notification_providers.dart` — **new**. **Service providers only**: `notificationServiceProvider`, `agendaNotificationSchedulerProvider`. No ephemeral state.
- `lib/core/providers/deep_link_providers.dart` — **new**. Ephemeral cross-feature state per ADR-ARCH-008: `pendingDeepLinkProvider` (StateProvider<String?>, one-shot consumed on first frame) and `notificationTapStreamProvider` (StreamProvider<String>). Placed in `core/providers/` to match the existing convention used by `sessionActiveProvider`, `appForegroundedProvider`, etc.
- `lib/core/background/workmanager_core_boot.dart` — **new**. `coreBoot()` returning `CoreBootBundle` (storage, config, api, notifications). Core-only — no imports from `features/`. Existing SQLite init code in `app_main.dart` moves here. Co-located with existing FG-service files; disambiguated by `workmanager_` filename prefix.
- `lib/app/background/agenda_refresh_entrypoint.dart` — **new**. `@pragma('vm:entry-point')` function. App-layer; imports `features/agenda/` to wire `AgendaRepository` and `AgendaNotificationScheduler` over the core bundle.
- `lib/app/background/register_agenda_refresh.dart` — **new**. `registerAgendaRefresh()`; called from `app_main.dart`.
- `lib/app/background/wire_agenda_for_background.dart` — **new**. `wireAgendaForBackground(CoreBootBundle)` — shared feature-wiring helper used by foreground init AND the bg entrypoint. Parity gate (see §Background Refresh). Top-of-file doc comment declares: "This file is the canonical feature-wiring helper for background isolates. New feature wiring helpers follow the `wire_<feature>_for_background.dart` naming convention (per ADR-PLATFORM-007 Consequences §1) so reviewers can locate them by pattern."
- `lib/core/config/app_config_service.dart` — modified. Add `lastAgendaFetchAt` getter/setter backed by SharedPreferences key `last_agenda_fetch_at` (ISO-8601 string, nullable). One new method pair; no schema migration. (Per ADR-ARCH-005 amendment: cross-isolate-safe scalar config store.)
- `lib/features/agenda/presentation/agenda_notifier.dart` — modified:
  - constructor takes `AgendaNotificationScheduler` and `AppConfigService` (the existing one, just one new method pair on it).
  - on `loaded`, write `appConfig.setLastAgendaFetchAt(now)` and (if `_selectedDate == today`) fire-and-forget reconcile with try/catch.
  - `ref.listen(sessionActiveProvider, ...)`: on `true → false` call `refresh()` (full fetch-then-reconcile); on `false → true` call reconciler directly with current `state.loaded.response` (cancels per-occurrence reminders without fetch).
- `lib/features/agenda/presentation/agenda_providers.dart` — inject new deps.
- `lib/app/app_main.dart`:
  - move SQLite bootstrap call to use the new shared helper.
  - read pending deep link via `getNotificationAppLaunchDetails()` *before* `runApp`.
  - `await notificationServiceProvider.init()`, `await registerAgendaRefresh()`.
  - delete `ComeBackNotifier.instance.init()` call.
- `lib/app/app.dart`:
  - keep `WidgetsBindingObserver`; replace switch arms with staleness check (trigger #2).
  - on first frame, consume `pendingDeepLinkProvider` and route if present.
  - delete `ComeBackNotifier` import.
- `ios/Runner/Info.plist`:
  - extend `BGTaskSchedulerPermittedIdentifiers` with `be.tramckrijte.workmanager.iOSBackgroundAppRefresh` (subject to §Open Questions verification).
  - add `UIBackgroundModes` array containing `fetch`.
- `android/app/src/main/AndroidManifest.xml`:
  - add `<uses-permission android:name="android.permission.USE_EXACT_ALARM"/>`.
  - add `<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>` — required so WorkManager re-registers the periodic task after device reboot; without it the schedule resumes only when the user opens the app post-reboot.
- `pubspec.yaml`: add `workmanager: ^0.5.2`, `flutter_native_timezone: ^2.0.0` (or current equivalent).
- `docs/decisions/ADR-NET-002-foreground-only-sync.md` — amend Decision, Rationale, Consequences with the `workmanager`-for-agenda-only carve-out (text in §ADR Impact). **Sync semantics unchanged.** Third amendment caveat noted.
- `docs/decisions/ADR-ARCH-005-app-config-in-core.md` — add cross-isolate-safety consequence (text in §ADR Impact).
- `docs/decisions/ADR-PLATFORM-007-shared-core-boot-helper.md` — **new**. Draft text in §ADR Impact.
- `docs/decisions/ADR-NOTIF-001-diff-based-reconciliation-with-id-partitioning.md` — **new**. Draft text in §ADR Impact.
- `docs/decisions/ADR-PLATFORM-008-two-channel-deep-link.md` — **new**. Draft text in §ADR Impact.
- `docs/proposals/POC-come-back-notification.md` — Status set to `Superseded by P040`.

**No change needed:**

- `lib/main_dev.dart` and `lib/main_stable.dart` — per-flavor entrypoints unchanged; `app_main.dart` is the shared boot path per ADR-OBS-001. Background isolate detects flavor via `const String.fromEnvironment('FLAVOR')` at build time, not via runtime-injected Telemetry singleton (which doesn't exist in the isolate).
- `core/network/api_client.dart` — agenda fetch path unchanged.
- `core/models/agenda.dart` — model already complete (P021).
- `features/agenda/data/api_agenda_repository.dart` — `fetchAgenda(date)` and `_getCachedAgenda(date)` reused from the bg entrypoint. (Note: lazy 7-day cache cleanup at `api_agenda_repository.dart:124` now also runs from cold-start reconcile via the new app-startup trigger — observable change in *when* cleanup runs, not in *what* runs. Acceptable: cleanup is small, non-blocking.)
- Sync queue, transcript paths, hands-free session lifecycle (other than reading `sessionActiveProvider`).
- `AgendaScreen` UI — unchanged.

---

## Tasks

| # | Task | Layer | Notes |
|---|------|-------|-------|
| T1 | `NotificationService` interface + `LocalNotificationService` impl (timezone-correct via `flutter_native_timezone`) + `AgendaNotificationScheduler` reconciler (pure, injected `Clock`) + `notification_providers.dart`. Unit tests for reconciler diff logic, ID mapping, status mapping (open/done/dismissed), summary copy, session-gating branch, timezone correctness. | core/notifications | Single PR. ~300 LOC + tests. No platform calls in reconciler tests — `FakeNotificationService` + injected clock. |
| T2 | `core/background/workmanager_core_boot.dart` (`coreBoot()` → `CoreBootBundle`, core deps only) + `app/background/agenda_refresh_entrypoint.dart` (`@vm:entry-point`) + `app/background/register_agenda_refresh.dart` + `app/background/wire_agenda_for_background.dart` (shared feature wiring). Extend `core/config/app_config_service.dart` with `lastAgendaFetchAt`. iOS Info.plist + Android Manifest edits. `workmanager` + `flutter_native_timezone` deps in pubspec. Tighten ADR-NET-002 amendment text and the three new ADR drafts (ADR-PLATFORM-007, ADR-NOTIF-001, ADR-PLATFORM-008) if needed — files already landed on the proposal branch. Parity-gate unit test asserts foreground and bg paths both call `coreBoot()` + `wireAgendaForBackground()` and nothing else for dep construction. Manual device verification for the rest. | core/background, core/config, app/background, ios, android, docs | Single PR. Depends on T1. |
| T3 | Wire `AgendaNotifier` to scheduler + last-fetch-at + session-edge listener. Repurpose `app.dart` `WidgetsBindingObserver` for staleness check (>1h on resume → kick refresh). Wire `app_main.dart` to read pending deep link before `runApp`, init notification service, register bg task, hydrate `pendingDeepLinkProvider`. Delete `come_back_notifier.dart` + PoC import; mark PoC doc `Superseded by P040`. Update existing `agenda_notifier_test.dart` and `agenda_screen_test.dart` for new constructor deps. Add notifier-test cases: reconcile invoked on `loaded(today)`, not invoked on `loaded(non-today)` and not on `error(cached)`; session-edge triggers re-reconcile. | features/agenda, app, core/providers, docs | Single PR. Depends on T1, T2. |

T2 ships ~80 LOC of platform glue + plist/manifest + final ADR tightening (drafts already on proposal branch). The parity-gate unit test is the only automated coverage; isolate behavior is device-only beyond that. Manual verification table in §Test Impact is the gate.

---

## Test Impact / Verification

### Existing tests affected

- `test/features/agenda/presentation/agenda_notifier_test.dart` — constructor signature changes; add `FakeAgendaNotificationScheduler` and `FakeLastAgendaFetchAt` to ProviderScope overrides; new test cases listed in T3.
- `test/features/agenda/presentation/agenda_screen_test.dart` — `ProviderScope` overrides must include the new providers; no behavioral assertions change.

### New tests

- `test/core/notifications/agenda_notification_scheduler_test.dart` — reconciler cases:
  - Empty response → only the 4 summaries scheduled.
  - Response with N non-skipped routine occurrences (`start_time` non-null, future) → 4 + N scheduled.
  - Second call with same response → zero plugin calls (diff invariant).
  - Removed occurrence → that ID canceled, others untouched.
  - Past-start-time occurrence → not scheduled.
  - `occurrenceId == null` or `start_time == null` → not scheduled.
  - `sessionActiveProvider == true` → 4 summaries only; no occurrences.
  - Session edge `true → false` → reconcile re-adds occurrences.
  - Session edge `false → true` → reconcile cancels occurrences (summaries untouched).
  - Non-today `AgendaResponse` is never accepted by the reconciler (guard at notifier level; covered by notifier tests).
- `test/core/notifications/id_mapping_test.dart` — stable, within reserved ranges, kinds disjoint.
- `test/core/notifications/summary_copy_test.dart` — zero/non-zero/all-elided variants of the summary body.
- `test/core/notifications/local_notification_service_test.dart` — minimal: `init()` idempotent, request honors plugin return, schedule passes through (mocktail of `FlutterLocalNotificationsPlugin`). Timezone init covered separately by injecting a fake `flutter_native_timezone` shim.

### Manual verification (device-required)

Per [[no_apple_developer_account]] memory, iOS testing is on a personal-cert debug build on a physical iPhone.

| # | Setup | Expected |
|---|-------|----------|
| 1 | First launch in non-UTC zone (e.g. Europe/Warsaw). Grant notifications. Pull-to-refresh Agenda. Inspect `pendingNotificationRequests`. | Four summaries scheduled for today's next 09:00/12:00/15:00/19:00 *in Warsaw time*, plus one entry per future routine occurrence. |
| 2 | Force-quit. Wait 5 min. Reopen. | Pending list unchanged — diff was empty. |
| 3 | Add routine occurrence via web UI for 5 min from now. Leave app open with Agenda visible. | Within next foreground fetch, occurrence appears in pending list. At T+5min, notification fires. |
| 4 | Add occurrence via web UI. Lock phone. Wait ≥ 1 h. | iOS: best-effort. Android: WorkManager fires within ~1 h; occurrence is scheduled; reminder fires at its time. |
| 5 | Tap notification → app foregrounded → lands on `/agenda`. | Deep link routes correctly from both cold and warm start; agenda screen renders cached snapshot in first frame. |
| 6 | Force-quit. Wait until 09:00. | Morning summary fires (OS owns the schedule). Tap → opens `/agenda`. |
| 7 | Start hands-free session. Have a routine occurrence due in 2 minutes. | At T+2min, no notification (session gated). Stop session. Within one reconcile cycle, reminder either re-schedules for future or is dropped if past. |
| 8 | Deny notification permission. | App runs, agenda fetches, no notifications scheduled, no crash. |
| 9 | Grant permission, run reconcile, revoke in OS settings, run reconcile again. | `cancelAll()` fires; `pendingNotificationRequests` empty after second reconcile. |
| 10 | App in background for 2 hours. Bring to foreground. | `WidgetsBindingObserver.didChangeAppLifecycleState(resumed)` fires; staleness check sees >1h; `refresh()` kicked; reconcile runs. |
| 11 | After upgrade from PoC version: confirm "Come back" notification never fires after 30 s background. | PoC removed. |

### Commands

```bash
cd voice-agent && make verify
```

---

## Acceptance Criteria

1. With notifications granted and at least one future non-skipped routine occurrence with non-null `start_time` for today, opening the Agenda tab schedules four summary notifications (09:00/12:00/15:00/19:00 local) plus one per occurrence. Verified via `pendingNotificationRequests()`.
2. After force-quitting the app, scheduled notifications still fire at their times (iOS guaranteed; Android subject to OEM force-quit handling — documented in §Risks).
3. At each of 09:00, 12:00, 15:00, 19:00 local, a summary notification fires with copy of the form `"<Slot>: X open, Y done, Z dismissed"` or `"<Slot>: nothing scheduled today"`. Tap deep-links to `/agenda`.
4. At each routine occurrence's `start_time` (today, non-null, non-skipped), a notification fires with the routine name. Tap deep-links to `/agenda`.
5. Skipped routines and occurrences with `start_time == null` produce no per-occurrence notification but are counted in summary `open` totals.
6. Reconciler called with the same `AgendaResponse` twice produces zero `schedule`/`cancel` calls on the second invocation.
7. Removing or completing an occurrence (via web UI then refresh, or via the agenda screen) cancels its pending notification within one reconcile cycle.
8. Denying notification permission on first prompt results in: reconcile short-circuits, no scheduled notifications, agenda screen still works, no crash.
9. Cold-launching via notification tap routes to `/agenda` and renders cached agenda data in the first frame (no blank loading state).
10. Bringing the app to foreground after >1 hour idle kicks a refresh; agenda is re-fetched and reconciler re-runs.
11. With `sessionActiveProvider == true`, per-occurrence reminders do not fire. On session end, the next reconcile re-adds future occurrences to the OS queue.
12. Workmanager background task is registered; on Android, periodic execution observable in logcat under `WM-WorkSpec`. On iOS, registration succeeds (no plist mismatch).
13. PoC "Come back" notification never fires under any app-lifecycle transition.
14. `lib/core/notifications/come_back_notifier.dart` no longer exists in the tree.
15. `flutter analyze` passes with zero issues; `flutter test` passes; no cross-feature imports.
16. Notifications scheduled in `Europe/Warsaw` while device clock is `Europe/Warsaw` actually fire in `Europe/Warsaw` (not UTC).

---

## Risks

| Risk | Mitigation |
|------|------------|
| iOS BGAppRefreshTask never runs (low-power mode, low-usage app). | Foreground >1h staleness trigger and Agenda-tab fetch keep schedule fresh whenever user opens the app. Documented as known limitation. |
| Background isolate boot in workmanager diverges from foreground boot when foreground code is refactored. | Shared `core/storage/storage_bootstrap.dart` is the single SQLite boot helper used by both paths. Lint rule (or comment) on `app_main.dart` to use the helper rather than open-coding. |
| Timezone misconfiguration ships UTC-only (PoC bug recurrence). | Manual verification #1 covers it. Unit test for `LocalNotificationService.init()` injects a fake `flutter_native_timezone` and asserts `tz.local` is set. |
| Notification flood with many routine occurrences. | OS-side: iOS/Android group/coalesce. App-side: scope limits per-occurrence to one notification per occurrenceId; no template-level fan-out. If user feedback shows noise, add a "max N per day" cap in P041. |
| Google Play rejects `USE_EXACT_ALARM` declaration. | Fall back to `inexactAllowWhileIdle` for occurrence reminders. One-flag change. |
| Notification during active hands-free session interrupts audio capture. | Session gating: per-occurrence reminders suppressed while `sessionActiveProvider == true`. Summaries still fire (visual banner only, no audio session interaction expected). |
| User-visible privacy: app fires notifications when phone is idle. | User-requested feature, not a surprise. OS-level toggle is the V1 master switch; in-app toggle is a follow-up. |
| Workmanager periodic task survives uninstall/reinstall with stale registration. | `ExistingWorkPolicy.keep` is idempotent. Reinstall starts fresh app data. Non-issue. |
| ID collision via CRC32. | Negligible at expected scale; plugin de-dups with replace semantics; logged at debug level. |
| `flutter_local_notifications` v18 API drift across iOS/Android. | Pin to version validated by PoC. Update is a separate concern. |
| Status mapping (`done = done ∪ promoted`, `dismissed = superseded`) may not match user mental model. | One-place `Map<RecordStatus, SummaryBucket>` lookup table in reconciler; revisit when `RecordStatus` adds a true `dismissed` variant. |
| Android OEM aggressive battery savers (Xiaomi/Huawei/OnePlus) kill scheduled alarms after force-quit. | Best-effort; document in release notes that user can whitelist the app in OEM-specific battery settings. iOS is unaffected. |
| Summary body drifts over the day (counts change at 10:30 but next reconcile is at 14:00). | Diff value-equality catches it: whenever a reconcile runs (foreground fetch, >1h staleness, hourly bg task), if the desired body differs from the in-memory snapshot, the summary is cancelled and re-scheduled. Between reconciles, the OS holds the most recent body. |

---

## Alternatives Considered

**Push (APNs / FCM).** Ruled out by no Apple Developer account ([[no_apple_developer_account]]).

**`cancelAll` then reschedule each tick.** Simpler code, but creates a swap window where the OS may either duplicate-display or drop-during-rate-limit. Diff-based avoids both.

**Schedule notifications inside `ApiAgendaRepository.fetchAgenda()`.** Couples cache concerns with notification scheduling. Reconciler stays separate, testable.

**ProviderContainer in background isolate.** Hidden hydration ceremony; foreground overrides don't transfer. Direct construction of dependencies in the entrypoint is explicit and avoids the trap.

**FG service (`flutter_foreground_task`) for hourly tick instead of workmanager.** Reuses P027 plumbing but only runs during hands-free sessions — most of the day idle. Doesn't meet the requirement.

**Single morning briefing (V0 from R0).** Replaced by four summaries on user request; same plumbing, four IDs instead of one.

**Per-action-item reminders with default times (e.g., 09:00).** Either duplicates the morning summary (noise) or requires a fragile heuristic. Action items aggregated into summaries is cleaner; per-item reminders return when backend exposes a per-item timestamp.

---

## Known Compromises and Follow-Up Direction

- **iOS hourly refresh is best-effort.** Documented. No app-side fix without paid Apple Developer + APNs `content-available: 1`.
- **No configurable summary times in V1.** Hardcoded 09:00/12:00/15:00/19:00.
- **No per-action-item exact-time reminders.** Blocked on backend exposing a timestamp (e.g., `scheduled_at: ISO-8601`). Tracked as **P041 — Action-item per-item reminders** (depends on personal-agent contract change). Until then, action items are visible only in summaries.
- **No notification actions.** Tap deep-links to agenda; "Mark done" inline requires a platform-channel handshake to call `markActionItemDone` from a background context. Follow-up.
- **No in-app master toggle.** OS-level toggle is V1 master.
- **Status mapping is interim.** `done = done ∪ promoted`, `dismissed = superseded`. Revisit when `RecordStatus` gains a true `dismissed` variant or the semantics are formalized.
- **Workmanager carve-out introduces a precedent.** If another use case wants periodic background work, the ADR-NET-002 amendment language allows it only for "agenda reconciliation." A new use case requires a new amendment.

If multiple `core/` modules grow background hooks beyond agenda reconcile, a shared `BackgroundJob` abstraction may be worth extracting. Not building it now — single instance.

---

## ADR Impact

`/proposal-architectural-review` (2026-05-17, two passes) confirmed three new ADRs and two amendments. Per the project's commit flow (CLAUDE.md "Proposal and ADR Commit"), all ADR files land on the same proposal-commit branch *before* implementation begins.

**Authoritativeness note:** the ADR files in `docs/decisions/` are the **canonical** source going forward. The summaries below are historical — they capture what was approved during proposal review. If wording drifts between the ADR file and the summary here, the ADR file wins. Final tightening (if any) happens during T2 on the same branch.

### New ADRs to author (committed with the proposal)

**ADR-PLATFORM-007 — Shared core boot helper for foreground and background isolates**
- *Status:* Proposed
- *Decision:* `core/background/workmanager_core_boot.dart::coreBoot()` returns a typed `CoreBootBundle` of `core/`-layer dependencies. It is the only place that constructs the core dep graph. Foreground (`app_main.dart`) and the workmanager isolate entrypoint (`app/background/agenda_refresh_entrypoint.dart`) both call it. Feature-level wiring lives in `app/background/wire_agenda_for_background.dart`, also called by both paths. No `ProviderContainer` is used in background isolates — overrides do not transfer across isolates and the hidden hydration ceremony is a trap.
- *Consequences:* Any new feature reachable from a background task adds itself to the parity-gate test asserting both paths use the two shared helpers. iOS BGTask flakiness is orthogonal — the helper guarantees that *when* the task runs, it sees the same world the foreground does.

**ADR-NOTIF-001 — Local notifications via diff-based reconciliation with reserved ID partitioning**
- *Status:* Proposed
- *Decision:*
  1. Local notifications only — no APNs / FCM until [[no_apple_developer_account]] changes.
  2. `LocalNotificationService` is the sole writer to the plugin queue. Reconciler is the sole writer to `LocalNotificationService`.
  3. Diff-based reconciliation against an in-memory `Map<int, ScheduledNotification>` snapshot (the plugin's `pendingNotificationRequests()` is platform-inconsistent on body/fireAt fields, so it cannot be the diff source).
  4. Reserved ID partitioning: summaries 1000–1003; action items 2_000_000–2_999_999 (P041); routine occurrences 3_000_000+ with `crc32(occurrenceId) & 0x7FFFFFFF`.
  5. Permission revocation handling: `cancelAll()` once on the false-after-true transition.
  6. Session gating via `sessionActiveProvider` (P027 contract).
- *Consequences:* New notification kinds claim a new range and amend this ADR. The "sole writer" invariant is enforced by code review. Cold-start rebuilds the OS queue (plugin replaces on ID match — idempotent).

**ADR-PLATFORM-008 — Two-channel cross-app-entry deep link with one-shot + stream invariant**
- *Status:* Proposed
- *Decision:* Cold-start deep links flow through `pendingDeepLinkProvider` (`StateProvider<String?>`, consumed exactly once on first frame). Warm-path taps flow through `notificationTapStreamProvider` (`Stream<String>`, registered after the cold-start read returns). Invariant: a single payload reaches exactly one channel.
- *Consequences:* Future cross-app-entry mechanisms (URL handlers, OAuth callbacks, share-target intents, Siri Shortcuts intents — relevant given Siri Shortcuts is the activation method per [[wake_word_dropped]]) reuse this two-channel shape. The <100 ms init-window edge case is acceptable and untested — re-tap recovers.

### ADR amendments (committed with the proposal)

**ADR-NET-002 (foreground-only sync) — third amendment**
- *Decision (carve-out):* Sync semantics unchanged. **Agenda notification reconciliation** may additionally run from a `workmanager` periodic task limited to one job: fetch today's agenda and update the OS notification queue. No general background sync introduced.
- *Rationale:* Reconciler freshness requirement (per ADR-NOTIF-001) requires a periodic refresh that foreground triggers alone cannot guarantee. Network surface remains a single `GET /agenda`. iOS BGTask is best-effort; the carve-out scope is justified by the cost of *not* running it (stale per-occurrence reminders).
- *Consequences:* `workmanager` ^0.5.2 enters the dep tree (this ADR is its sole authorization). Future "I want background X" requests need a separate decision.
- *Meta-note (third amendment caveat):* This is the third amendment to ADR-NET-002 after P027 (session-active) and P039 (dev-telemetry). If a fourth use case arises, consider restructuring this ADR (e.g., split into "general sync policy" + a registry of approved background exceptions) rather than adding a fourth carve-out.

**ADR-ARCH-005 (app-config-in-core) — consequence addition**
Add to Consequences:
> `AppConfigService` (SharedPreferences-backed) is the cross-isolate-safe configuration store: it can be read from background isolates (e.g., the workmanager agenda-refresh task per P040) without re-opening SQLite or re-parsing cache files. SQLite via `SqliteStorageService` also works from a background isolate (it is platform-isolate-safe), but SharedPreferences is the lighter choice for scalar config values used by short-lived background tasks.

### Existing ADRs cross-referenced (no amendment)

- `ADR-ARCH-003` (layered-feature-isolation) — respected: `core/background/workmanager_core_boot.dart` does not import `features/`. Feature wiring lives in `app/background/`. Architectural review explicitly verified.
- `ADR-ARCH-008` (ephemeral-cross-feature-state) — followed: `pendingDeepLinkProvider` and `notificationTapStreamProvider` live in `core/providers/deep_link_providers.dart` (canonical location).
- `ADR-ARCH-009` (provider-scope-promotion) — applied: `agendaNotifierProvider` promoted to app scope via `AppShellScaffold`, with all three criteria documented in §Reconciler Triggers.
- `ADR-ARCH-007` (async-db-init-before-runapp) — extended in spirit by ADR-PLATFORM-007.
- `ADR-AUDIO-009` (conditional iOS audio session) — notification banners do not touch `playAndRecord`; session gating covers the audio-capture interaction.
- `ADR-PLATFORM-006` (controller-owned FG service lifecycle) — unaffected. Workmanager periodic task and FG service are disjoint mechanisms coexisting in `core/background/`.
- `ADR-OBS-001` (dev-flavor telemetry singleton) — extended: telemetry is wired into the bg isolate's `coreBoot` on dev flavor via `const String.fromEnvironment('FLAVOR')`.
- `ADR-DATA-008` (wrapper-type-for-collection-with-metadata) — `CoreBootBundle` follows this shape (typed bundle of related items).
- `ADR-DATA-002` (sync-queue-delete-on-sent) — spiritually analogous: ADR-NOTIF-001's "sole writer to OS queue" mirrors "sole authority over sync_queue state machine."

---

## Open Questions

- **Exact iOS BGTask identifier string for workmanager 0.5.x.** Best guess: `be.tramckrijte.workmanager.iOSBackgroundAppRefresh`. To be verified against plugin source before T2 plist edit lands. Scoped to T2.
- **Status mapping confirmation.** V1 maps `done = done ∪ promoted` and `dismissed = superseded`. Confirm with personal-agent owner that "promoted" reads as a positive resolution in the user's mental model. If not, drop the promoted-into-done collapse and surface promoted as its own count.
- **What happens to summaries between 19:00 and 09:00 next day?** Decision: at 19:00, the reconciler schedules tomorrow's 09:00 summary using tomorrow's date. The reconciler runs again whenever the user opens the app the next day. If the user never opens, the 09:00 summary still fires (OS owns the schedule); its content is yesterday's snapshot (stale by one day). Acceptable for V1; documented.
