# Proposal 019 — Background Activation & Wake Word Detection

## Status: Implemented

## Prerequisites
- P012 (Hands-Free Local VAD) — `HandsFreeController`, `HandsFreeOrchestrator`, VAD pipeline must exist; merged
- P014 (Recording Mode Overhaul) — `suspendForManualRecording()` / `resumeAfterManualRecording()` must exist; merged
- P013 (VAD Advanced Settings) — `VadConfig` in `AppConfig` must exist; merged
- P006 (Settings Screen) — settings persistence infrastructure must exist; merged

## Scope
- Tasks: 9
- Layers: core/background (new), core/providers, core/config, features/activation (new), features/recording, features/settings, platform (Android native + iOS native)
- Risk: High — introduces background execution, native platform code, third-party SDK (Picovoice), and supersedes ADR-PLATFORM-002

---

## Problem Statement

The app can only be used while foregrounded with the screen unlocked. When the user locks the phone, switches to another app, or puts the phone in a pocket, all recording and listening stops immediately (ADR-PLATFORM-002). To use the voice agent the user must: unlock the phone, open the app, wait for the recording screen to load, and then speak.

This makes the agent impractical for its primary use case — capturing thoughts and notes throughout the day. The user wants to say a wake word (e.g. "Jarvis") while the phone is in a pocket or on a desk and have the agent start listening, without touching the screen. They also want quick activation from the lock screen via a system shortcut (Quick Settings tile on Android, Control Center on iOS) for situations where voice activation is not appropriate.

---

## Are We Solving the Right Problem?

**Root cause:** The app has no background execution capability and no activation mechanism other than opening the app manually. ADR-PLATFORM-002 explicitly cancels all audio activity on background, and ADR-NET-002 restricts all processing to foreground. There is no platform integration (shortcuts, tiles, intents) to launch the app quickly.

**Alternatives dismissed:**
- *Keep foreground-only, add home screen widget:* A widget can launch the app with one tap, but still requires unlocking the phone and looking at the screen. Does not solve the hands-free pocket scenario.
- *System voice assistant integration only (Siri/Google Assistant):* Would avoid custom wake word detection, but the user explicitly does not want Siri integration. Google Assistant on Android could work but ties activation to Google's ecosystem and requires internet.
- *VAD-as-wake-word (use existing Silero VAD + STT to detect a phrase):* VAD only distinguishes speech from non-speech — it cannot detect a specific phrase. Running STT on every detected speech segment would drain battery, require internet (Groq is cloud-based), and send all ambient speech to a third-party server.

**Smallest change?** No — this requires coordinated changes across multiple layers (background service infrastructure, wake word SDK, platform-specific native code, settings). However, each component is independently useful: background service enables future features, wake word is the primary activation method, and platform shortcuts provide fallback activation. The proposal is structured so each task is independently mergeable and valuable.

---

## Goals

- The app listens for a configurable wake word while backgrounded, using on-device processing (no network, no cloud)
- On wake word detection, the app automatically starts a hands-free VAD session
- The user can activate the agent from the Android lock screen via a Quick Settings tile
- The user can activate the agent from the iOS lock screen via a Control Center control
- A persistent notification (Android) shows activation status and provides start/stop controls
- All background activation features are opt-in via Settings toggles

## Non-goals

- Siri integration (explicitly excluded by user)
- Background sync — sync remains foreground-only per ADR-NET-002
- Custom wake word training UI in-app — users train wake words in Picovoice Console and import the `.ppn` file
- Lock screen widget (beta on Android 16, limited on iOS — deferred)
- Always-on wake word when app is force-killed (requires restart; foreground service keeps app alive but cannot survive force-kill)
- Google Assistant integration

---

## User-Visible Changes

**New in Settings:** "Background Activation" section with toggles for wake word detection and background listening, a Picovoice access key field, and a wake word sensitivity slider.

**Android:** A persistent notification appears when background listening is active, showing current state (listening for wake word / recording session active) with Start/Stop action buttons. A new Quick Settings tile ("Voice Agent") toggles background listening from anywhere, including the lock screen.

**iOS:** Background listening continues when the app is minimized. A Control Center control ("Voice Agent") toggles activation from the lock screen without unlocking. The Action Button can be configured by the user (in iOS Settings) to open the app, which auto-starts wake word listening.

**Wake word flow:** User says the configured wake word (default: "Jarvis", or a custom-trained phrase) while the phone is in a pocket. The phone plays a short acknowledgment tone. The hands-free VAD session starts automatically — the user speaks their note, the VAD detects the end of speech, and the transcript is saved and enqueued for sync. After the session completes, the app returns to wake word listening.

---

## Solution Design

### Microphone ownership model

The microphone is an exclusive resource (ADR-AUDIO-005). Wake word detection (Porcupine) and hands-free recording (VAD + `record` package) both need audio input. They cannot run simultaneously.

State machine for microphone ownership (see also extended version with error transitions in Core activation bridge section):

```
[wake_word_listening] --(wake word detected)--> [hands_free_session]
[hands_free_session] --(session ends/timeout)--> [wake_word_listening]
[wake_word_listening] --(wakeWordPauseRequestProvider=true)--> [idle]
[idle] --(wakeWordPauseRequestProvider=false)--> [wake_word_listening]
[any] --(user disables background listening)--> [idle]
[idle] --(user enables background listening)--> [wake_word_listening]
[wake_word_listening] --(Porcupine error)--> [error]
[error] --(auto-retry after 5s / user fixes config)--> [wake_word_listening]
```

Transitions are managed by `ActivationController` (new) which coordinates between `WakeWordService` (new) and the existing `HandsFreeController.suspendForManualRecording()` / `resumeAfterManualRecording()` pattern. Cross-feature coordination uses core-layer providers exclusively (see Core activation bridge).

### Background service infrastructure

Located in `core/background/` — this is app-level infrastructure, not feature-specific. Any feature that needs background execution in the future uses this module.

#### Isolate model (critical design decision)

`flutter_foreground_task` supports two execution models: (a) `TaskHandler` callbacks in a background isolate with send-port communication, and (b) foreground service as a keepalive for the main Flutter isolate. **This proposal uses model (b) — the foreground service is purely a keepalive.** PorcupineManager, ActivationController, and all Riverpod providers run in the main Dart isolate. The foreground service prevents Android from killing the app process when backgrounded. No `TaskHandler` is needed; no send-port communication is needed. Notification actions (the "Stop" button) use a native `PendingIntent` writing to SharedPreferences rather than the `TaskHandler` notification callback API — see Android persistent notification section.

On iOS, `UIBackgroundModes: audio` + an active audio session achieves the same keepalive effect — iOS keeps the app process alive while audio hardware is in use.

**Android:** `flutter_foreground_task` package creates a foreground service with `microphone` type. Configured with `FlutterForegroundTask.init()` before `runApp()` and started/stopped via `FlutterForegroundTask.startService()` / `stopService()`. The notification is managed through the same API.

**iOS:** `UIBackgroundModes: audio` entitlement in `Info.plist`. The audio session category must be switched at runtime depending on background listening state:

- **Background listening disabled (default):** Audio session stays `ambient` (ADR-AUDIO-007) — respects silent switch, mixes with other audio, stops on background.
- **Background listening enabled:** Audio session switches to `playAndRecord` via a shared `AudioSessionManager` (new, in `core/background/`) that calls `AVAudioSession.setCategory()` through a platform channel. This keeps audio hardware alive in background and allows simultaneous input/output. It ignores the iOS hardware silent switch while active, which is acceptable because the user has explicitly opted into background listening.

The `AudioSessionManager` is a thin native bridge (`MethodChannel('com.voiceagent/audio_session')`) that manages the app-level AVAudioSession category. The existing `AudioContextIOS(category: ambient)` on `AudioPlayer` instances (ADR-AUDIO-007) is superseded by the app-level session when background listening is active. On `stopService()`, the manager reverts to `ambient`.

`BackgroundService` interface lives in `core/background/background_service.dart`. Implementation (`FlutterForegroundTaskBackgroundService`) lives in `core/background/flutter_foreground_task_service.dart`. Provider in `core/background/background_service_provider.dart`.

#### SyncWorker background gating

The existing `SyncWorker` (5s `Timer.periodic` calling `_drain()` via `_scheduleDrain()`, plus an immediate `_drain()` on start and on connectivity `resume()`) has no foreground/background awareness — if the isolate stays alive, it will sync in background, violating ADR-NET-002. Fix: add a `bool Function() isAppForegrounded` callback (injected via constructor) and check it as the **first line of `_drain()`** — `if (!isAppForegrounded()) return;`. This gates every entry point to `_drain()`: the periodic timer, the immediate call in `_scheduleDrain()`, and the `resume()` path. `AppShellScaffold` already observes `AppLifecycleState` for connectivity; extend this to set a core-level `appForegroundedProvider` (`StateProvider<bool>`, default: `true`). The `SyncWorker` constructor receives `() => ref.read(appForegroundedProvider)` as the callback. This preserves ADR-NET-002 without stopping the timer (which would require restart logic).

#### HandsFreeController provider scope

Currently `handsFreeControllerProvider` is only alive when `RecordingScreen` is mounted (`ref.watch` in `build()` keeps it alive, `initState()` calls `startSession()`). For background activation, the controller must be alive at app scope. Fix: add `ref.watch(handsFreeControllerProvider)` to `AppShellScaffold` (per ADR-ARCH-009 provider scope promotion pattern). `RecordingScreen` keeps its `ref.watch` in `build()` for UI rendering and keeps `startSession()` in `initState()` (now idempotent — early-returns if already active). `AppShellScaffold` must be converted from `ConsumerWidget` to `ConsumerStatefulWidget` to support `WidgetsBindingObserver` for `appForegroundedProvider`. This is a prerequisite change that must happen in T5 (lifecycle updates).

### Picovoice Porcupine integration

Package: `porcupine_flutter: ^4.0.0`

`WakeWordService` interface in `features/activation/domain/`:

```
abstract class WakeWordService {
  Future<void> startBuiltIn({required String accessKey, required List<BuiltInKeyword> keywords, required List<double> sensitivities})
  Future<void> startCustom({required String accessKey, required List<String> keywordPaths, required List<double> sensitivities})
  Future<void> stop()
  Stream<int> get detections      // emits keyword index on detection
  Stream<WakeWordError> get errors  // emits typed errors (invalidKey, corruptModel, audioFailure)
  bool get isListening
  void dispose()
}
```

`BuiltInKeyword` is an enum wrapping Porcupine's built-in keywords (e.g. `jarvis`, `computer`, `alexa`). `WakeWordError` is a sealed class with variants: `invalidAccessKey`, `corruptModel(String path)`, `audioCaptureFailed(String reason)`, `unknownError(String message)`.

`PorcupineWakeWordService` implementation in `features/activation/data/`:
- `startBuiltIn()` uses `PorcupineManager.fromBuiltInKeywords()` for default keywords
- `startCustom()` uses `PorcupineManager.fromKeywordPaths()` for user-trained `.ppn` files
- `stop()` stops and deletes PorcupineManager (releases audio)
- `detections` stream emits keyword index via a StreamController fed by the PorcupineManager detection callback
- `errors` stream emits typed `WakeWordError` from the PorcupineManager error callback, classifying errors by inspecting the exception message/type

Porcupine AccessKey stored in `FlutterSecureStorage` (same pattern as Groq API key — ADR-DATA-004).

Built-in keywords (shipped with `porcupine_flutter`): "Jarvis", "Computer", "Hey Google", "Alexa", etc. Default: "Jarvis". Custom `.ppn` files can be placed in `assets/wake_words/` for user-trained wake words.

### Core activation bridge

Per ADR-ARCH-008 (ephemeral cross-feature state), cross-feature coordination goes through core-layer providers. All cross-feature communication uses providers in `core/providers/` (alongside existing `latestAgentReplyProvider`).

New providers in `core/providers/`:

**`activationEventProvider`**: `StateProvider<ActivationEvent?>` — set by `features/activation/`, observed by `features/recording/`. Triggers hands-free session start.

`ActivationEvent` enum: `{ wakeWordDetected, shortcutActivated }`

**`handsFreeSessionActiveProvider`**: `StateProvider<HandsFreeSessionStatus>` — set by `features/recording/`, observed by `features/activation/`. Signals session lifecycle without cross-feature imports. `HandsFreeSessionStatus` is a sealed class in `core/providers/`:

```
sealed class HandsFreeSessionStatus { const HandsFreeSessionStatus(); }
class HandsFreeSessionInactive extends HandsFreeSessionStatus { const HandsFreeSessionInactive(); }
class HandsFreeSessionRunning extends HandsFreeSessionStatus { const HandsFreeSessionRunning(); }
class HandsFreeSessionCompletedOk extends HandsFreeSessionStatus { const HandsFreeSessionCompletedOk(); }
class HandsFreeSessionFailed extends HandsFreeSessionStatus {
  const HandsFreeSessionFailed({required this.message, this.requiresSettings = false});
  final String message;
  final bool requiresSettings;  // mirrors HandsFreeSessionError.requiresSettings
}
```

This allows `ActivationController` to distinguish normal completion (restart wake word) from error (transition to error state with the message, auto-retry or require settings). The provider defaults to `HandsFreeSessionInactive()`.

**`wakeWordPauseRequestProvider`**: `StateProvider<Completer<void>?>` — set by `features/recording/` (before manual recording) with a fresh `Completer`, observed by `features/activation/` (stops Porcupine, then completes the Completer). `RecordingController` awaits the Completer's future before opening the microphone, ensuring Porcupine has fully released audio hardware. Reset to `null` by `features/recording/` when recording ends.

This ensures **zero cross-feature imports**. Both features read/write only core-layer providers. The `Completer` pattern provides the async acknowledgment that a bare `bool` cannot — the recording feature knows Porcupine has stopped before it tries to acquire the mic.

**`ActivationState` sealed class** (in `features/activation/domain/activation_state.dart`):

```
sealed class ActivationState {
  const ActivationState();
}
class ActivationIdle extends ActivationState { const ActivationIdle(); }
class ActivationListening extends ActivationState {
  const ActivationListening({required this.keyword});
  final String keyword;   // current wake word being detected
}
class ActivationHandsFreeActive extends ActivationState {
  const ActivationHandsFreeActive({required this.trigger});
  final ActivationEvent trigger;  // what triggered the session
}
class ActivationError extends ActivationState {
  const ActivationError({required this.message, this.requiresSettings = false});
  final String message;
  final bool requiresSettings;  // true = missing access key, needs user action
}
```

Flow:
1. `ActivationController` detects wake word (or shortcut press)
2. Sets `activationEventProvider` to `wakeWordDetected` (or `shortcutActivated`)
3. `HandsFreeController` watches `activationEventProvider`
4. On non-null event: starts hands-free session (reusing existing `startSession()` logic), sets `handsFreeSessionActiveProvider` to `HandsFreeSessionRunning()`
5. After session ends normally: `HandsFreeController` sets `handsFreeSessionActiveProvider` to `HandsFreeSessionCompletedOk()`, resets `activationEventProvider` to `null`. After session error: sets to `HandsFreeSessionFailed(message: ...)`.
6. `ActivationController` watches `handsFreeSessionActiveProvider` — on `HandsFreeSessionCompletedOk`, restarts wake word listening. On `HandsFreeSessionFailed`, transitions to `ActivationError` using the structured `requiresSettings` flag (no message heuristics needed).

**Manual recording coordination (async handoff with acknowledgment):**
1. `RecordingController.startRecording()` creates a `Completer<void>` and sets `wakeWordPauseRequestProvider` to it
2. `RecordingController` awaits `completer.future` (blocks until Porcupine confirms release)
3. `ActivationController` watches the provider, sees non-null Completer, stops Porcupine, calls `completer.complete()`, transitions to `idle`
4. `RecordingController` receives completion, proceeds with manual recording (microphone guaranteed free)
5. On recording end: `RecordingController` sets `wakeWordPauseRequestProvider` to `null`
6. `ActivationController` sees `null`, restarts Porcupine

If `ActivationController` is in `idle` state (background listening disabled), the Completer completes immediately — no blocking. Timeout: `RecordingController` applies a 2-second timeout on the await; if exceeded, proceeds anyway (Porcupine likely already released or was never running).

**Error transitions in the state machine:**

```
[wake_word_listening] --(wake word detected)--> [hands_free_session]
[wake_word_listening] --(Porcupine error: invalid key/corrupt ppn/audio failure)--> [error]
[hands_free_session] --(session ends/timeout)--> [wake_word_listening]
[hands_free_session] --(session error)--> [error]
[wake_word_listening] --(user opens app + taps record)--> [idle] (via pause request)
[idle] --(manual recording ends)--> [wake_word_listening]
[any] --(user disables background listening)--> [idle]
[idle] --(user enables background listening)--> [wake_word_listening]
[error] --(requiresSettings: false, after 5s delay)--> [wake_word_listening] (auto-retry)
[error] --(requiresSettings: true)--> stays in [error] until user fixes config
```

### Lifecycle management updates

ADR-PLATFORM-002 is **partially superseded**:
- **Manual recording:** Still cancels on background (unchanged behavior)
- **Hands-free session triggered by wake word:** Continues in background (new behavior)
- **Wake word listening:** Continues in background (new behavior)
- **Hands-free session started manually from UI:** Still terminates on background (unchanged — user was looking at screen, backgrounding is likely intentional)

The distinction: `HandsFreeController` gains a `triggeredByActivation` flag. When `true`, `didChangeAppLifecycleState(paused)` does NOT terminate the session. When `false` (manual start from UI), existing cancel-on-background behavior is preserved.

### Android Quick Settings Tile

Native Kotlin `TileService` subclass (`VoiceAgentTileService`). The `TileService` runs in the app process but does NOT have direct access to the Flutter engine's `MethodChannel`. Communication uses `SharedPreferences` as a lightweight IPC bridge.

**SharedPreferences storage details:**
- **Android native side:** Uses `context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)` — this is the exact file that Flutter's `shared_preferences` package reads/writes on Android. All keys are prefixed with `flutter.` (the `shared_preferences` package convention).
- **Keys:** `flutter.activation_toggle_requested` (bool), `flutter.activation_stop_requested` (bool), `flutter.activation_state` (String: "active" or "inactive")
- **Flutter side:** Uses `SharedPreferencesAsync` (not the legacy `SharedPreferences.getInstance()`) to avoid stale cached values. `SharedPreferencesAsync.getBool()` reads directly from disk on each call, ensuring native-written flags are always observed. The polling interval (10s) is acceptable latency for tile-to-app communication.
- **Flag lifecycle:** After reading a `true` flag, Flutter immediately writes it back to `false` to prevent re-processing on next poll cycle.

Communication flow:

- **Tile → Flutter (app alive):** When the foreground service is running, the Flutter engine is alive. `TileService.onClick()` writes `activation_toggle_requested=true` to SharedPreferences. `ActivationController` (running in the alive Dart isolate) detects the flag via periodic polling (10s interval) and on `AppLifecycleState.resumed`, calls `toggle()`, and clears the flag.
- **Tile → Flutter (app not alive):** When the app is not running (no foreground service, no Dart isolate), `TileService.onClick()` launches the app using a `PendingIntent` targeting `MainActivity` with an `ACTION_TOGGLE_ACTIVATION` extra. `MainActivity.onCreate()` / `onNewIntent()` reads the extra and forwards it to Flutter via `MethodChannel('com.voiceagent/activation')` once the Flutter engine is ready. `ActivationController` receives the toggle and starts background listening (which also starts the foreground service, keeping the Dart isolate alive for subsequent tile taps). This handles Android 12+ background-start restrictions because `TileService.onClick()` is a user-initiated action (explicit user tap), which is an exemption from foreground service background-start limits.
- **Flutter → Tile:** `ActivationController` writes `activation_state=active|inactive` to SharedPreferences. `TileService.onStartListening()` reads it and updates the tile icon/label.
- **Tile states:** active (microphone icon, "Listening"), inactive (microphone-off icon, "Tap to start")
- Works from lock screen without authentication (audio-only, no sensitive data shown)
- **Android 14+ microphone restriction:** Starting a `microphone`-type foreground service from background is restricted on Android 14+. The tile tap is a user-initiated exemption (system UI interaction). When the app is not alive, the `PendingIntent` launches the activity to foreground first, then starts the foreground service — this satisfies the "while-in-use" permission model.

### iOS Control Center control

The Control Center control runs as a **Widget Extension** (separate process), not inside the main app. It cannot directly call `FlutterMethodChannel`.

Architecture:
- **New Xcode target:** `VoiceAgentControl` (Widget Extension, iOS 18+)
- **Shared state:** App Group (`group.com.voiceagent.shared`) with `UserDefaults(suiteName:)` for cross-process state sharing
- **Control → App:** `ToggleVoiceAgentIntent` (conforms to `SetValueIntent<Bool>`) writes `activation_requested=true` to App Group UserDefaults and sets `openAppWhenRun = true` to launch/foreground the app. On launch or `didBecomeActive`, `AppDelegate` reads the flag and forwards it to Flutter via `MethodChannel`.
- **App → Control:** `ActivationController` writes `activation_state` to App Group UserDefaults (via a platform channel to native Swift). `ControlWidget.body` reads from the same UserDefaults to display current state.
- **Graceful absence:** The Widget Extension target is only compiled when the deployment target is iOS 18+. On older iOS, the control simply does not appear — no crash, no conditional code in the main app.

For iOS <18: the user configures the Action Button (iPhone 15 Pro+) or a home screen Shortcut to open the app. The app auto-starts wake word listening on launch when the setting is enabled. No custom code needed for this path.

### Android persistent notification

Provided by `flutter_foreground_task`. Configured with:
- Title: "Voice Agent" 
- Body: dynamic — "Listening for wake word..." / "Recording session active" / "Paused"
- Actions: "Stop" button to disable background listening
- Small icon: microphone icon
- Priority: low (non-intrusive)
- Ongoing: true (cannot be swiped away while active)

Notification text updates are driven by `ActivationController` state changes via `flutter_foreground_task` API.

**Notification action handling:** The "Stop" button uses a native `PendingIntent` (configured in the foreground service notification builder) that writes `activation_stop_requested=true` to SharedPreferences. `ActivationController` detects this flag via the same polling mechanism used for the Quick Settings tile and calls `stop()`. This avoids the need for a `TaskHandler` — the foreground service remains a pure keepalive with no send-port communication. The `flutter_foreground_task` package's `notificationButton` callback API requires a `TaskHandler` and is therefore NOT used; instead, the notification is built with a custom `PendingIntent` action via a platform channel call during `startService()` that configures the native notification builder directly.

### AudioFeedbackService extension

New method added to `AudioFeedbackService` interface:

```
Future<void> playWakeWordAcknowledgment()  — short distinct tone confirming wake word detected
```

Implementation in `AudioplayersAudioFeedbackService`: plays `assets/audio/wake_word_ack.mp3` (a short, distinctive chirp — must be clearly different from processing start jingle to avoid confusion). Follows the same `getEnabled()` guard pattern as other methods.

New audio asset: `assets/audio/wake_word_ack.mp3` (< 300 ms, CC0 license).

### AppConfig additions

New fields:

```
backgroundListeningEnabled: bool     // default: false (opt-in)
wakeWordEnabled: bool                // default: false (opt-in)  
picovoiceAccessKey: String?          // stored in SecureStorage
wakeWordKeyword: String              // default: 'jarvis' (built-in)
wakeWordSensitivity: double          // default: 0.5 (range 0.0-1.0)
```

All persisted via existing `AppConfigService` pattern (SharedPreferences for non-sensitive, SecureStorage for access key). `picovoiceAccessKey` follows the `groqApiKey` SecureStorage pattern exactly (ADR-DATA-004): loaded in `AppConfigService.load()` with try-catch for SecureStorage failures, `copyWith()` uses `_sentinel` pattern for nullable string.

---

## Affected Mutation Points

### Microphone acquisition points

**Needs change:**
- `HandsFreeController.startSession()` — must set `handsFreeSessionActiveProvider` to `HandsFreeSessionRunning()`, accept `triggeredByActivation` parameter
- `HandsFreeController.stopSession()` — must set `handsFreeSessionActiveProvider` to `HandsFreeSessionCompletedOk()`
- `HandsFreeController._terminateWithError()` — must set `handsFreeSessionActiveProvider` to `HandsFreeSessionFailed(message: ...)`
- `HandsFreeController.didChangeAppLifecycleState()` — conditional cancel based on `triggeredByActivation` flag
- `RecordingController.startRecording()` — must set `wakeWordPauseRequestProvider` to a `Completer<void>` and await its future before opening mic
- `RecordingController.cancelRecording()` / `stopAndTranscribe()` — must set `wakeWordPauseRequestProvider` to `null` after completion

**No change needed:**
- `HandsFreeOrchestrator.startEngine()` — internal to hands-free, microphone handoff happens before this is called
- `RecordingServiceImpl.start()` — internal to manual recording, same reasoning

### App lifecycle points

**Needs change:**
- `HandsFreeController.didChangeAppLifecycleState()` — add `triggeredByActivation` guard
- `main.dart` — initialize `FlutterForegroundTask.init()` config before `runApp()`

**No change needed:**
- `RecordingController.didChangeAppLifecycleState()` — manual recording cancel-on-background is preserved

**Needs change (newly identified):**
- `AppShellScaffold` — convert from `ConsumerWidget` to `ConsumerStatefulWidget` with `WidgetsBindingObserver`; add `handsFreeControllerProvider` watch (provider scope promotion, ADR-ARCH-009), add `appForegroundedProvider` lifecycle observer, add `activationControllerProvider` watch
- `SyncWorker._drain()` — add first-line `isAppForegrounded()` check to gate sync in background (ADR-NET-002)
- `SyncWorker` constructor — add `bool Function() isAppForegrounded` callback parameter
- `sync_provider.dart` — update `SyncWorker` construction to pass `isAppForegrounded: () => ref.read(appForegroundedProvider)`
- `RecordingScreen.initState()` — retain `startSession()` call (now idempotent when session is already active via AppShellScaffold promotion)

### Audio feedback points

**Needs change:**
- `AudioFeedbackService` interface — add `playWakeWordAcknowledgment()` method
- `AudioplayersAudioFeedbackService` — implement `playWakeWordAcknowledgment()`
- All test `_StubAudioFeedbackService` classes — add no-op stub for new method

### Configuration points

**Needs change:**
- `AppConfig` — add 5 new fields
- `AppConfig.copyWith()` — add 5 new parameters
- `AppConfigService.load()` — load new fields
- `AppConfigService` — add 5 new save methods
- `AppConfigNotifier` — add 5 new update methods
- `SettingsScreen` — add new "Background Activation" section

---

## Tasks

| # | Task | Layer | Depends on |
|---|------|-------|------------|
| T1 | AppConfig additions: new fields, persistence methods, notifier methods (no UI) | core/config | — |
| T2 | Background service infrastructure: `flutter_foreground_task` (Android) + `UIBackgroundModes` (iOS) + iOS audio session management + service lifecycle manager in `core/background/` | platform, core/background | T1 |
| T3 | Picovoice wake word integration: `WakeWordService` interface + `PorcupineWakeWordService` impl + provider + `AudioFeedbackService.playWakeWordAcknowledgment()` | features/activation, core/audio | T1 |
| T4a | Core activation bridge: `ActivationState` sealed class, core providers (`activationEventProvider`, `handsFreeSessionActiveProvider`, `wakeWordPauseRequestProvider`), `ActivationController` state machine | core/providers, features/activation | T2, T3 |
| T4b | `ActivationController` session lifecycle: `AppShellScaffold` wiring, wake word → session → wake word cycle integration | features/activation, app | T4a |
| T5 | Lifecycle updates: conditional cancel-on-background in `HandsFreeController`, `triggeredByActivation` flag, `activationEventProvider` watcher, `handsFreeSessionActiveProvider` writes, `wakeWordPauseRequestProvider` in `RecordingController` | features/recording | T4a |
| T6 | Settings UI: "Background Activation" section in Settings screen | features/settings | T1 |
| T7 | Android Quick Settings Tile + notification controls: native `TileService`, `MethodChannel` bridge, notification action handlers | platform (Android), features/activation | T4b |
| T8 | iOS Control Center control: `ControlWidget`, `ToggleVoiceAgentIntent` with `openAppWhenRun`, `MethodChannel` bridge | platform (iOS), features/activation | T4b |

### T1 details — AppConfig additions

- `AppConfig`: add `backgroundListeningEnabled` (bool, default: false), `wakeWordEnabled` (bool, default: false), `picovoiceAccessKey` (String?, SecureStorage), `wakeWordKeyword` (String, default: 'jarvis'), `wakeWordSensitivity` (double, default: 0.5)
- `AppConfig.copyWith()`: add corresponding parameters (`picovoiceAccessKey` uses `_sentinel` pattern like `groqApiKey`)
- `AppConfigService.load()`: load new fields from SharedPreferences + SecureStorage (follow `groqApiKey` pattern with try-catch, ADR-DATA-004)
- `AppConfigService`: add `saveBackgroundListeningEnabled()`, `saveWakeWordEnabled()`, `savePicovoiceAccessKey()`, `saveWakeWordKeyword()`, `saveWakeWordSensitivity()`
- `AppConfigNotifier`: add corresponding `update*()` methods
- Update all test files with `AppConfig` construction — add new fields with defaults (non-breaking, fields have defaults)
- Tests: unit tests for load/save round-trip of new fields, SecureStorage error handling for access key

### T2 details — Background service infrastructure

- Add `flutter_foreground_task: ^9.2.2` to `pubspec.yaml`
- Add `android.permission.FOREGROUND_SERVICE`, `android.permission.FOREGROUND_SERVICE_MICROPHONE`, `android.permission.POST_NOTIFICATIONS`, and `android.permission.INTERNET` to `AndroidManifest.xml` (INTERNET is required by Porcupine for access key validation; the app likely already has it for API sync but the manifest should declare it explicitly)
- Add `<service>` declaration for `flutter_foreground_task` in `AndroidManifest.xml`
- Add `UIBackgroundModes: audio` to `ios/Runner/Info.plist`
- Create `core/background/background_service.dart`: abstract interface — `startService()`, `stopService()`, `updateNotification(title, body)`, `isRunning` getter
- Create `core/background/flutter_foreground_task_service.dart`: implementation wrapping `flutter_foreground_task` API
  - `startService()`: starts foreground service (Android) AND calls `AudioSessionManager.setPlayAndRecord()` (iOS) via the native `MethodChannel('com.voiceagent/audio_session')` bridge. This sets the app-level `AVAudioSession` category to `playAndRecord`, which supersedes the per-player `AudioContextIOS(category: ambient)` and keeps the app alive in background.
  - `stopService()`: stops foreground service (Android) AND calls `AudioSessionManager.setAmbient()` (iOS) to revert to the `ambient` category (restoring ADR-AUDIO-007 default).
- Create `core/background/background_service_provider.dart`: `Provider<BackgroundService>` with `ref.onDispose`
- Initialize foreground task config in `main.dart` (after storage init, before `runApp()`) — `FlutterForegroundTask.init()` is global config, not service start
- Runtime `POST_NOTIFICATIONS` permission request on Android 13+ (API 33+) — requested when user first enables background listening in Settings; foreground service can still run without notification permission but notification won't be visible
- Tests: unit tests for `FlutterForegroundTaskBackgroundService` with mocked `flutter_foreground_task` — verify start/stop lifecycle, notification updates, iOS audio session category switch
- Update all test files with `implements` fakes if needed for new providers

### T3 details — Picovoice wake word integration

- Add `porcupine_flutter: ^4.0.0` to `pubspec.yaml`
- Create `features/activation/domain/wake_word_service.dart`: abstract interface with `startBuiltIn()`, `startCustom()`, `stop()`, `detections` stream, `errors` stream, `isListening`, `dispose()` (as specified in Solution Design)
- Create `features/activation/data/porcupine_wake_word_service.dart`: `PorcupineManager` wrapper implementing `WakeWordService`
- Create `features/activation/presentation/wake_word_provider.dart`: `Provider<WakeWordService>` with `ref.onDispose`
- Ship default built-in keyword: `porcupine_flutter` includes built-in keywords accessible by name (no `.ppn` file needed for defaults)
- Add `assets/wake_words/` directory for custom `.ppn` files (empty initially, documented in README)
- Add `playWakeWordAcknowledgment()` method to `AudioFeedbackService` interface + implementation in `AudioplayersAudioFeedbackService` + new `assets/audio/wake_word_ack.mp3` asset
- Tests: unit tests with mocked `PorcupineManager` — start/stop lifecycle, detection stream emission, error handling (invalid key, corrupt ppn, audio failure), double-start guard, stop-when-not-running guard; unit test for `playWakeWordAcknowledgment()`

### T4a details — Core activation bridge

- Create `core/providers/activation_event.dart`: `enum ActivationEvent { wakeWordDetected, shortcutActivated }`
- Create `core/providers/hands_free_session_status.dart`: `HandsFreeSessionStatus` sealed class (Inactive, Running, CompletedOk, Failed) — core type used by both features/activation and features/recording
- Create `core/providers/activation_providers.dart`: `activationEventProvider`, `handsFreeSessionActiveProvider` (default: `HandsFreeSessionInactive()`), `wakeWordPauseRequestProvider` — all `StateProvider` in core
- Create `features/activation/domain/activation_state.dart`: `ActivationState` sealed class (Idle, Listening, HandsFreeActive, Error — as specified in Solution Design)
- Create `features/activation/presentation/activation_controller.dart`: `ActivationController extends StateNotifier<ActivationState>`
  - Owns the microphone ownership state machine (wake word vs hands-free vs manual)
  - Watches `handsFreeSessionActiveProvider` (core provider, NOT a recording feature import) to detect session end: `HandsFreeSessionCompletedOk` → restart wake word, `HandsFreeSessionFailed(message:)` → transition to `ActivationError` with appropriate recovery strategy
  - Watches `wakeWordPauseRequestProvider` to pause/resume Porcupine for manual recording
  - On wake word detection: stops Porcupine, sets `activationEventProvider`, plays acknowledgment tone via `audioFeedbackServiceProvider`
  - On session end: restarts Porcupine
  - `toggle()` method for Quick Settings tile / Control Center
  - Reads config from `appConfigProvider` for access key, keyword, sensitivity
  - Error recovery: auto-retry after 5s for transient errors; stay in error for config issues (requiresSettings: true)
- Create `features/activation/presentation/activation_provider.dart`: `StateNotifierProvider<ActivationController, ActivationState>`
- Tests: state machine transitions — idle→listening→sessionActive→listening cycle, toggle on/off, error recovery (transient auto-retry, config error stays), missing access key guard, config reload on settings change, wake word pause request handling

### T4b details — ActivationController session lifecycle

- Wire `ActivationController` observation in `AppShellScaffold` (alongside existing `syncWorkerProvider` watch)
- Integration: verify full cycle — wake word detection → session start → session end → wake word restart
- Integration: verify manual recording pause — pause request → Porcupine stops → recording → pause request cleared → Porcupine restarts
- Tests: integration-style tests with mocked providers verifying the full lifecycle cycle and manual recording coordination

### T5 details — Lifecycle updates

**Provider scope change (prerequisite):**
- Add `ref.watch(handsFreeControllerProvider)` to `AppShellScaffold` — the controller must be alive at app scope for background activation (ADR-ARCH-009). `RecordingScreen` keeps its existing `ref.watch(handsFreeControllerProvider)` in `build()` for UI rendering.
- Convert `AppShellScaffold` from `ConsumerWidget` to `ConsumerStatefulWidget` with `WidgetsBindingObserver` mixin on its `ConsumerState`. This enables `didChangeAppLifecycleState` for setting `appForegroundedProvider`. Call `WidgetsBinding.instance.addObserver(this)` in `initState()` and `removeObserver(this)` in `dispose()`.
- **Preserve P014 auto-start behavior:** `RecordingScreen.initState()` currently calls `ref.read(handsFreeControllerProvider.notifier).startSession()` when the screen mounts (P014 behavior). This call is retained — but `startSession()` gains an early return: `if (state is HandsFreeListening || state is HandsFreeCapturing || ...) return;` — idempotent when already running. When the controller is idle and the user navigates to `/record`, `startSession(triggeredByActivation: false)` starts a manual hands-free session, preserving existing behavior.
- Add `appForegroundedProvider` (`StateProvider<bool>`, default: `true`) in `core/providers/`. `AppShellScaffold` sets it via `WidgetsBindingObserver` (`resumed` → true, `paused` → false).
- `SyncWorker._drain()`: first-line check `if (!isAppForegrounded()) return;` — gates every entry point. This preserves ADR-NET-002 now that the isolate stays alive in background.

**HandsFreeController changes:**
- Add `bool _triggeredByActivation = false` field
- `startSession()`: accept optional `triggeredByActivation` parameter, store in field
- `didChangeAppLifecycleState()`: when `_triggeredByActivation == true` and state is paused, do NOT terminate — allow background continuation
- `stopSession()`: reset `_triggeredByActivation = false`, set `handsFreeSessionActiveProvider` to `HandsFreeSessionCompletedOk()`
- `_terminateWithError()`: set `handsFreeSessionActiveProvider` to `HandsFreeSessionFailed(message: ...)` (forwards error message from `HandsFreeSessionError` state)
- `startSession()`: set `handsFreeSessionActiveProvider` to `HandsFreeSessionRunning()` on successful start
- Add watcher for `activationEventProvider` — on non-null `wakeWordDetected` or `shortcutActivated` event, call `startSession(triggeredByActivation: true)`, then clear event

**RecordingController changes:**
- `startRecording()`: create `Completer<void>`, set `wakeWordPauseRequestProvider` to it, await `completer.future.timeout(Duration(seconds: 2))` before opening mic; set to `null` after recording ends (in both `cancelRecording()` and `stopAndTranscribe()`)

**Tests:**
- Verify background-cancel is skipped when `triggeredByActivation` is true
- Verify cancel still works when false (existing behavior preserved)
- Verify activation event triggers session start
- Verify `handsFreeSessionActiveProvider` is set to `HandsFreeSessionRunning()` on start, `HandsFreeSessionCompletedOk()` on normal stop, `HandsFreeSessionFailed(message:)` on error
- Verify `wakeWordPauseRequestProvider` Completer-based handoff: RecordingController awaits, ActivationController completes, microphone acquired only after completion
- Verify `SyncWorker._drain()` returns early when `isAppForegrounded()` returns `false` (test via constructor-injected callback)
- Verify provider scope: `handsFreeControllerProvider` alive without `RecordingScreen` mounted

### T6 details — Settings UI

- `SettingsScreen`: new "Background Activation" section after "Voice Activity Detection", containing:
  - `SwitchListTile` for background listening (key: `'background-listening-tile'`)
  - `SwitchListTile` for wake word detection (key: `'wake-word-tile'`, disabled when background listening is off)
  - `TextField` for Picovoice access key (masked, key: `'picovoice-key-field'`)
  - `DropdownButton` for wake word keyword selection (built-in options, key: `'wake-word-keyword-dropdown'`)
  - `Slider` for wake word sensitivity (0.0-1.0, key: `'wake-word-sensitivity-slider'`)
- Request `POST_NOTIFICATIONS` runtime permission (Android 13+) when user enables background listening for the first time
- **Microphone permission check:** When the user enables wake word detection, verify microphone permission via the existing `AudioRecorder.hasPermission()` path (same OS-level permission used by the `record` package — granted once per app, covers both `record` and `flutter_voice_processor`). If denied, show an inline error on the wake word toggle with a "Grant Permission" button that opens `openAppSettings()`. Do not enable wake word detection until permission is granted. This follows the same UX pattern as the existing recording permission flow.
- Tests: widget tests for new settings section — toggle visibility, validation, persistence callbacks, wake word tile disabled when background listening is off, microphone permission denied state rendering

### T7 details — Android Quick Settings Tile + notification controls

- Create `android/app/src/main/kotlin/.../VoiceAgentTileService.kt`: extends `TileService`
  - `onClick()`: if foreground service is running, writes `flutter.activation_toggle_requested=true` to `FlutterSharedPreferences`. If not running, launches `MainActivity` via `PendingIntent` with `ACTION_TOGGLE_ACTIVATION` extra (handles app-not-alive case).
  - `onStartListening()`: reads `flutter.activation_state` from `FlutterSharedPreferences`, updates tile icon/label
  - Tile icon: microphone (active state) / microphone-off (inactive state)
  - Tile label: "Voice Agent" / "Listening"
  - Helper: `isForegroundServiceRunning()` checks `ActivityManager.getRunningServices()` or a SharedPreferences flag set by Flutter on service start/stop
- Register `TileService` in `AndroidManifest.xml` with `android.service.quicksettings.action.QS_TILE` intent filter
- Update `MainActivity.kt`: override `onCreate()` / `onNewIntent()` to check for `ACTION_TOGGLE_ACTIVATION` extra and forward to Flutter via `MethodChannel('com.voiceagent/activation')` with method `toggleFromIntent`
- Create `features/activation/data/platform_channel_bridge.dart`: handles cross-process communication
  - Polls `SharedPreferencesAsync` for `activation_toggle_requested` and `activation_stop_requested` flags on lifecycle resume and periodic interval (10s)
  - On flag detected: calls `ActivationController.toggle()` or `.stop()`, clears flag by writing `false`
  - Writes `activation_state` to SharedPreferences on `ActivationController` state changes
  - Listens on `MethodChannel('com.voiceagent/activation')` for `toggleFromIntent` calls from `MainActivity` (tile tap when app was not alive)
  - Handles notification stop action via `activation_stop_requested` SharedPreferences flag
- Notification "Stop" button: configured during `startService()` via a platform channel call that sets up a native `PendingIntent` writing `flutter.activation_stop_requested=true` to SharedPreferences (avoids TaskHandler requirement)
- Tests: platform channel bridge unit tests — verify toggle flag detection (both SharedPreferences and MethodChannel paths), state write, notification stop flag detection, flag clear after processing

### T8 details — iOS Control Center control

- Create new Xcode Widget Extension target: `VoiceAgentControl` (iOS 18+ deployment target)
- Add App Group capability (`group.com.voiceagent.shared`) to both main app target and extension target
- Create `VoiceAgentControl/VoiceAgentControl.swift`: `ControlWidget` using `AppIntents` framework
  - `ToggleVoiceAgentIntent`: conforms to `SetValueIntent<Bool>`, sets `openAppWhenRun = true`
  - Reads/writes `activation_state` and `activation_requested` via `UserDefaults(suiteName: "group.com.voiceagent.shared")`
  - Control displays current state from shared UserDefaults
- Create native Swift bridge in `ios/Runner/ActivationBridge.swift`:
  - On `AppDelegate.applicationDidBecomeActive`: reads `activation_requested` from App Group UserDefaults, forwards to Flutter via `MethodChannel('com.voiceagent/activation')`
  - `ActivationController` writes state changes to App Group UserDefaults via the same channel
- Reuse `platform_channel_bridge.dart` from T7 for the Flutter-side handler (same method channel, platform-agnostic)
- `Info.plist`: update `NSMicrophoneUsageDescription` to cover background listening ("Voice Agent needs microphone access to record audio for transcription and to listen for your wake word in the background.")
- Tests: platform channel bridge tests cover the Flutter side; native Swift widget extension verified manually on device

---

## Test Impact

### Existing tests affected

- `test/features/recording/presentation/hands_free_controller_test.dart` — add tests for `triggeredByActivation` flag, activation event watcher; add `_StubActivationEvent` provider override
- `test/features/recording/presentation/recording_controller_test.dart` — add test for wake word pause coordination; add provider override
- `test/features/recording/presentation/recording_screen_test.dart` — add activation provider stub override
- `test/features/recording/presentation/recording_screen_hands_free_test.dart` — add activation provider stub override
- `test/features/recording/presentation/recording_screen_mic_button_test.dart` — add activation provider stub override
- `test/features/settings/settings_screen_test.dart` — add tests for new "Background Activation" section; add stub overrides for new providers
- `test/features/settings/advanced_settings_screen_test.dart` — add new config field stubs
- `test/app/app_shell_scaffold_test.dart` (if exists) — add activation provider observation test
- `test/app/router_test.dart` — add activation provider stub
- `test/app/app_test.dart` — add activation provider stub
- All test files with `AppConfig` construction — add new fields with defaults (non-breaking, fields have defaults)

### New tests

**T1:** `test/core/config/app_config_service_test.dart` (additions)
- Load/save round-trip for new fields
- SecureStorage error handling for picovoiceAccessKey

**T2:** `test/core/background/flutter_foreground_task_service_test.dart`
- Start/stop lifecycle
- Notification text updates
- Double-start guard (idempotent)
- iOS audio session category switch on start/stop

**T3:** `test/features/activation/data/porcupine_wake_word_service_test.dart`
- Start emits listening state
- Detection callback emits on stream
- Stop releases resources
- Error callback emits on error stream (invalid key, corrupt ppn, audio failure)
- Start without access key throws
- Double-start is idempotent
- `playWakeWordAcknowledgment()` unit test

**T4a:** `test/features/activation/presentation/activation_controller_test.dart`
- Full state machine cycle: idle → listening → session → listening
- Toggle on/off
- Missing access key → error state (requiresSettings: true, stays in error)
- Transient Porcupine error → error state → auto-retry after 5s
- Wake word disabled in config → skip Porcupine, only background service
- Config change (keyword/sensitivity) → restart Porcupine with new params
- Wake word pause request handling (pause → idle, unpause → listening)

**T4b:** `test/features/activation/presentation/activation_controller_integration_test.dart`
- Full lifecycle cycle with mocked providers
- Manual recording coordination cycle

**T5:** `test/features/recording/presentation/hands_free_controller_test.dart` (additions)
- `triggeredByActivation: true` → background does NOT cancel session
- `triggeredByActivation: false` → background cancels session (existing behavior preserved)
- Activation event watcher starts session
- `handsFreeSessionActiveProvider` transitions: `HandsFreeSessionRunning` on start, `HandsFreeSessionCompletedOk` on normal stop, `HandsFreeSessionFailed` on error
- `wakeWordPauseRequestProvider` set/cleared by `RecordingController` manual recording

**T6:** `test/features/settings/settings_screen_test.dart` (additions)
- Background Activation section visible
- Wake word tile disabled when background listening is off
- Sensitivity slider updates config
- Access key field persists on blur

**T7:** `test/features/activation/data/platform_channel_bridge_test.dart`
- `toggleActivation` method call dispatches to controller
- State changes send `updateTileState` to platform
- `stopActivation` dispatches stop

Run: `flutter analyze && flutter test`

---

## Acceptance Criteria

1. With background listening enabled and wake word configured, the app continues listening after being minimized (both platforms).
2. Saying the configured wake word triggers a hands-free VAD session automatically, with an acknowledgment tone.
3. After the hands-free session completes, the app returns to wake word listening without user interaction.
4. On Android, the Quick Settings tile toggles background listening from the lock screen.
5. On Android, a persistent notification shows current state ("Listening for wake word..." / "Recording session active") with a Stop button.
6. On iOS 18+, the Control Center control toggles background listening from the lock screen.
7. Manual recording (tap-to-record) pauses wake word listening and resumes it after recording ends.
8. Existing manual hands-free sessions (started from UI) still cancel on background (ADR-PLATFORM-002 preserved for manual starts).
9. All background activation features are disabled by default and require explicit opt-in in Settings.
10. Wake word detection runs entirely on-device — no audio data leaves the device for wake word purposes.
11. Missing Picovoice access key shows a clear error in Settings, does not crash.
12. `flutter test` and `flutter analyze` pass.
13. Foreground service notification disappears when background listening is disabled.
14. Invalid Picovoice access key shows an error state and disables wake word listening without crash.
15. If another app captures the microphone while wake word is listening, the app recovers gracefully when the microphone becomes available again (transitions to error, then auto-retries).
16. On iOS, the audio session reverts to `ambient` (respecting silent switch) when background listening is disabled.

---

## Risks

| Risk | Mitigation |
|------|------------|
| `flutter_voice_processor` (Porcupine audio) conflicts with `record` package for microphone access | Strict microphone ownership model — Porcupine stops completely before hands-free starts, and vice versa. Transition tested on physical devices. |
| Battery drain from continuous background audio processing | Porcupine is designed for always-on use (<1% CPU). Foreground service notification makes battery usage transparent. Settings toggle allows easy disable. |
| iOS kills background audio after extended silence | `playAndRecord` audio session with active PorcupineManager audio stream keeps the app alive. If iOS still reclaims, the app restarts wake word on next foreground via `didChangeAppLifecycleState(resumed)`. |
| iOS silent switch ignored when background listening is active | `playAndRecord` category does not respect the silent switch (unlike `ambient`). This is a necessary trade-off — `ambient` cannot keep the app alive in background. The audio feedback `getEnabled()` guard still prevents jingles when the user has disabled audio feedback in Settings. Documented in Settings UI. |
| `flutter_foreground_task` does not run PorcupineManager reliably in background | Fallback: if Dart isolate audio fails in background, implement native Porcupine in Kotlin/Swift service with platform channel notification on detection. This is a known escalation path documented by Picovoice. |
| Picovoice free tier changes or access key expires | Access key is user-managed. If Picovoice changes terms, wake word can be disabled independently — the rest of the activation features (shortcuts, tiles) still work. |
| Quick Settings Tile / Control Center not available on older OS versions | Tile requires Android 7+ (already our min SDK). Control Center control requires iOS 18+ — gracefully absent on older versions, documented in Settings. |
| Android 15 limits foreground services to 6 hours for some types | Use `microphone` foreground service type which is exempt from the 6-hour timeout (it is designed for ongoing audio capture). |
| Wake word false positives trigger unwanted recording sessions | Sensitivity is configurable (0.0-1.0). Default 0.5 balances detection rate and false positives. User can adjust in Settings. Sessions produce no harm — empty transcriptions are discarded by existing logic. |

---

## Alternatives Considered

**Native-only wake word (Kotlin/Swift, no Flutter):** More reliable for background audio but doubles the implementation effort. Each platform would need separate Porcupine integration, state management, and UI communication. The Flutter-based approach with `flutter_foreground_task` is the documented community pattern and sufficient for V1. Native escalation is a known fallback if Flutter background audio proves unreliable.

**openWakeWord (open-source, ONNX-based):** No vendor dependency, reuses existing ONNX runtime (Silero VAD). However: no Flutter SDK, no mobile-optimized models, smaller community, unproven on mobile. Picovoice has purpose-built mobile models and a Flutter SDK. Migration to openWakeWord is possible later if needed — the `WakeWordService` interface abstracts the implementation.

**Polling-based activation (periodic timer checks a "should activate" flag):** Simpler but does not solve the core problem — the user still needs another mechanism to set the flag. Wake word detection is the only truly hands-free activation method.

---

## Known Compromises and Follow-Up Direction

### Single built-in wake word selection (V1 pragmatism)

V1 offers a dropdown of Porcupine's built-in keywords ("Jarvis", "Computer", etc.) and a file path for custom `.ppn` files. There is no in-app UI for training custom wake words — users must use Picovoice Console externally and import the `.ppn` file. A future iteration could add a training UI or file picker for `.ppn` import.

### No background sync (V1 pragmatism)

When a wake-word-triggered session completes in the background, the transcript is saved to SQLite and enqueued but NOT synced until the app is next foregrounded (ADR-NET-002 preserved). This is acceptable — transcripts are safely queued and sync on next app open. A follow-up proposal could add background sync via `workmanager` if the delay becomes a user complaint.

### Flutter-based background audio (V1 pragmatism)

Running PorcupineManager in a Dart isolate kept alive by `flutter_foreground_task` is the simplest path but may have reliability issues on some devices (aggressive battery optimization, OEM-specific process killing). If V1 testing reveals reliability problems, the escalation path is clear: move Porcupine to a native Android Service / iOS background task with platform channel communication. The `WakeWordService` interface isolates this change.

### ADR-PLATFORM-002 partial supersession

The cancel-on-background policy is now conditional rather than absolute. The `triggeredByActivation` flag creates two behavior paths in `HandsFreeController.didChangeAppLifecycleState()`. This is a reasonable complexity increase — the flag is set at session start and cleared at session end, with no ambiguous intermediate states. Documented in ADR-PLATFORM-004.

### iOS audio session category runtime switch (ADR-AUDIO-007 amendment)

When background listening is enabled, the audio session switches from `ambient` to `playAndRecord`. This means the iOS hardware silent switch is ignored while background listening is active. This is a necessary trade-off — `ambient` category cannot keep the app alive in background. Documented in ADR-AUDIO-009 as a conditional override of ADR-AUDIO-007. The `ambient` default is preserved when background listening is disabled.

### WakeWordService interface placement (V1 pragmatism)

The `WakeWordService` interface is in `features/activation/domain/`, not `core/`. If future features need wake word events (e.g., a notification feature), the interface should be promoted to `core/` with only the implementation staying in `features/activation/data/`. For V1, there is only one consumer, so feature placement is appropriate.

### Microphone ownership as informal protocol

The microphone ownership state machine is enforced by `ActivationController` watching core providers, not by a formal `MicrophoneOwnershipService` type. If a fourth microphone consumer is added in the future, extracting a formal arbiter into `core/` would make ADR-AUDIO-005 enforceable at the type level. For V1 with three consumers (Porcupine, VAD, manual recording), the provider-based coordination is sufficient.

### HandsFreeController provider scope promotion

Moving `handsFreeControllerProvider` from screen-scoped (`RecordingScreen`) to app-scoped (`AppShellScaffold`) changes its lifecycle from transient to permanent. The criteria for this promotion and the idempotency requirements for screen-level `initState()` calls are documented in ADR-ARCH-009. If additional controllers need promotion in the future, they must meet the same criteria (cross-screen reactivity, negligible idle cost, idempotent screen-level triggers).

### Platform channel bridge as shared infrastructure

T7 and T8 both use the same `MethodChannel('com.voiceagent/activation')`. This is the first platform channel in the project. The naming convention, placement rules, and SharedPreferences/App Group IPC patterns are documented in ADR-PLATFORM-005. If future features need additional native bridges, consider extracting a platform channel registry in `core/platform/`. For now, a single channel with a method-name dispatcher is sufficient.
