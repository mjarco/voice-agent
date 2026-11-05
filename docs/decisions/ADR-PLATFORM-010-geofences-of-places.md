# ADR-PLATFORM-010: Geofences of places run natively beside the location log

Status: Accepted

## Context

The arrival list (workspace epic `2026-11-places/01-arrival-list`, task 3, PR #395) will show
what to buy when you walk into a store. This task shows nothing yet: the phone watches every place
and logs enter, dwell and exit, so that real arrivals show Android's geofence delay. The owner
runs the device tests once, at the epic's end (decision of 2026-11-05). Geofences must survive what the location log's
subscription survives: the app closed, a reboot, an update, a force stop and location turned off.

The reports follow the trigger contract, `docs/compilations/notification-triggers/reviewed/04-trigger-contract.md`
in the workspace docs repo, section 7: a report is a status row of the location log, its status
an event type of `03-event-format.md` (at most 64 characters), its row id a UUIDv7, its detail JSON
under 500 characters. The owner settled the plan's open points on 2026-11-05
(`compilations/notification-triggers/source/2026-11-05-owner-decision-plan-points.md`).

## Decision

1. **Kotlin owns registration and the receiver**, in `location/` beside the pipeline of
   ADR-PLATFORM-009: `GeofenceRegistry`, `GeofenceReceiver`, `GeofenceRegisterWorker`, and
   `GeofenceConfig` in its own prefs file, `geofences.xml`, off the phone's backup. Dart only
   hands over the places (`com.voiceagent/place_geofences`, from `features/places/`) and the
   switch (`com.voiceagent/location_log`, from `features/location_log/`). Kotlin keeps the
   places it was given, so boot needs no Flutter. This is the path to places that ADR-NET-006
   left open.
2. **One geofence per place**: request id = place id; enter, dwell and exit; loitering delay
   60 s, the same value as `dwell_s` in the triggers; radius `max(radius_m, 150)`; no expiry;
   at most 100, the first 100 in Dart's order, with a `geofences_capped` row past that.
3. **Initial trigger 0.** Registration is repeated at every app start; with an initial enter,
   each start while standing at home would log a false `place.entered` and spoil the delay
   reading. The cost: a reboot inside a place logs no enter there; the exit still comes.
4. **Registration is repeatable**, as the pipeline's subscription is: at boot and at the
   BOOT_COMPLETED after a force stop (the same `LocationBootReceiver`, so a boot is counted
   once), at `MY_PACKAGE_REPLACED`, at app start, when the set of places changes (by hash),
   when the switch changes, and on a return to the app when the location permission changed
   (as when "always" is granted on the settings page). A failure other than a missing
   permission, and the `GEOFENCE_NOT_AVAILABLE` event that comes when location goes off,
   schedule a unique `androidx.work` job, `geofence-register`, with exponential backoff and no
   network constraint. A missing permission is not retried: the return to the app with the
   permission granted registers. After a failure the ids that may still be held are kept, and
   the next registration first removes every geofence of the app, so none is left stale.
   Registration waits for Play services on its own thread, one at a time; the pipeline's
   thread only writes rows, so no reading or broadcast waits behind Play services.
5. **The switch is the consent.** "Alerty w sklepach" is off by default and apart from the log's
   switch. Turning it on runs the log's permission flow: while-in-use, notifications (for the
   notification of task 5), then "all the time". Geofence rows follow this switch alone, not the
   log's: with it off nothing is written, and with it on rows are written even while the log is
   paused.
6. **Rows are 03's event types, in the log's queue.** `place.entered` for enter and dwell (the
   transition is in `detail`), `place.left` for exit, with the place, its name, the transition,
   the triggering fix's time and accuracy, and the radius. `recorded_at` is the phone's clock
   when the broadcast arrives. Location off writes `app.location_degraded` and the first
   registration after it `app.location_restored` (03, S5). Every new row of the log now gets a
   UUIDv7 id. JSON details are kept whole under 500 characters, never cut.
7. **Diagnostic statuses are not trigger events.** `geofences_registered`, `geofences_failed`,
   `geofences_removed` and `geofences_capped` are allowed to explain gaps, as the
   log's own statuses do; they are not event types of 03 and nothing reads them as such.
8. **No new network path.** Rows go through the log's queue and upload (ADR-NET-005); the retry
   job posts nothing. ADR-NET-002 is unchanged.

## Consequences

- Until task 4 the phone watches every place, by the epic's decision; from task 4 the set comes from the
  triggers (`GET /triggers`), and the hand-over from Dart goes.
- Standing inside a place when its geofence is registered (switching on, a reboot) gives no
  enter there, by design (item 3); the exit still comes.
- The native code has no automated tests, as ADR-PLATFORM-009 expects; it is verified by
  `docs/manual-tests/arrival-list.md`. Dart is tested over mocked channels.
- With the switch on and no "always" permission, each attempt (app start, boot, a change of
  places) writes one `geofences_failed` with code 1004, and nothing retries in between.
- Android only; iOS would need its own region monitoring.
