# ADR-PLATFORM-011: A registration keeps visits, survives a process kill, and needs "all the time"

Status: Accepted.
Decided in: workspace off-roadmap task `2026-11-06-arrival-defects` (defects D1–D3 of the arrival-list device run)
Supersedes: in [ADR-NOTIF-003](./ADR-NOTIF-003-arrival-alerts-posted-natively.md) item 4, the sentence on forgetting the visit of a geofence added afresh; in [ADR-PLATFORM-010](./ADR-PLATFORM-010-geofences-of-places.md) items 3 and 4, which reasons add only what changed

## Context

The device run of the arrival list (Pixel 11 Pro, Android 17, 1.19.0+34; workspace docs
`requirements/roadmaps/2026-11-places/epics/01-arrival-list/drafts/06-device-run-report.md`,
section 2) found three defects in one function, `GeofenceRegistry.reconcile`:

- **D1.** After a force stop mid-visit, every geofence is added again and its visit forgotten,
  because ADR-NOTIF-003 item 4 assumed that a geofence added with initial trigger 0 while you stand
  inside reports nothing. On this phone it reports no enter but does report the dwell, about 65 s
  later, so a second alert came in one visit (T17), twice.
- **D2.** On Android 17 the next start after a plain process kill (`am kill`, a permission revoke,
  a cold tap) also brings `BOOT_COMPLETED`. With no reboot `LocationBootReceiver` calls it
  `restart_after_stop`, which re-added everything, and with D1 forgot every visit, though the
  geofence intent was still alive (T6 step 4, seen five times).
- **D3.** With "all the time" revoked, the app start found the registration standing and returned
  before asking Play services, so no `geofences_failed` 1004 came and the screen kept the old count;
  alerts silently stopped (T4).

## Decision

1. **A geofence added again keeps its trigger's visit.** Only the visit of a trigger withdrawn from
   the set is forgotten (with its geofence). A dwell reported after a re-registration then meets the
   visit's once and fires nothing. If the exit was missed while the geofence was gone (a force stop,
   a reboot, location off), the visit ends at that trigger's next transition after `max_visit_s`
   (6 h from personal-agent), as any missed exit does; until then a return to that store does not
   alert. A changed geofence (a moved place, a new radius) also keeps its visit.
2. **`restart_after_stop` keeps the registration** like the app start and a new trigger set, while
   it stands. A force stop cancels the intent, so after a real one everything is still added again;
   a reboot (`reboot`) and an update still add everything.
3. **A registration stands only with fine location all the time, unchanged since it was made.**
   Without "all the time", or with precise location turned off, Play services stops reporting, so
   the app start does not return unchanged. Any change of the permission since the last
   registration also makes the next one try in full. An add without the permission first removes
   every geofence of the app (by its intent; a failure is left to the next registration), then fails
   before Play services with code 1004: `geofences_failed`, the held ids kept as uncertain (so the
   screen shows "obszary: 0"), no retry job, and a return to the app with the permission changed
   registers (ADR-PLATFORM-010 item 4 stands). Before Android 10 the fine permission includes
   "all the time".
4. The decision is computed by `RegistrationPlan` (`standing` and `of`), pure Kotlin with JVM
   tests; the registry reads the permissions and the intent and calls Play services.

## Consequences

- A visit can outlive a missed exit by up to `max_visit_s`. That is one alert held back on a
  return within 6 h, against a second alert in the same visit on any force stop or kill.
- Android 17's boot broadcast after a kill no longer costs a re-registration or a row.
- A trigger withdrawn and armed again while you stand inside (the last item ticked off, a new one
  added; or a trigger pushed out of the first 100 and back) has lost its visit, so its dwell may
  fire a second alert. Accepted: both are rare, and the visit of a withdrawn trigger has nothing
  left to hold back.
- The manual plan `docs/manual-tests/arrival-list.md` T4, T6 and T17 change their expected results.
