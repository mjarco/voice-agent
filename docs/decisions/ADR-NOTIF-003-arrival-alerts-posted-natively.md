# ADR-NOTIF-003: Arrival alerts are posted natively, a second writer of notifications

Status: Accepted. Item 6 fulfilled by task 6 (PR #399): the tap opens the trigger's route, of which only `/shopping` with `store=` type ids may be opened, through ADR-PLATFORM-008's two channels, and Kotlin writes `trigger.tapped` once, for the alert last shown. In item 4, forgetting the visit of a geofence added afresh is superseded by [ADR-PLATFORM-011](./ADR-PLATFORM-011-registration-keeps-visits.md): only a withdrawn trigger's visit is forgotten.
Decided in: workspace epic `2026-11-places/01-arrival-list`, task 5, PR #397
Amends: rules 2 and 5 of [ADR-NOTIF-001](./ADR-NOTIF-001-diff-based-reconciliation-with-id-partitioning.md)
Supersedes: item 6 of [ADR-NET-007](./ADR-NET-007-armed-triggers-pulled-in-background.md) (`would_fire` on `place.entered` rows)

## Context

The arrival list fires when you stay `dwell_s` at a store where something waits. The geofence's
broadcast wakes `GeofenceReceiver` in Kotlin, often with no Flutter engine and no time to start one
(ADR-PLATFORM-009). The notification must be posted from there, at most once per visit, and its
reports must come back as rows of the location log, named by the trigger contract
(workspace docs, `compilations/notification-triggers/reviewed/04-trigger-contract.md`, sections 5–7).

ADR-NOTIF-001 makes Dart's `LocalNotificationService` the single writer of notifications and gives
each kind its own id range. A native writer breaks rule 2 as written, so it needs this ADR
(the epic's construction 4).

## Decision

1. **A second writer, `ArrivalNotifier` (Kotlin).** It posts only arrival alerts, only in its own
   channel `arrival_alerts` ("Alerty w sklepach") and its own id range, and never cancels, reads or
   replaces anything of Flutter's. Dart's `LocalNotificationService` stays the only writer of
   everything else. This amends rule 2 of ADR-NOTIF-001.
2. **Its id range is `1_000_000–1_999_999`**: `1_000_000 + crc32(trigger id) % 1_000_000`, one id
   per trigger, so a second visit replaces the first if it is still on screen. The range lies
   between the daily summaries (`1000–1003`) and the reserved action-item range (`2_000_000+`), and
   clear of the services' ids (`1`, `4102`). This amends rule 5 of ADR-NOTIF-001. Two triggers may share
   an id (about n²/2 000 000 for n triggers); the later alert then replaces the earlier, whose swipe
   is lost. Accepted at up to 90 triggers.
3. **The channel is heads-up with sound** (`IMPORTANCE_HIGH`): you are walking in and glance once,
   and an alert is rare. Once the channel exists only you change it, in the system's settings.
4. **Once per visit is kept on disk** (`Visits`, in `geofences.xml`), keyed by the trigger's id,
   never by its version: a restart or a new list mid-visit does not fire again. The firing
   transition is the dwell when `dwell_s` > 0 and the enter when it is 0; an expired trigger never
   fires. A visit with no exit is ended lazily, at the next transition of that trigger after
   `max_visit_s`, with a `place.left` row of `"transition":"max_visit"` dated at the visit's end.
   A geofence removed (its trigger withdrawn) or added afresh (boot, update, retry, a changed key)
   will never report the exit of a visit in progress, so that visit is forgotten at once; added
   with initial trigger 0 while you stand inside, it reports no enter or dwell either, so this
   cannot fire twice (manual plan, T17). Visit state is read and written only on the location
   pipeline's thread, and saved with `commit` before the notification is posted.
5. **Reports are location-log rows** (04, section 7), each naming its cause by row id
   (`LocationStore.enqueue` returns the UUIDv7, now monotonic within the process, so a report
   made in the same millisecond as its cause sorts after it): `trigger.fired` (`caused_by` the `place.entered`
   row, with `"surface":"phone"` and `"shown"`), `trigger.shown` (`caused_by` the fired row), and
   `trigger.ignored` on a swipe (`caused_by` the shown row), written by `ArrivalDismissReceiver`
   (not exported) from the notification's delete intent. With notifications off (the permission,
   the app's notifications or the channel) the alert is not posted: `trigger.fired` carries
   `"shown":false` and a `why`, no `trigger.shown` follows, and the visit's once is spent.
6. **The tap opens the app as the launcher does.** `trigger.tapped` and the trigger's route are
   task 6 (ADR-PLATFORM-008's cold and warm paths).
7. **`would_fire` leaves `place.entered`** (ADR-NET-007, item 6): `trigger.fired` now says it.
   `expired: true` stays on an enter or dwell of an expired trigger.

## Consequences

- Review now flags a direct `FlutterLocalNotificationsPlugin` call outside `LocalNotificationService`
  and a notification posted from Kotlin outside `ArrivalNotifier`; the location foreground service's
  own notification is part of the service, as before.
- Dart's `cancelAll()` at a revoked permission (ADR-NOTIF-001, rule 6) also clears an arrival alert
  on screen. That is harmless: with the permission revoked no alert could show anyway.
- A swipe or a tap after "Alerty w sklepach" is turned off writes nothing; the switch off also clears
  the visits, so the next switch on starts with none. The switch on creates the channel, so it is
  in the system's settings before the first alert.
- A trigger whose `version` or `place` is over 100 characters is rejected, so a report's detail
  always has room for `caused_by` within the log's 500 characters.
- Visits and `Triggers` have JVM unit tests (`android/app/src/test/`); posting, the channel and the
  swipe are verified on the device by `docs/manual-tests/arrival-list.md`, T16–T21.
- This grants no other feature a native notification path.
