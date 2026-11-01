# ADR-PLATFORM-009: The location log runs natively, apart from Flutter

Status: Accepted

## Context

The location log (workspace off-roadmap task `2026-11-01-location-log`) collects
dated positions and sends them to personal-agent, to learn what a subscription
can collect. It has to work with the app closed, across reboots, and in two
modes the owner switches between in Settings: background only (a few readings an
hour, no notification) and a foreground service (as often as asked, with a
permanent notification).

The options were a Dart plugin with a background isolate, Kotlin capture with a
Dart upload through `workmanager`, or all of it in Kotlin. A background wake-up
may end before a Flutter engine could start, and Kotlin cannot start a
`workmanager` Dart task without reaching into the plugin.

## Decision

1. **Everything that runs unattended is Kotlin**, in
   `android/app/src/main/kotlin/.../location/`. Dart only controls and reads it
   over `com.voiceagent/location_log`, from `features/location_log/`.
2. **Its own store.** `location_log.db` is a separate file, so a location failure
   cannot touch transcripts or the sync queue. A row is written before any send
   and deleted once personal-agent has answered for it.
3. **Its own service.** `LocationForegroundService` has type `location`. The
   hands-free service is stopped by `HandsFreeController` when a session ends
   (ADR-PLATFORM-006), and a `microphone` service cannot start at boot.
4. **Subscribing is repeatable.** `FusedLocationProviderClient` is assumed to
   lose a registration, so `reconcile` runs at each app start, on
   `BOOT_COMPLETED` and on `MY_PACKAGE_REPLACED`.
5. **Status rows explain gaps.** Start, stop, reboot, update, subscribe failures,
   and changes of permission, battery saver and the location setting go into the
   same stream. The Stop button of the Task Manager has no callback, so it is
   read from `ApplicationExitInfo` on the next start.
6. **Permissions.** `ACCESS_FINE_LOCATION`, `ACCESS_BACKGROUND_LOCATION` and
   `FOREGROUND_SERVICE_LOCATION` are requested only when the owner turns the log
   on. The switch off is the pause.
7. **Credentials.** The pipeline cannot read `flutter_secure_storage`, so Dart
   hands it the URL and token at each start and change, and the token is stored
   under an Android Keystore key (ADR-DATA-004).
8. **No cleartext.** `HttpURLConnection` obeys Android's default refusal of
   cleartext, unlike Dart's stack, so the log needs an HTTPS server. It uses the
   URL from Settings, like transcripts. The device test against a dev personal-agent
   ran on a build with a test field and a cleartext rule for `laptop.lan`; both were
   removed before shipping, on the owner's decision. A new run needs them
   brought back on a local build, from the tag
   `off-roadmap/2026-11-01-location-log/D8`.

## Consequences

- Android only. `play-services-location` enters the dependency tree, and iOS would
  need its own pipeline.
- The native code has no automated tests, as ADR-PLATFORM-005 expects: it is
  verified by `docs/manual-tests/location-log.md`. Dart is tested over a mocked
  channel.
- The token exists in two places on the phone. Signing out needs both cleared;
  `setCredentials` does that at the next start.
- Queued rows survive a pause and are sent later. Delete-all in the web UI does
  not reach rows still queued on the phone.
