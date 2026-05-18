# ADR-PLATFORM-005: Platform channel pattern for native bridge communication

Status: Accepted
Proposed in: P019
Amended in: P026 (activation IPC removed), P039 (EventChannel sibling + telemetry channel registry + registry-extraction deferred), P039 T5a (channel registered on iOS via `TelemetryEventEmitter.swift`; Dart consumer in `lib/core/observability/telemetry_native_bridge.dart`)

## Context

P019 introduced two platform channels: `MethodChannel('com.voiceagent/audio_session')` for iOS AVAudioSession management and `MethodChannel('com.voiceagent/activation')` for Quick Settings tile and Control Center control communication, plus SharedPreferences/App Group UserDefaults as cross-process IPC for tile/widget→app signaling. P026 removes the wake word feature along with the tile, widget extension, and all activation IPC. The audio session bridge remains.

## Decision

### Platform channel naming and placement (MethodChannel and EventChannel)

- **Channel naming:** `com.voiceagent/{concern}` (e.g.,
  `com.voiceagent/audio_session`, `com.voiceagent/telemetry_native_events`).
- **MethodChannel vs EventChannel:**
  - **`MethodChannel`** — request/response or Dart → native invocations
    (audio session control, media-button method calls).
  - **`EventChannel`** — native → Dart streams where the payload is a
    sequence of notifications and Dart subscribes once (telemetry
    audio-session events). Added as a sibling pattern in P039.
- **Dart bridge location:** If the channel serves a single feature, the bridge class lives in `features/{feature}/data/`. If shared across features or used by core infrastructure, it lives in `core/{concern}/`.
- **Native code location:** Android Kotlin in `android/app/src/main/kotlin/.../`. iOS Swift in `ios/Runner/`.
- **Testing:** Flutter side tested via mocked `MethodChannel` / `EventChannel` handler (`TestDefaultBinaryMessengerBinding`). Native side verified manually on device (or Simulator for iOS where no paid Apple Developer account is available).

### Channel-name registry (current)

| Channel | Type | Owner proposal | Direction |
|---|---|---|---|
| `com.voiceagent/audio_session` | MethodChannel | P019 (audio_session.dart) | Dart ⇄ native |
| `com.voiceagent/media_button` | MethodChannel + EventChannel | P037/P038 (`MediaButtonBridge`) | bidirectional |
| `com.voiceagent/telemetry_native_events` | EventChannel | P039 (`TelemetryEventEmitter`) | native → Dart |

## Rationale

Platform channel naming and placement conventions keep the native-Dart boundary consistent as new platform integrations are added. The `com.voiceagent/{feature}` namespace avoids collisions and makes ownership clear.

## Consequences

- Platform channel names form a namespace — collisions must be avoided when adding new channels.
- **`PlatformChannelRegistry` extraction is deferred (P039).** With three
  independent channels now in the codebase, the original trigger of
  "third channel → consider extracting a registry" has fired and been
  evaluated. The three channels have independent lifetimes, distinct
  owners, and zero shared state, so extracting a registry would invent
  abstraction over coincidence. Revisit triggers: (a) a fourth channel
  with overlapping concerns, or (b) the first cross-channel shared
  state (e.g. unified error reporting, shared lifecycle).
- Complex cross-process IPC patterns (SharedPreferences polling on Android, App Group UserDefaults on iOS) are no longer in use and no longer documented here. If re-introduced in a future proposal, they should be re-evaluated against lower-latency alternatives.
