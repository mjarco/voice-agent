# ADR-PLATFORM-012: The location log watches its subscription by its readings

Status: Accepted.
Decided in: workspace off-roadmap task `2026-11-11-location-resubscribe`
Extends: [ADR-PLATFORM-009](./ADR-PLATFORM-009-native-location-pipeline.md) item 4 (subscribing is repeatable)

## Context

ADR-PLATFORM-009 item 4 assumes `FusedLocationProviderClient` can lose a registration and runs
`reconcile` at each app start, on `BOOT_COMPLETED` and on `MY_PACKAGE_REPLACED`. It does not cover a
loss while the process lives.

After stable 1.29.0+47 was installed on the Pixel (2026-11-10 09:04 CET), the log got no reading for
more than 25 hours. On 2026-11-11 Play services (`dumpsys` of its location service) held the app's
geofences but no location-update request. The app had written `subscribed` twice at the update
(`app_updated` and `app_start`, within 300 ms of the install) and no `subscribe_failed`, and its
process lived on from the install, so nothing subscribed again. The system's location history shows
one GPS fix asked for by the app 19 s after the install, ended 2 s later, and no reading from it in the log.
Why the request went is not known: a race with Play services clearing the updated package's
requests is the likeliest reading, but two earlier updates (2026-11-08, 2026-11-09) kept theirs.

## Decision

1. **A periodic job watches the readings, in background mode.** `LocationWatchWorker` runs every 30
   minutes, with no constraint, while the log is on (scheduled by `reconcile` with the policy
   `UPDATE`, so a changed period reaches phones that have the job; cancelled when the log is off). It
   runs `LocationWatch.check` on the pipeline's thread, which does nothing in foreground mode: there a
   start of the foreground service from a worker can be refused or can make the running service stop
   itself, leaving the log worse off.
2. **Stale means 30 minutes without a reading**, counted from the later of the last reading and the
   last subscription, so a fresh subscription gets its own half hour. In 8.4 days of the log
   (2026-11-01 to 2026-11-10) only 6 gaps were longer.
3. **A stale stretch re-subscribes once per two hours.** The watch writes a status `readings_stale`
   (detail: `last_reading_at`, `last_subscribed_at`) and runs `reconcile` with the reason
   `stale_readings`, which writes `subscribed`. If no reading follows, the next try waits two hours,
   so a phone with location off writes a few rows a day, not two an hour.
4. **The cause is not guessed at.** The watch answers any silent loss (an update race, a Play services
   restart, anything else), and the `readings_stale` rows count how often it happens.

## Consequences

- A lost subscription usually costs about an hour of readings (30 minutes stale plus up to a period)
  instead of lasting until the next process start; Doze and app standby can defer the job longer.
- A real long gap (the phone off, location off, a still phone where Play services gives nothing)
  writes a `readings_stale` and a `subscribed` row every two hours; personal-agent stores status values
  as text with no list, so no contract changes.
- A re-subscription asks for a fix (seen as a short GPS request), a small cost during stale stretches only.
- Foreground mode is not watched: a silent loss there still lasts until the next process start.
- The rule mixes clocks: the last reading is the fix's time, the rest the phone's clock. A clock moved
  by hand can delay the watch or bring one false stale row; both pass on their own.
- `lastSubscribedAtMs` is written when the request is sent, before Play services answers; a failed
  request is still written as `subscribe_failed` (ADR-PLATFORM-009) and the next try waits its turn.
