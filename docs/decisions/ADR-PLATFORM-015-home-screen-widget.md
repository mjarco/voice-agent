# ADR-PLATFORM-015: A home-screen widget with the day's three numbers, read in the background

Status: Accepted

Amends: ADR-NET-002 (a fourth background exception, next to P040's agenda
reconciliation).

## Context

The owner wants a home-screen widget with what matters most: calories left,
with the warning under the reserve, unfinished and overdue tasks, and matters
with activity in the last 7 days (workspace
`docs/discussions/2026-11-va-meals-dashboard/`, source M2 and M3; the widget
in its draft 06 §4). V2 of the redesign builds it
(`docs/requirements/off-roadmap/2026-11-15-va-widget/`). The numbers are in
the today view personal-agent composes (`GET /api/v1/today?v=1`, ADR-API-124
of personal-agent), which Dziś already reads (ADR-ARCH-013).

A widget is drawn by the launcher, not by the app: Android shows what the
app last handed it. What the owner does in the app reaches the widget only
if the app hands it over; what is done elsewhere (the web UI, the glasses)
only if something reads the day while the app is closed. That is background
execution, which ADR-NET-002 allows only for named exceptions.

## Decision

1. **The widget is native Android**, a `RemoteViews` layout drawn by
   `TodayWidgetProvider` (4 × 2 cells), from strings Dart composes
   (`HomeWidgetNumbers`) and saves through the `home_widget` plugin. The
   plugin is used because it registers in every Flutter engine, the
   WorkManager isolate's included, where the app's own channels in
   `MainActivity` do not exist.
2. **Kotlin decides one thing:** numbers of another day than today are not
   drawn (dashes instead). An app left overnight would otherwise show
   yesterday's calories until the next read.
3. **Every read of the day redraws it** (`TodayNotifier.refresh`): at start,
   on resume, after a swipe on Dziś, after every agent reply (a meal logged or
   a task ticked by voice, also during a hands-free session), and on return
   from the diet's screens.
4. **Leaving the app reads the day once more** (`AppLifecycleState.paused`),
   so what was done in the app is on the widget when the home screen shows.
5. **A WorkManager task reads the day every 15 minutes** (Android's shortest
   period), `widgetRefresh`, on the dispatcher of P040's task, with a network
   constraint. It is one read-only call, `GET /api/v1/today?v=1`, and it reads
   nothing when no widget is placed. A failed read is retried by WorkManager's
   backoff. Android's own `updatePeriodMillis` (30 minutes) only redraws
   what is saved.
6. **Taps open the app** (`WidgetTapBridge`, in ArrivalTapBridge's pattern of
   ADR-PLATFORM-008, one tap to one channel, nothing from recents): the
   calories the diet's day over Dziś, the tasks Dziś, the matters Sprawy.
   **The mic opens Dziś and starts listening** once the activity is in front
   (`HandsFreeController.listen`, the same as the glasses' Rozmowa,
   ADR-AUDIO-016). It does not listen with the app closed: Android allows a
   microphone service started from a widget tap, but the session lives in the
   activity's engine (decision D1 of the task).

## Consequences

- `home_widget` enters the dependency tree, with its Glance dependency.
- The widget lags work done outside the app by up to 15 minutes, and longer
  when Android defers periodic work (Doze, battery saver). The owner's case
  of 06 §4 ("a task ticked in the web UI shows within 15 minutes") is the
  measure.
- This is ADR-NET-002's fourth exception. Its P040 amendment asks that a
  fourth be the moment to restructure ADR-NET-002 into a policy and a list
  of exceptions; that is left for the redesign's review before the merge.
- No transcript, sync queue or write goes through the background task.
