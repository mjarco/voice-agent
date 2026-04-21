# ADR-PLATFORM-005: Platform channel pattern for native bridge communication

Status: Accepted
Proposed in: P019
Amended in: P026 (activation IPC removed)

## Context

P019 introduced two platform channels: `MethodChannel('com.voiceagent/audio_session')` for iOS AVAudioSession management and `MethodChannel('com.voiceagent/activation')` for Quick Settings tile and Control Center control communication, plus SharedPreferences/App Group UserDefaults as cross-process IPC for tile/widget→app signaling. P026 removes the wake word feature along with the tile, widget extension, and all activation IPC. The audio session bridge remains.

## Decision

### MethodChannel naming and placement

- **Channel naming:** `com.voiceagent/{feature}` (e.g., `com.voiceagent/audio_session`).
- **Dart bridge location:** If the channel serves a single feature, the bridge class lives in `features/{feature}/data/`. If shared across features or used by core infrastructure, it lives in `core/{concern}/`.
- **Native code location:** Android Kotlin in `android/app/src/main/kotlin/.../`. iOS Swift in `ios/Runner/`.
- **Testing:** Flutter side tested via mocked `MethodChannel` handler (`TestDefaultBinaryMessengerBinding`). Native side verified manually on device.

## Rationale

Platform channel naming and placement conventions keep the native-Dart boundary consistent as new platform integrations are added. The `com.voiceagent/{feature}` namespace avoids collisions and makes ownership clear.

## Consequences

- Platform channel names form a namespace — collisions must be avoided when adding new channels.
- If a third platform channel is added, consider extracting a `PlatformChannelRegistry` in `core/platform/` for centralized channel management.
- Complex cross-process IPC patterns (SharedPreferences polling on Android, App Group UserDefaults on iOS) are no longer in use and no longer documented here. If re-introduced in a future proposal, they should be re-evaluated against lower-latency alternatives.
