# ADR-PLATFORM-013: The location log subscribes again a minute after an update

Status: Accepted.
Decided in: workspace off-roadmap task `2026-11-11-location-resubscribe` (D3)
Extends: [ADR-PLATFORM-012](./ADR-PLATFORM-012-watch-the-subscription-by-its-readings.md) (the watch)

## Context

ADR-PLATFORM-012 left the cause of the lost request open. The install of 1.29.1+48 on the Pixel
(2026-11-11 12:30) showed it: the app, started by `MY_PACKAGE_REPLACED`, subscribed at 12:30:06.657,
and Play services removed the request at 06.774 (`-client` in `dumpsys` of its location service) with
no call from the app. Play services clears an updated package's requests, and here it did so after
the app had already subscribed again. The watch brought the request back at its first run, 63
minutes later (the job waited for Doze).

So each install costs about an hour of readings, though two earlier updates (2026-11-08, 2026-11-09)
kept their request.

## Decision

1. **`MY_PACKAGE_REPLACED` also enqueues a one-time job, 60 seconds later**
   (`LocationAfterUpdateWorker`, unique work `location-log-after-update`, `REPLACE`, no constraint).
   It runs `LocationWatch.afterUpdate` on the pipeline's thread, which runs `reconcile` with the
   reason `after_update`. That writes a `subscribed` row.
2. **Background mode only**, for the reason of ADR-PLATFORM-012 item 1: a start of the foreground
   service from a worker can be refused or stop the running service.
3. **Once, unconditionally.** It does not check whether the request is still there: the app cannot
   read Play services' list, and one more subscription costs one fix.
4. **The watch stays.** A request cleared later than the minute, or lost for any other reason, is
   still answered within about an hour.

## Consequences

- After an install the log should lose a minute or two of readings, not about an hour. The minute
  is a margin chosen against one observed clearing (117 ms); a slower clearing falls to the watch.
- Every update writes one more `subscribed` row (`background, after_update`).
- The job may be deferred like any job; after an install the phone is usually awake.
- Foreground mode still waits for the next process start.
