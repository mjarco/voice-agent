# ADR-NET-007: Armed triggers are pulled in the background, and geofences come from them

Status: Accepted. Item 6 (`would_fire`) superseded by [ADR-NOTIF-003](./ADR-NOTIF-003-arrival-alerts-posted-natively.md).

## Context

The arrival list (workspace epic `2026-11-places/01-arrival-list`, task 4, PR #396) fires on
the phone, offline too, from triggers personal-agent arms ahead of time. personal-agent serves
them at `GET /api/v1/triggers`, compiled on read (its ADR-API-114, thought-agent#637, deployed
2026-11-05). The contract is `docs/compilations/notification-triggers/reviewed/04-trigger-contract.md`
in the workspace docs repo. A change in places or the list should reach the phone within about an
hour (the epic's criterion 1), with the app closed, so the set cannot be fetched only in the
foreground.

ADR-NET-002 keeps sync to the foreground, and ADR-NET-005 made the location log's upload its
background exception. Until this task the geofences of ADR-PLATFORM-010 came from every place
Dart handed over.

## Decision

1. **A third background path, for one route.** Kotlin pulls `GET <base>/triggers` with the base
   URL and token the location log already holds:
   - every hour from a unique periodic `androidx.work` job, `triggers-pull`, with a network
     constraint;
   - at app start and when "Alerty w sklepach" goes on;
   - on a return to the app, at most once per 5 minutes.

   Only while the switch is on. It shares no code with the transcript sync and posts nothing.
2. **The set's version is its `ETag`.** The phone sends it back as received in `If-None-Match`
   (weak behind Cloudflare). A `304` keeps the set. Only a `200` with `{"data": <set>}` and
   `contract: 1` replaces it, as a whole. Anything else counts as a failure and the old set
   stays. Redirects are not followed. The request runs on its own thread; what it brought is
   settled on the registry's thread, so the switch going off meanwhile wins and nothing is
   written with it off. A failure writes one `triggers_failed` row until a pull
   works again, so a phone offline for a day writes one, not 24.
3. **Kotlin alone holds the set**, in `geofences.xml`, off backup. Dart reads only a count and
   when personal-agent last answered. Turning the switch off clears the set and cancels the job.
4. **What goal 2 does not build is rejected, not guessed.** A trigger with another condition, a
   guard, another `once`, no `phone` surface, a missing field, an id over 100 characters or a
   `dwell_s` over a day is skipped, so one trigger Play services would refuse never blocks the rest. It gets one
   `trigger.rejected` row per id and version (04, section 4). Unknown fields are ignored.
5. **Geofences come from the triggers**, one per trigger: request id = trigger id, radius
   `max(radius_m, 150)`, loitering delay = `dwell_s`. A geofence's key leaves out the version and
   the text, so a new list at the same store does not add it again; a new set is a reason that
   keeps intact geofences (ADR-PLATFORM-010, item 3). This supersedes items 1 and 2 of
   ADR-PLATFORM-010: Dart no longer hands over places, and `com.voiceagent/place_geofences` is
   gone.
6. **Rows say what would fire.** A `place.entered` row carries `trigger`, `v`, and `would_fire`:
   the transition `dwell_s` asks for (dwell when > 0, enter when 0) on a trigger not yet expired
   by the phone's clock. `name` is the trigger's title, cut to 60 characters. Once per visit and
   the notification are task 5.

## Consequences

- The set last pulled is what fires offline; the triggers' expiry (three days, ADR-API-114)
  bounds how stale it gets.
- Between an update from task 3 and the first pull the phone watches nothing; the app start
  right after pulls.
- A store with nothing to buy has no trigger, so no geofence and no `place.entered` rows; the
  log no longer records arrivals at every place.
- The trigger parser has JVM unit tests (`android/app/src/test/`); the rest of the native code
  is verified by `docs/manual-tests/arrival-list.md`, as ADR-PLATFORM-009 expects.
- This grants no other feature a background path.
