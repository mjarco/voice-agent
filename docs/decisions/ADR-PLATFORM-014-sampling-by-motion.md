# ADR-PLATFORM-014: The location log samples by motion

Status: Accepted.
Decided in: workspace off-roadmap task `2026-11-11-motion-sampling`
Extends: [ADR-PLATFORM-009](./ADR-PLATFORM-009-native-location-pipeline.md) (the modes of the log)

## Context

The location log has two modes (ADR-PLATFORM-009): background, a reading every 300 s at most every
60 s, and foreground, a service with a permanent notification and an interval the owner picks
(default 30 s). In background mode a drive of 10 minutes leaves two or three points; foreground mode
keeps the notification and the GPS on also while the phone lies on a desk. The owner asked for
frequent readings while moving and chose the Activity Recognition Transition API of Play services,
which reports when the phone starts walking, running, cycling, riding a vehicle or stands still.

Two facts shape the design:

- An activity recognition event is one of the exemptions that let an app start a foreground service
  from the background on Android 12+; a `location` service of an app holding
  `ACCESS_BACKGROUND_LOCATION` may then read location all the time (Android 14+).
- Personal-agent takes only `background` and `foreground` as a reading's `requested_mode` and refuses
  the row otherwise; a refused row is gone. Status values are free text.

## Decision

1. **A third mode, `motion` ("Według ruchu").** Background readings while the phone stands; the
   foreground service while it moves. The two old modes do not change. Choosing the mode in Settings
   asks for "Physical activity" (`ACTIVITY_RECOGNITION`, runtime on Android 10+; below it the Play
   services permission in the manifest is enough). Without it the mode keeps background readings and
   the screen offers "Nadaj".
2. **ENTER transitions only**, for `still`, `walking`, `running`, `on_bicycle` and `in_vehicle`:
   entering one is leaving the previous. `MotionTransitions` registers them on each `reconcile` in
   motion mode (assumed lost after a reboot or an update, like the location request) and removes them
   in every other mode and when the log is off. The watch renews it on each run in motion mode, since
   Play services can drop a registration silently (ADR-PLATFORM-012); a return to the app renews it when
   the permission changed on the settings page. `MotionReceiver` gets them.
3. **A start of motion switches at once.** The interval by activity: a vehicle 10 s, a bicycle 15 s,
   walking or running 30 s. Another motion with another interval restarts the service with it. The
   service is started from the transition's broadcast, inside the exemption. If the start is refused,
   or the service cannot hold itself in the foreground, the log writes `subscribe_failed`, ends the
   frequent state and subscribes in the background, so it keeps some readings and the next start of
   motion tries again.
4. **`still` switches back after 3 minutes** without a new motion (`Motion.SETTLE_MS`), because traffic
   lights and jams report `still` and then a vehicle again. **A stop the API missed switches back
   too:** frequent readings end when the phone has not moved 100 m for 10 minutes, or no reading came
   for 10 minutes since they started (`Motion.STATIONARY_MS`, an anchor moved by each reading further
   than 100 m). No timer: the checks run on each frequent reading and in the 30-minute watch of
   ADR-PLATFORM-012, which writes `motion_settled` (detail `still since …` or `stationary since …`).
5. **The motion state starts empty** after a reboot, an update, a restart after a stop, a change
   of mode and the log's switch: a motion from before says nothing of now. Motion mode starts in the background and waits
   for a transition; the API promises no event for the current activity.
6. **Readings keep the contract.** A reading's `requested_mode` is the mode in effect (`foreground`
   while moving, `background` otherwise) and `requested_interval_s` the interval in effect. Each
   transition is a status row `activity` (detail `{"activity", "at"}`); new status values are
   `motion_settled`, `motion_permission` (`granted`/`denied`, on a change) and
   `motion_subscribe_failed`. `subscribed` rows of motion mode start with `motion, `.

## Consequences

- No change to personal-agent: the readings carry the two known modes, the statuses are text.
- While moving the permanent notification shows "W ruchu: odczyt co N s"; while standing there is
  none.
- The start of each motion loses what the API's delay costs (documented only as "may vary by
  device"): typically a minute or two of a drive in background readings. A stop costs three minutes of
  frequent readings, more when no reading comes (then up to the watch's next run, 30 minutes or
  longer under Doze).
- A long jam (no 100 m in 10 minutes) ends the frequent readings until the next transition: a car
  still in a jam sends none, so the rest of that drive is read in the background.
- An older build installed over this one would read the stored mode `motion` and send it as
  `requested_mode`, which personal-agent refuses; switch to another mode before a downgrade.
- A wrong kind of motion (a tram as `still`, slow cycling as walking) changes only the interval or
  delays the switch; it does not lose the background readings.
- The 30-minute stale watch of ADR-PLATFORM-012 covers motion mode while its readings are in the
  background, and not while the service runs, as in foreground mode.
- Not verified on a device when decided: the exemption's start of the service, the API's delays and
  mistakes on the Pixel, the registration's fate after a reboot. The manual plan
  `docs/manual-tests/motion-sampling.md` covers them.
