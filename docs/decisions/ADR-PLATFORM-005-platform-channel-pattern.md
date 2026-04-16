# ADR-PLATFORM-005: Platform channel pattern for native bridge communication

Status: Proposed
Proposed in: P019

## Context

P019 introduces the project's first platform channels: `MethodChannel('com.voiceagent/audio_session')` for iOS AVAudioSession management and `MethodChannel('com.voiceagent/activation')` for Quick Settings tile and Control Center control communication. Additionally, SharedPreferences is used as a cross-process IPC mechanism between the Android TileService/notification actions and the Flutter Dart isolate. A consistent pattern is needed before more platform channels are added.

## Decision

### MethodChannel naming and placement

- **Channel naming:** `com.voiceagent/{feature}` (e.g., `com.voiceagent/audio_session`, `com.voiceagent/activation`).
- **Dart bridge location:** If the channel serves a single feature, the bridge class lives in `features/{feature}/data/`. If shared across features or used by core infrastructure, it lives in `core/{concern}/`.
- **Native code location:** Android Kotlin in `android/app/src/main/kotlin/.../`. iOS Swift in `ios/Runner/`.
- **Testing:** Flutter side tested via mocked `MethodChannel` handler (`TestDefaultBinaryMessengerBinding`). Native side verified manually on device.

### SharedPreferences as cross-process IPC (Android)

When native Android components (TileService, notification PendingIntent) need to communicate with the Flutter Dart isolate without a live MethodChannel:

- **Native side:** Write to `context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)` with keys prefixed `flutter.` (matching the `shared_preferences` package convention).
- **Flutter side:** Read via `SharedPreferencesAsync` (not the legacy cached API) to ensure native-written values are observed.
- **Polling interval:** 10 seconds for non-urgent flags. Additionally poll on `AppLifecycleState.resumed`.
- **Flag lifecycle:** After reading a `true` flag, immediately write it back to `false` to prevent re-processing on next poll cycle.
- **Crash safety:** Flags are boolean with `false` as default. A stale `true` flag after a crash triggers a single extra toggle on next launch — acceptable for activation toggle but would be problematic for destructive actions.

### App Group UserDefaults as cross-process IPC (iOS)

When iOS Widget Extensions need to communicate with the main app:

- **Shared container:** App Group `group.com.voiceagent.shared`.
- **Both sides:** Read/write via `UserDefaults(suiteName: "group.com.voiceagent.shared")`.
- **App launch:** Widget Extension sets `openAppWhenRun = true` to launch the app. `AppDelegate.applicationDidBecomeActive` reads pending flags and forwards to Flutter via MethodChannel.

## Rationale

The TileService and Widget Extension run in contexts where the Flutter engine's MethodChannel is not directly accessible. SharedPreferences/UserDefaults are the simplest cross-process communication mechanism on each platform — no additional dependencies, no ContentProvider setup, no XPC.

The 10-second polling interval is acceptable for toggle actions (user taps tile, waits up to 10s for response). Real-time communication is not needed for these use cases.

## Consequences

- Platform channel names form a namespace — collisions must be avoided when adding new channels.
- SharedPreferences polling introduces up to 10s latency for native-to-Flutter communication. For real-time communication, a dedicated service with send-port or MethodChannel (when the engine is alive) should be used instead.
- If a third platform channel is added, consider extracting a `PlatformChannelRegistry` in `core/platform/` for centralized channel management.
- Flag-based IPC is limited to simple boolean/string signals. Complex data exchange should use MethodChannel when the Flutter engine is alive.
