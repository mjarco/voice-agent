# Proposal 026 — Remove Wake Word, Rewire Foreground Service to Session Lifecycle, Clean Up Whisper Traces

## Status: Draft

## Prerequisites
- None — this proposal removes existing code and rewires one provider listener

## Scope
- Tasks: ~5
- Layers: features/activation (delete), features/recording (controller rewire), core/config (trim), features/settings (trim), core/audio (trim), platform native (iOS + Android), build (Makefile)
- Risk: Medium — deletes a merged feature (P019), removes 4 persisted settings, moves the foreground-service start/stop trigger from `ActivationController` to `HandsFreeController`, amends ADR-PLATFORM-004

---

## Problem Statement

Two pieces of dead/broken code currently sit in the project.

**1. Wake word feature (P019) is unusable for the user and adds dependency weight.** The user cannot register at Picovoice (account-gated). With wake word disabled but `backgroundListeningEnabled = true` (the user's actual configuration), the hands-free session technically continues across `paused` lifecycle — but the foreground service that should keep the process alive is **only triggered by `ActivationController`'s wake-word state machine**, not by an active hands-free session. Result: the iOS app suspends, ONNX Runtime + Silero VAD hold ~150 MB, and iOS kills it under memory pressure within minutes of locking the phone. The bug is not "background listening is wrong" — the bug is "foreground service is wired to the wrong state machine."

**2. Stale local-Whisper references.** Project STT runs against Groq's cloud `whisper-large-v3-turbo` API (per ADR-AUDIO-002). But the `Makefile` still has a `model` target downloading `ggml-base.bin` (~140 MB) for a never-wired whisper.cpp integration, `assets/models/README.md` instructs the user to run that command, and `CLAUDE.md` + `AGENTS.md` mention `whisper_flutter_new` as a dependency that doesn't appear in `pubspec.yaml` and isn't imported anywhere. New developers are misled.

Bundling both removals into one proposal is honest scope: both are "remove abandoned code that misleads or breaks the system." The work is structurally adjacent (touches the same `pubspec.yaml`, build config, and docs files) and small enough that splitting would just create busy-work.

---

## Are We Solving the Right Problem?

**Root cause of the crash:** P019 wired the foreground service trigger to `ActivationController` (which only transitions on wake-word events). When wake word is unconfigured but a hands-free session is active and the app backgrounds, the foreground service never starts because `ActivationController` never leaves `ActivationIdle`. iOS suspends the unprotected process and kills it under memory pressure. The crash is a symptom of a wiring choice, not of "background listening" as a concept.

**Why not just remove background listening entirely?** Originally I proposed that. The user rejected it: "if I go to background with the app, I want transcription to keep working." Background listening is the desired behavior — the user manually opens the app, lands on Record (auto-VAD-start), then locks the phone and expects the session to continue capturing thoughts. The wake-word feature was only one possible activation path, and it's the one being abandoned. Background-while-active is a separate (correct) behavior.

**Alternatives dismissed:**
- *Keep wake word disabled by default but leave the code in place.* Rejected — the dead code still ships in the binary, ships an extra ~5 MB of native pods, and pollutes `HandsFreeController` with `_triggeredByActivation` and `wakeWordPauseRequestProvider` coordination that exists only for wake-word ↔ manual-recording handoff (no longer needed once wake word is gone).
- *Keep `backgroundListeningEnabled` as an opt-in setting.* Considered. Rejected for V1 — the user's intent (lock-screen-keeps-listening) matches the always-on behavior, and the setting only existed because P019 wanted opt-in for the experimental wake-word feature. Removing the setting reduces UI surface, test surface, and migration complexity. If a user later asks for foreground-only mode, that's an opt-out toggle in a future proposal.
- *Make the foreground service global (always-on whenever the app is running).* Rejected — the foreground service exists specifically to signal "user-initiated audio task active." Running it whenever the app is open creates a permanent notification even when the user is on the Settings or Agenda tab. Tying it to session lifecycle gives the right semantics: "service runs because something needs the mic in background."

**Smallest change?** The minimum to fix the crash + remove wake word is: (a) delete the activation feature, (b) move the foreground service trigger from `ActivationController` to `HandsFreeController`'s state-change listener. Everything else (Whisper cleanup, settings removal, ADR updates, native cleanup of unused widgets/tiles) is mechanical follow-on. The proposal bundles them because they all flow from the same decision; splitting would be administrative.

---

## Goals

- Remove the Picovoice/Porcupine dependency and the account-gating barrier
- **Rewire foreground service start/stop to `HandsFreeController` state transitions** (the actual fix for the iOS crash)
- Restore the lock-screen-keeps-listening behavior to actually working: open app → Record tab → session starts → FG service starts → lock screen → session continues → unlock → session still active
- Remove dead `whisper.cpp` build targets and `whisper_flutter_new` documentation references
- Remove iOS Widget Extension and Android Quick Settings tile (both were wake-word toggles with nothing to toggle once wake word is gone)
- Reduce app binary size (~5–8 MB from `porcupine_flutter` native pods + Widget Extension target)

## Non-goals

- Re-adding wake word with a different SDK (decision: no in-app wake word, period — Siri Shortcuts is the activation alternative if the user wants hands-free launch)
- Implementing Siri Shortcuts integration (out of scope; iOS handles "Hey Siri, open Voice Agent" without app-side code; custom Shortcuts can be configured by the user in iOS Shortcuts app)
- Removing the foreground service or `flutter_foreground_task` dependency (these stay; only the trigger moves)
- Removing `UIBackgroundModes: audio` (stays; needed for background mic)
- Removing `AudioSessionBridge.swift` (stays; needed to switch iOS audio session to `playAndRecord` when session starts)
- Adding a "foreground-only" opt-out toggle (out of scope; can be added in a follow-up if requested)
- Removing or changing the existing Groq cloud STT (only the dead local-Whisper traces are touched)
- Solving the broader "ONNX Runtime memory footprint on iOS" question (the FG service rewire fixes the crash by giving the app the right memory budget; long-term VAD memory optimization is separate)

---

## User-Visible Changes

**Settings screen:** the entire "Background Activation" section is removed — Picovoice access key field, "Background listening" toggle, "Wake word detection" toggle, wake word keyword dropdown, sensitivity slider. The user's previous values are deleted from `SharedPreferences` and `flutter_secure_storage` on first launch.

**iOS:**
- No Control Center "Voice Agent" widget (the `ios/VoiceAgentControl/` extension is deleted).
- "Hey Siri, open Voice Agent" works as a system-wide app launch (no app-side code needed).
- When the user enters the Record tab, hands-free VAD starts (existing behavior). The iOS audio session switches to `playAndRecord` (existing `AudioSessionBridge` behavior).
- Lock screen with active session → session continues capturing in background, transcripts continue syncing on next foreground.

**Android:**
- No Quick Settings "Voice Agent" tile.
- When a hands-free session is active, a persistent notification appears: "Voice Agent — Recording session active." Notification disappears when the session ends or the user navigates off the Record tab.
- Lock screen with active session → notification stays, session continues, transcripts saved locally and synced when foregrounded again.

**Both platforms:** force-closing the app (swipe-up from app switcher) ends the session naturally with the process. Tab switch ends the session within ~1 second (existing behavior).

---

## Solution Design

### Architecture: foreground service follows the hands-free session

Today (broken):
```
Wake-word event   → ActivationController.startListening
                  → ActivationListening state
                  → BackgroundService.startService()
                  → notification: "Listening for wake word..."

Wake word detected → ActivationController._onDetection
                  → activationEventProvider triggers HandsFreeController.startSession
                  → ActivationHandsFreeActive state
                  → BackgroundService.updateNotification("Recording session active")
```

After P026 (wake word gone, hands-free is the only activation path):
```
RecordingScreen.initState  → HandsFreeController.startSession
                            → guards pass
                            → (NEW) await BackgroundService.startService()
                              → on iOS: AudioSessionBridge sets playAndRecord
                            → _startEngine() → orchestrator begins capture
                            → notification: "Recording session active"

Session ends (stop / error)  → HandsFreeController.stopSession() or _terminateWithError()
                             → await BackgroundService.stopService()
                               → on iOS: AudioSessionBridge sets ambient
                             → state → HandsFreeIdle / HandsFreeSessionError
```

**Mechanism: explicit calls in `HandsFreeController`, not a state listener.** The original state-listener design (mirroring `activation_provider.dart`) has a subtle ordering problem: the listener fires only after the state transitions to a non-idle variant, which happens only after `orchestrator.start()` emits `EngineListening` — which happens only after audio capture has begun. On iOS, this means the mic starts recording in `ambient` category, then switches to `playAndRecord` mid-flight. ADR-AUDIO-009 requires the category to be set BEFORE capture for correct `allowBluetooth`/`playAndRecord` options.

So instead: `HandsFreeController.startSession()` calls `await bg.startService()` after guards pass and BEFORE `_startEngine()`. `stopSession()` and `_terminateWithError()` both call `await bg.stopService()` before transitioning state. The `Ref` field on the controller already exists (used for `appConfigProvider`, `handsFreeEngineProvider`) — add a read of `backgroundServiceProvider` in these methods. No provider-factory listener needed.

Notification text is fixed ("Voice Agent — Recording session active") because the hands-free state machine has more granularity than the user needs in a notification.

### Lifecycle behavior on app pause

`HandsFreeController.didChangeAppLifecycleState` becomes a no-op for the `paused` state. The session continues running. The Android foreground service (started via the listener above when the session went active) keeps the process alive. The iOS audio session in `playAndRecord` mode + `UIBackgroundModes: audio` keeps the iOS process alive.

This is the intended behavior. The current code's `_terminateWithError('Interrupted: app backgrounded')` cancellation was a workaround for the broken FG service wiring; with the FG service now correctly tied to session lifecycle, the cancellation isn't needed.

### What gets deleted, what stays

Removal scope:

| Layer | What goes | What stays |
|-------|-----------|------------|
| `lib/features/activation/` | Entire directory (domain, data, presentation, providers) | — |
| `lib/core/background/` | Change hardcoded `startService()` notification text in `FlutterForegroundTaskService` from "Listening for wake word..." to a generic "Voice Agent — Starting..." (or similar) since the wake-word text no longer applies. `HandsFreeController.startSession()` calls `updateNotification(...)` with "Recording session active" immediately after `startService()` completes. | `BackgroundService` interface + `FlutterForegroundTaskService` implementation + provider — all stay |
| `lib/core/providers/` | `activation_event.dart`, `activation_providers.dart` (`bridgeStoreProvider`), `hands_free_session_status.dart` | `app_foreground_provider.dart` (used by sync gating) |
| `lib/core/audio/` | `playWakeWordAcknowledgment()` from `AudioFeedbackService` interface + impl + 7 test stubs + `assets/audio/wake_word_ack.mp3` | `AudioSessionBridge` provider — keep |
| `lib/core/config/app_config.dart` | Fields: `wakeWordEnabled`, `picovoiceAccessKey`, `wakeWordKeyword`, `wakeWordSensitivity`, `backgroundListeningEnabled` (always-on now) | Other fields unchanged |
| `lib/core/config/app_config_service.dart` | Save methods + SecureStorage key for picovoice; one-shot migration deletes 4 SharedPreferences wake-word keys + 1 SecureStorage key | — |
| `lib/core/config/app_config_provider.dart` | Remove notifier methods that mutate the deleted fields: `updateBackgroundListeningEnabled`, `updateWakeWordEnabled`, `updatePicovoiceAccessKey`, `updateWakeWordKeyword`, `updateWakeWordSensitivity` | — |
| `lib/features/recording/presentation/hands_free_controller.dart` | Remove: `_triggeredByActivation` field + param, `wakeWordPauseRequestProvider` listener wiring, `backgroundListeningEnabled` check in `didChangeAppLifecycleState` (becomes no-op), 3 direct writes (lines 214, 254, 472) + 2 calls to `_signalSessionFailed` (lines 188, 204) + the helper itself (lines 468-477). **Add: `await _ref.read(backgroundServiceProvider).startService()` in `startSession()` after guards pass and before `_startEngine()`. `await _ref.read(backgroundServiceProvider).stopService()` at start of `stopSession()` (after the idle guard) and start of `_terminateWithError()`. Best-effort updateNotification call after startService completes** | Everything else unchanged |
| `lib/features/recording/presentation/recording_providers.dart` | `ref.listen(activationEventProvider, ...)` block in `handsFreeControllerProvider` factory | — No new listener needed (FG service calls move into `HandsFreeController` directly for ordering — see Architecture section) |
| `lib/features/recording/presentation/recording_controller.dart` | Writes to `wakeWordPauseRequestProvider` | — |
| `lib/features/settings/settings_screen.dart` | "Background Activation" section UI (5 fields), including the `openAppSettings` call at line 113 (was for wake-word permission flow). | `permission_handler` import STAYS — `recording_screen.dart:160,364` still uses `openAppSettings`. |
| `lib/app/app_shell_scaffold.dart` | `ref.watch(activationControllerProvider)` | — |
| `lib/main.dart` | — | `FlutterForegroundTaskService.initForegroundTask()` call stays (FG service still in use) |
| `pubspec.yaml` | `porcupine_flutter: ^3.0.3`. Remove `assets/wake_words/`. Verify `flutter_voice_processor` (transitive) is gone after porcupine removal. | `flutter_foreground_task` stays |
| `assets/wake_words/` | Delete directory | — |
| iOS native | Delete `ios/Runner/ActivationBridge.swift`. Delete `ios/VoiceAgentControl/` widget extension directory (8 files). Edit `AppDelegate.swift`: remove `ActivationBridge.shared.configure(...)` call (line 16) and entire `applicationDidBecomeActive` override (lines 21-24). Keep `AudioSessionBridge.shared.configure(...)` (line 17) — needed for background mic. Keep `didInitializeImplicitFlutterEngine` body with `engineBridge.pluginRegistry`. Edit `ios/Runner.xcodeproj/project.pbxproj`: remove PBXBuildFile/PBXFileReference for `ActivationBridge.swift` (lines 12, 64), remove `VoiceAgentControl` group + targets + framework links + copy phases (multiple line ranges). Update `NSMicrophoneUsageDescription` to drop the wake-word clause. App Group `group.com.voiceagent.shared` was only in `VoiceAgentControl/VoiceAgentControl.entitlements:5` — disappears with the directory. | `AudioSessionBridge.swift` stays. `UIBackgroundModes: audio` in `Info.plist` stays. |
| Android native | Delete `VoiceAgentTileService.kt`. Edit `AndroidManifest.xml`: remove tile service entry. Revert `MainActivity.kt` to empty `class MainActivity : FlutterActivity()` template (drop `companion object`, `methodChannel`, `configureFlutterEngine`, `onCreate`, `onNewIntent`, `handleActivationIntent`). | `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MICROPHONE`, `POST_NOTIFICATIONS`, `RECORD_AUDIO`, `INTERNET` permissions all stay (needed for background recording session + sync). |
| `docs/decisions/` | — | **Amend** ADR-PLATFORM-005 — remove activation-IPC guidance (tile / Control Center IPC is gone) but KEEP the audio-session bridge guidance (`AudioSessionBridge.swift` + `com.voiceagent/audio_session` MethodChannel stay). **Amend** ADR-PLATFORM-004 (rationale changes from "wake-word activation continues across background" to "active hands-free session continues across background; FG service tied to session state"). ADR-PLATFORM-002 stays Accepted. ADR-AUDIO-009 stays Accepted, rationale updated. ADR-ARCH-009 stays Accepted, rationale updated (`handsFreeControllerProvider` is app-scoped because tab switching needs `stopSession()` access AND because the FG service listener lives in the provider factory). |
| Test helpers | Delete `test/helpers/stub_background_service.dart`? **No — keep.** `BackgroundService` stays in production code; the stub stays for test overrides. Update tests that override `bridgeStoreProvider.overrideWithValue(InMemoryBridgeStore())` — drop that override. Delete `test/helpers/in_memory_bridge_store.dart` (used only by activation feature). | `stub_background_service.dart` stays. |
| Tests | Delete `test/features/activation/` (3 files) and the `_TrackingWakeWordConfigService` helper class in `test/features/settings/settings_screen_test.dart`. Update `test/features/recording/presentation/hands_free_controller_test.dart` to drop background-lifecycle test cases that depended on `backgroundListeningEnabled`. Add new tests: "session always continues on paused", "FG service starts when session activates and stops when session returns to idle". Update `test/features/recording/presentation/recording_controller_test.dart` to drop `wakeWordPauseRequestProvider` test group (lines 405–450), the activation_providers import (line 24), and the `playWakeWordAcknowledgment` stub override (line 168). | Other tests unchanged. |

### Whisper trace cleanup

- `Makefile`:
  - Rename `WHISPER_MODEL_DIR` → `MODEL_DIR` (preserves `vad-model` and `clean` behavior — both reference this variable for the Silero VAD path)
  - Remove `WHISPER_MODEL_URL`, `WHISPER_MODEL_PATH`
  - Remove the `model` target (lines 18–25)
  - Update `setup: deps model vad-model` → `setup: deps vad-model` (line 37)
  - Remove `model` from `.PHONY` line (line 1)
- `assets/models/README.md`: remove the "Run 'make model' to download the Whisper base model" line
- `CLAUDE.md`: fix multiple references — line 5 "transcribes on-device using Whisper" → "transcribes via Groq cloud API"; line 82 remove `whisper_flutter_new`; line 266 remove "Whisper FFI"; line 435 update implementation example (`WhisperSttService` → `GroqSttService`); line 548 remove `make model` mentions and the Whisper download instructions in setup
- `AGENTS.md`: fix line 5 similarly ("on-device Whisper" → "Groq cloud API"). Remove "Whisper (whisper_flutter_new)" from line 9 (or whatever line references it).

### Migration

A one-shot migration runs on first launch of the new version, blocking `loadCompleted`:

1. Read flag `wake_word_removal_migration_done` from SharedPreferences. If true, skip.
2. `prefs.remove('wake_word_enabled')`, `'wake_word_keyword'`, `'wake_word_sensitivity'`, `'background_listening_enabled'` (the latter is removed because the setting no longer exists; behavior is now always-on)
3. Best-effort `prefs.remove('activation_state')`, `'activation_toggle_requested'`, `'activation_stop_requested'`, `'foreground_service_running'` (legacy IPC keys from deleted bridges)
4. `try { await secureStorage.delete(key: 'picovoice_access_key') } catch (_) { /* log only */ }`
5. Set the migration-done flag.

The migration is idempotent (flag-gated). First-launch latency cost: ~50–200 ms (one-time Keychain access). Acceptable.

---

## Affected Mutation Points

All code paths that reference wake word, the `ActivationController`, or the FG-service trigger:

**Needs change:**
- `lib/main.dart` — no change (FG service init stays)
- `lib/app/app_shell_scaffold.dart` — remove `ref.watch(activationControllerProvider)`
- `lib/features/recording/presentation/recording_providers.dart` — remove the activation-event `ref.listen` block. **Do NOT add a state listener** — FG service calls move into `HandsFreeController` directly (see Architecture section) for ordering correctness on iOS (ADR-AUDIO-009 requires `playAndRecord` set BEFORE capture).
- `lib/features/recording/presentation/hands_free_controller.dart` — see Removal scope row
- `lib/features/recording/presentation/recording_controller.dart` — remove all writes to `wakeWordPauseRequestProvider`
- `lib/features/settings/settings_screen.dart` — remove the section. `permission_handler` import stays (still used by recording screen).
- `lib/core/config/app_config.dart` — remove 5 fields + `copyWith` + constructor params
- `lib/core/config/app_config_service.dart` — remove 5 save methods + SecureStorage key + add `_runRemovalMigration()` to `load()`
- `lib/core/audio/audio_feedback_service.dart` — remove `playWakeWordAcknowledgment` from interface
- `lib/core/audio/audioplayers_audio_feedback_service.dart` — remove implementation lines 71-75
- `pubspec.yaml` — remove `porcupine_flutter`, the `assets/wake_words/` block; verify `flutter_voice_processor` is gone post-cleanup. `permission_handler` STAYS.
- iOS + Android native (per Removal scope table)
- 6 ADR files (per Removal scope table)
- 4 doc/build files (Whisper trace cleanup)

**No change needed:**
- `lib/features/recording/data/hands_free_orchestrator.dart` (engine unchanged)
- `lib/features/recording/data/vad_service_impl.dart` (Silero VAD unchanged)
- `lib/core/background/` (FG service infrastructure unchanged)
- `ios/Runner/AudioSessionBridge.swift` (still needed for background mic)
- All other features (agenda, plan, routines, chat, history, transcript, sync)

---

## Tasks

| # | Task | Layer |
|---|------|-------|
| T1+T2 | **Single PR.** Delete `lib/features/activation/`, `lib/core/providers/{activation_event,activation_providers,hands_free_session_status}.dart`, `assets/wake_words/`, `test/features/activation/`, `test/helpers/in_memory_bridge_store.dart`. Remove `porcupine_flutter` from pubspec. Update `app_shell_scaffold.dart` to drop `activationControllerProvider` watch. Simplify `HandsFreeController` per Removal scope. **Add explicit `BackgroundService.startService()` / `stopService()` calls inside `HandsFreeController.startSession()`, `stopSession()`, `_terminateWithError()`** (NOT a state listener — see Architecture section for rationale). Update `FlutterForegroundTaskService` initial notification text from "Listening for wake word..." to generic. Remove `wakeWordPauseRequestProvider` writes from `RecordingController`. Update test override lists across the suite (remove `bridgeStoreProvider.overrideWithValue(InMemoryBridgeStore())` from ~10 sites; `backgroundServiceProvider` overrides STAY since `BackgroundService` is still in use). Update `hands_free_controller_test.dart`: drop background-lifecycle cases that depended on `backgroundListeningEnabled`; add "session always continues on paused" + "FG service start/stop call ORDER (start before _startEngine; stop before idle transition)" tests via tracking stub. Update `recording_controller_test.dart` per Removal scope. | features/activation, core/providers, features/recording, core/background, app, pubspec, test |
| T3 | Cleanup `core/audio/AudioFeedbackService` interface (remove `playWakeWordAcknowledgment()`), implementation, `assets/audio/wake_word_ack.mp3` asset. Update 7 `_StubAudioFeedback` test stubs to drop the no-op override. Drop tests for `playWakeWordAcknowledgment` in `audioplayers_audio_feedback_service_test.dart`. | core/audio, test |
| T4 | Delete the 5 wake-word fields from `AppConfig` + their save methods + the 5 notifier methods in `app_config_provider.dart` (`updateBackgroundListeningEnabled`, `updateWakeWordEnabled`, `updatePicovoiceAccessKey`, `updateWakeWordKeyword`, `updateWakeWordSensitivity`). Remove "Background Activation" UI section from `SettingsScreen` (including the `openAppSettings` call at line 113 for wake-word permission flow). `permission_handler` import in settings stays. Add `_runRemovalMigration()` per Migration section. Update `test/core/config/app_config_service_test.dart`: drop the 7 references to `backgroundListeningEnabled` (lines 18, 24, 34, 40, 174, 189, 264) and any references to the other 4 wake-word fields. Tests: migration matrix (fresh install / full state / SecureStorage-only / already-migrated / SecureStorage delete throws / re-run idempotency / settings widget test). | core/config, features/settings, test |
| T5 | Native cleanup: iOS — delete `ActivationBridge.swift`, delete entire `ios/VoiceAgentControl/` widget extension directory, edit `AppDelegate.swift` (drop `ActivationBridge.shared.configure(...)` line 16 and the `applicationDidBecomeActive` override; keep `AudioSessionBridge` configure line 17 and `didInitializeImplicitFlutterEngine` with `engineBridge.pluginRegistry`). Edit `ios/Runner.xcodeproj/project.pbxproj` — remove `ActivationBridge.swift` PBX entries (lines 12, 64) and the entire `VoiceAgentControl` target/group/framework/copy-phase entries. Update `NSMicrophoneUsageDescription`. Android — delete `VoiceAgentTileService.kt`, remove tile service entry from `AndroidManifest.xml`, revert `MainActivity.kt` to empty `class MainActivity : FlutterActivity()`. Verify build: `flutter build ios --release --no-codesign` and `flutter build apk --release` must succeed. Manual smoke test on iPhone 12 Pro per T5 details below. | platform native (iOS + Android) |
| T6 | Documentation + ADR cleanup. Rename `WHISPER_MODEL_DIR` → `MODEL_DIR`, remove other Whisper Makefile pieces. Update `assets/models/README.md`. Update `CLAUDE.md` lines 5, 82, 266, 435, 548 (multiple Whisper references). Update `AGENTS.md` similarly. Mark P019 status `Reverted by P026`. Amend ADR-PLATFORM-004 (Decision section rewrite per T6 details). **Amend** ADR-PLATFORM-005 (remove activation-IPC, retain audio-session bridge guidance). Amend ADR-AUDIO-009 (trigger condition + "category set BEFORE capture" Consequences bullet). Amend ADR-ARCH-009 (rationale simplification — only tab-switch reason remains). **Two new ADRs land with this proposal** (already drafted in `docs/decisions/`): ADR-PLATFORM-006 (controller-owned FG service lifecycle) and ADR-DATA-009 (one-shot removal migration). `permission_handler` STAYS — used by `recording_screen.dart:160,364` for `openAppSettings()`; ADR-PLATFORM-003 unchanged. | docs, build |

### T1+T2 details

In-PR order to keep build green:

1. Edit `lib/main.dart` — no change (verify FG service init `FlutterForegroundTaskService.initForegroundTask()` is still there)
2. Edit `app_shell_scaffold.dart` — remove `ref.watch(activationControllerProvider)`
3. Edit `lib/features/recording/presentation/hands_free_controller.dart`:
   - Remove imports of `core/providers/activation_providers.dart`, `core/providers/hands_free_session_status.dart`, `features/activation/...`
   - Remove `_triggeredByActivation` field and the `triggeredByActivation` named param on `startSession()`
   - Replace `didChangeAppLifecycleState` with empty body (keep the override for clarity, with a comment explaining FG service handles background continuity):
     ```dart
     @override
     void didChangeAppLifecycleState(AppLifecycleState state) {
       // No-op: hands-free session continues across background transitions.
       // The foreground service (started explicitly by startSession() and
       // stopped by stopSession() / _terminateWithError()) keeps the process alive.
     }
     ```
   - Delete writes to `handsFreeSessionStatusProvider`: 3 direct writes (lines 214, 254, 472) plus the `_signalSessionFailed` helper (lines 468-477) and its 2 call sites (lines 188, 204)
   - Delete the `_signalSessionFailed` helper method entirely
   - Verify the missing-Groq-key path still sets `requiresAppSettings: true` directly on `HandsFreeSessionError` state (it does today, independently of `_signalSessionFailed`)
4. Edit `lib/features/recording/presentation/recording_providers.dart` — `handsFreeControllerProvider` factory:
   - Remove the `ref.listen(activationEventProvider, ...)` block
   - **Do NOT add a state listener.** FG service calls move into `HandsFreeController` directly (see step 3) for ordering correctness on iOS.

3a. Inside `HandsFreeController.startSession()`, after both guards pass and BEFORE `_startEngine()`:
   ```dart
   final bg = _ref.read(backgroundServiceProvider);
   await bg.startService();
   unawaited(bg.updateNotification(
     title: 'Voice Agent',
     body: 'Recording session active',
   ));
   ```

3b. Inside `HandsFreeController.stopSession()`, after the idle guard returns early:
   ```dart
   await _ref.read(backgroundServiceProvider).stopService();
   ```

3c. Inside `HandsFreeController._terminateWithError()`, before transitioning state:
   ```dart
   unawaited(_ref.read(backgroundServiceProvider).stopService());
   ```
   (`unawaited` here because `_terminateWithError` is sync; the FG service stop happens fire-and-forget. Acceptable because the next session start will await `startService` properly.)

3d. Add `import 'package:voice_agent/core/background/background_service_provider.dart';` to `hands_free_controller.dart`. Add `import 'dart:async';` if `unawaited` isn't already in scope.
5. Edit `lib/features/recording/presentation/recording_controller.dart` — remove all writes to `wakeWordPauseRequestProvider`. Remove import of `activation_providers.dart`.
6. Update test override lists — `grep -rn 'bridgeStoreProvider' test/` and remove every `.overrideWithValue(InMemoryBridgeStore())`. `backgroundServiceProvider` overrides STAY (BackgroundService still in production code).
7. Update `hands_free_controller_test.dart`:
   - Drop test cases that asserted "session continues only when `backgroundListeningEnabled = true`"
   - Replace with "session always continues on `AppLifecycleState.paused`" (single test)
   - **Delete the 5 test cases that read `handsFreeSessionStatusProvider`** (lines 595, 608, 620, 633, 646) — the provider is deleted in step 9
   - Override `backgroundServiceProvider` with a tracking stub `_TrackingBackgroundService` that records `startService`/`stopService`/`updateNotification` calls
   - Add new tests:
     - "`startSession` awaits `startService` before calling `_startEngine` (verify call order on the stub)"
     - "`stopSession` awaits `stopService` before transitioning state to `HandsFreeIdle`"
     - "`_terminateWithError` calls `stopService` (fire-and-forget acceptable)"
     - "Permission-denied or missing-Groq-key guard does NOT call `startService`"
8. Update `recording_controller_test.dart`: drop `import activation_providers.dart` (line 24), drop `_StubAudioFeedback.playWakeWordAcknowledgment()` override (line 168), delete the entire "wake-word pause" test group (lines 405–450).
9. Delete `lib/features/activation/`, `lib/core/providers/{activation_event,activation_providers,hands_free_session_status}.dart`, `assets/wake_words/`, `test/features/activation/`, `test/helpers/in_memory_bridge_store.dart`.
10. Edit `pubspec.yaml`: remove `porcupine_flutter`, remove `- assets/wake_words/` line. Run `flutter pub deps | grep flutter_voice_processor` — if absent, transitive cleanup is automatic.
11. `flutter pub get && flutter analyze && flutter test` — all green.

### T3 details

(Same as previous version — see proposal history.)
- `AudioFeedbackService` interface (`lib/core/audio/audio_feedback_service.dart`) loses `Future<void> playWakeWordAcknowledgment();`
- `AudioplayersAudioFeedbackService` (`lib/core/audio/audioplayers_audio_feedback_service.dart`) loses lines 71-75
- Delete `assets/audio/wake_word_ack.mp3`
- Update 7 `_StubAudioFeedback` overrides:
  - `test/app/app_shell_scaffold_test.dart`
  - `test/features/settings/settings_screen_test.dart`
  - `test/features/api_sync/sync_worker_test.dart`
  - `test/features/recording/presentation/recording_screen_test.dart`
  - `test/features/recording/presentation/recording_screen_hands_free_test.dart`
  - `test/features/recording/presentation/recording_screen_mic_button_test.dart`
  - `test/features/recording/presentation/hands_free_controller_test.dart`
- Drop `playWakeWordAcknowledgment` tests in `test/core/audio/audioplayers_audio_feedback_service_test.dart`
- Verify with `grep -rn 'playWakeWordAcknowledgment' lib/ test/` → zero results

### T4 details

`AppConfig` field list becomes (post-removal): `apiUrl`, `apiToken`, `groqApiKey`, `vadConfig`, `language`, `autoSend`, `keepHistory`, `ttsEnabled`, `audioFeedbackEnabled` (and any other unrelated fields). Verify exact current fields in `lib/core/config/app_config.dart` before implementing. The 5 deleted fields take their `copyWith` lines and constructor params with them.

`_TrackingWakeWordConfigService` helper class in `test/features/settings/settings_screen_test.dart` (lines ~488-500) and the test "Picovoice access key field is visible and persists on blur" (~line 375) — delete both.

`_runRemovalMigration()` pseudocode:
```
if prefs.getBool('wake_word_removal_migration_done') == true: return
for key in ['background_listening_enabled', 'wake_word_enabled', 'wake_word_keyword',
            'wake_word_sensitivity', 'activation_state', 'activation_toggle_requested',
            'activation_stop_requested', 'foreground_service_running']:
  prefs.remove(key)
try:
  await secureStorage.delete(key: 'picovoice_access_key')
except: log only
prefs.setBool('wake_word_removal_migration_done', true)
```

Runs synchronously inside `AppConfigService.load()` after the prefs handle is acquired and before `AppConfig` is constructed. Best-effort: on Android, `SharedPreferencesAsync` uses DataStore, so IPC keys written by the deleted Dart bridge linger but are harmless after the bridge code is gone.

Migration test matrix (in `test/core/config/app_config_service_migration_test.dart` or extend existing service test):
- **Fresh install** (no prefs at all) — migration runs, sets flag, all `remove()` calls are no-ops
- **Full state** (all 5 wake-word keys + 4 IPC keys + SecureStorage key set) — verify all 9 + 1 removals
- **SecureStorage-only state** — verify SecureStorage delete still happens
- **Already migrated** — verify no `remove()` calls re-execute
- **SecureStorage delete throws** — verify flag is still set, exception logged not propagated
- **Widget test**: settings screen does not contain "Background listening" / "Picovoice" / "Wake word" text

`permission_handler` STAYS in pubspec and in `lib/features/settings/settings_screen.dart` — verified: `lib/features/recording/presentation/recording_screen.dart:160,364` still call `openAppSettings()` for the permission-denied UI. ADR-PLATFORM-003 unchanged.

### T5 details

**iOS:**
- `ios/Runner/AppDelegate.swift` after edits should be:
  ```swift
  import Flutter
  import UIKit

  @main
  @objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
    override func application(
      _ application: UIApplication,
      didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
      return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
      GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
      if let controller = window?.rootViewController as? FlutterViewController {
        AudioSessionBridge.shared.configure(with: controller.binaryMessenger)
      }
    }
  }
  ```
- `ios/Runner/Info.plist` `NSMicrophoneUsageDescription` (line 73-74) update: "Voice Agent needs microphone access to record audio for transcription **and to continue recording when the app is in the background**." (Background recording is still a real use case.)
- `ios/VoiceAgentControl/` — delete the entire directory (8 files including `AppIntent.swift`, `VoiceAgentControl.swift`, `VoiceAgentControlBundle.swift`, `VoiceAgentControlControl.swift`, `VoiceAgentControlLiveActivity.swift`, `VoiceAgentControl.entitlements`, `Info.plist`, `Assets.xcassets`).
- `ios/Runner.xcodeproj/project.pbxproj` — surgical edits:
  - Remove PBXBuildFile entry for `ActivationBridge.swift` (line ~12)
  - Remove PBXFileReference entry for `ActivationBridge.swift` (line ~64)
  - Remove PBXFileReference entry for `AudioSessionBridge.swift` is **kept** (line ~63) — file stays
  - Remove `VoiceAgentControl` synchronized root group entry (line ~89)
  - Remove `VoiceAgentControl` reference in groups (line ~157)
  - Remove `ActivationBridge.swift` from PBXSourcesBuildPhase (line ~437)
  - Remove `WidgetKit.framework`, `SwiftUI.framework` references and the `Embed Foundation Extensions` copy phase entries (line ~35 area)
  - Use `xcodeproj` Ruby gem or careful manual edit; verify with `xcodebuild -list -project ios/Runner.xcodeproj`
- After edits, `pod install` in `ios/`
- `flutter build ios --release --no-codesign` must succeed

**Android:**
- Delete `android/app/src/main/kotlin/com/voiceagent/voice_agent/VoiceAgentTileService.kt`
- Edit `AndroidManifest.xml`: remove the `<service android:name=".VoiceAgentTileService" ...>` entry (lines ~30-40)
- Revert `MainActivity.kt` to:
  ```kotlin
  package com.voiceagent.voice_agent

  import io.flutter.embedding.android.FlutterActivity

  class MainActivity : FlutterActivity()
  ```
- Keep `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MICROPHONE`, `POST_NOTIFICATIONS`, `RECORD_AUDIO`, `INTERNET` permissions — all needed for background recording session
- Tile uses system drawables only — no project-level drawables to delete

**Manual smoke test on iPhone 12 Pro:**
1. `flutter run --release`
2. App opens on Record tab, VAD auto-starts (existing behavior); verify hands-free notification appears (iOS doesn't show one — verify via Console.app or instruments that `AVAudioSession` is in `playAndRecord` category)
3. Speak: "test message", verify Groq transcription saved to history
4. Lock screen
5. Speak: "second message" (within 30 seconds of locking, before iOS settles)
6. Unlock, navigate to History, verify "second message" was transcribed
7. Verify app process did not get killed (PID is the same as before lock)
8. Wait 10 minutes locked, repeat speak test, verify still working
9. Switch to Agenda tab → verify session stops (existing behavior from tab switch fix)
10. Force-close app from app switcher → verify graceful shutdown (no orphan processes)

### T6 details

(Same structure as previous; cite ADRs being amended:)
- ADR-PLATFORM-004: rewrite the Decision section (not just rationale). New text:
  ```
  ## Decision (P026 amendment)

  Cancel-on-background policy splits by recording mode:
  - Manual recording (RecordingController): cancels on background per ADR-PLATFORM-002 (unchanged).
  - Hands-free session (HandsFreeController): continues across background transitions.
    The foreground service (Android) and playAndRecord audio session (iOS) keep the process
    alive for the duration of the session.

  There is now a single hands-free session type. The previous trigger-source distinction
  (activation-triggered vs manually-started) and the backgroundListeningEnabled opt-in
  are removed by P026. Background continuity is unconditional for any active hands-free
  session and is controlled solely by session state, not by user setting or trigger source.

  ## Consequences (P026 amendment, additions)
  - HandsFreeController.didChangeAppLifecycleState(paused) is a no-op.
  - The foreground service start/stop is driven by HandsFreeController.startSession()
    and stopSession() / _terminateWithError() via explicit calls (see ADR-PLATFORM-006).
  - Manual recording behavior is unchanged — ADR-PLATFORM-002 applies.
  ```
- ADR-PLATFORM-005: **Amend** (not rescind). Remove activation-IPC sections (Android Quick Settings tile, iOS Control Center widget, polling-based IPC pattern for tile→app communication) — these are gone. KEEP the audio-session bridge guidance (`AudioSessionBridge.swift` + `com.voiceagent/audio_session` MethodChannel remain in use for iOS `playAndRecord` switching). Update status header to reflect scope reduction.
- ADR-AUDIO-009: amend trigger condition from "`backgroundListeningEnabled` setting" to "active hands-free session." The audio session category switches to `playAndRecord` when `HandsFreeController.startSession()` calls `BackgroundService.startService()` (BEFORE `_startEngine()`), and back to `ambient` when `stopService()` is called from `stopSession()` / `_terminateWithError()`. Add a Consequences bullet:
  ```
  - The category switch must happen BEFORE audio capture starts. HandsFreeController must
    await BackgroundService.startService() (which sets playAndRecord on iOS) before
    invoking HandsFreeEngine.start(). Reverse order risks recording in ambient category
    and switching mid-flight, which has produced allowBluetooth/playAndRecord option
    loss in past testing. Symmetrically, on session end, await stopService() before
    transitioning state to HandsFreeIdle.
  ```
- ADR-ARCH-009 (provider scope promotion): rationale simplification — `handsFreeControllerProvider` remains app-scoped because `AppShellScaffold.onDestinationSelected` calls `stopSession()` when the user navigates away from the Record tab and `startSession()` when they return. Screen-scoping would dispose the controller on tab switch, severing the in-flight session and deleting the WAV-cleanup / job-drain machinery mid-operation. Note: P019's secondary justification (cross-feature activation events forwarded via core providers) is gone — activation has been removed in P026. The single remaining justification (tab-switch lifecycle) still meets the three criteria in this ADR's Decision section.
- ADR-PLATFORM-002: no edit needed.

`Makefile` rename: `WHISPER_MODEL_DIR` → `MODEL_DIR`. Three references must be updated together: line 8 `VAD_MODEL_PATH := $(MODEL_DIR)/silero_vad_v5.onnx`, line 31 `mkdir -p $(MODEL_DIR)`, line 150 `clean: rm -rf $(MODEL_DIR)`. Then remove `WHISPER_MODEL_URL`, `WHISPER_MODEL_PATH`, the `model` target, `model` from `setup` deps, and `model` from `.PHONY`.

---

## Test Impact

### Existing tests affected

- `test/features/activation/**/*` — **deleted entirely** (3 files)
- `test/helpers/in_memory_bridge_store.dart` — deleted
- `test/features/recording/presentation/hands_free_controller_test.dart` — drop `backgroundListeningEnabled` test cases; add "always continues on paused" + "FG service follows session state" tests
- `test/features/recording/presentation/recording_controller_test.dart` — drop activation imports + `playWakeWordAcknowledgment` stub + wake-word pause test group
- 7 `_StubAudioFeedback` test stubs — drop `playWakeWordAcknowledgment` no-op overrides
- `test/core/audio/audioplayers_audio_feedback_service_test.dart` — drop wake-word ack tests
- `test/features/settings/settings_screen_test.dart` — drop `_TrackingWakeWordConfigService` helper + Picovoice key test
- `test/app/app_test.dart`, `test/app/app_shell_scaffold_test.dart`, `test/app/router_test.dart`, `test/features/settings/advanced_settings_screen_test.dart`, `test/features/api_sync/sync_worker_test.dart`, recording screen tests — drop `bridgeStoreProvider.overrideWithValue(InMemoryBridgeStore())` from override lists; `backgroundServiceProvider` overrides STAY

### New tests

- In `hands_free_controller_test.dart` (or in `recording_providers_test.dart` if better-suited): "FG service starts on session activation, stops on session idle"
- `test/core/config/app_config_service_migration_test.dart`: full migration matrix

### Run

```bash
flutter analyze         # zero issues
flutter test            # full suite green
flutter run --release   # manual smoke on iPhone 12 Pro
```

---

## Acceptance Criteria

1. After all tasks merged, the following greps across `lib/`, `test/`, `pubspec.yaml`, `Makefile`, `CLAUDE.md`, `AGENTS.md`, `ios/`, `android/`, `assets/` return zero results (excluding ADRs that intentionally reference rescinded decisions, and `lib/core/config/app_config_service.dart` which holds the migration flag key `wake_word_removal_migration_done` and the old `picovoice_access_key` SecureStorage key as a string literal in the migration code only): `porcupine`, `picovoice`, `flutter_voice_processor`, `whisper_flutter_new`, `wakeWord`, `wake_word`, `WakeWord`, `playWakeWordAcknowledgment`, `wake_word_ack`, `ActivationBridge`, `VoiceAgentTileService`, `ACTION_TOGGLE_ACTIVATION`, `group.com.voiceagent.shared`, `activationControllerProvider`, `activationEventProvider`, `wakeWordPauseRequestProvider`, `handsFreeSessionStatusProvider`, `bridgeStoreProvider`, `InMemoryBridgeStore`, `_signalSessionFailed`, `_triggeredByActivation`, `triggeredByActivation`.
2. `lib/features/activation/` directory does not exist. `assets/wake_words/`, `assets/audio/wake_word_ack.mp3`, and `ios/VoiceAgentControl/` do not exist.
3. `AudioFeedbackService` interface no longer contains `playWakeWordAcknowledgment`.
4. `lib/core/background/` and `flutter_foreground_task` dependency are intact (kept; used by `HandsFreeController` listener).
5. `flutter analyze` passes with zero issues.
6. `flutter test` passes with all tests green.
7. **App built in release mode launches on iPhone 12 Pro, opens on Record tab, auto-starts hands-free VAD, stays alive across screen lock for at least 10 minutes, and successfully transcribes utterances spoken with the screen locked.**
8. After 10 minutes of foreground listening on iPhone 12 Pro, app process RSS does not grow more than 50 MB above baseline.
9. After 1 hour of locked-screen state with active session, the app process is alive (verifiable: PID unchanged, history shows transcripts captured during locked period).
10. A user upgrading from a prior version with `picovoiceAccessKey` set in SecureStorage and `wakeWordEnabled = true` in SharedPreferences sees both removed after first launch, and the settings screen does not show any wake-word UI.
11. P019's status reads `Reverted by P026`. ADR-PLATFORM-005 scope is amended (activation-IPC removed, audio-session-bridge guidance retained). ADR-PLATFORM-004 rationale section reflects the new "FG service follows hands-free session" semantics. ADR-AUDIO-009 trigger condition is updated.
12. `make setup` succeeds without attempting to download `ggml-base.bin`.
13. Android: notification "Voice Agent — Recording session active" appears when hands-free session starts, disappears when it ends.

---

## Risks

| Risk | Mitigation |
|------|------------|
| Memory pressure still kills the app on iOS even with FG service / `playAndRecord` audio session | Acceptance criteria 7-9 cover this on iPhone 12 Pro. If the test fails, the fallback is a follow-up "release VAD model after N minutes idle" optimization in `HandsFreeController` (out of scope for P026 — would need its own proposal). |
| The explicit `BackgroundService.start/stop` calls in `HandsFreeController` may run out of order or skip in some edge cases | Test with a tracking stub that records call timestamps. Verify: `startService` completes BEFORE `_startEngine`; `stopService` completes BEFORE state transitions to `HandsFreeIdle`; failed permission/Groq-key guards do NOT call `startService`. |
| Removing `_signalSessionFailed` removes a side-effect that another feature depended on | Verified: only `ActivationController` reads `handsFreeSessionStatusProvider`. After `ActivationController` is deleted, the provider has no consumers. |
| Migration `secureStorage.delete()` throws on a corrupted Keychain — could block app start | Wrap in try/catch, log only, set migration flag anyway. |
| User who had Control Center widget configured on iOS sees it disappear after upgrade | iOS removes Control Center widgets automatically when the providing app no longer registers them. No user-facing breakage beyond the widget being gone. |
| Removing `wakeWordPauseRequestProvider` breaks the manual-recording-while-hands-free flow | Verified: `wakeWordPauseRequestProvider` was used to coordinate Porcupine's mic ownership ↔ `record` package's mic ownership. After Porcupine is gone, `record` is the only mic consumer and no coordination is needed. The hands-free engine's `suspendForManualRecording()` and `resumeAfterManualRecording()` methods stay (they're internal to `HandsFreeController`, not the wake-word pause provider). |
| Build break in T5 if Xcode project edits are imprecise | T5 includes `flutter build ios --release --no-codesign` as a verification step. If the build breaks, revert pbxproj edits and try `xcodeproj` Ruby gem for safer programmatic edits. |

---

## Alternatives Considered

**Soft-delete (set defaults to false, hide UI, keep code):** Rejected. The dead code still ships, still requires `_triggeredByActivation` and `wakeWordPauseRequestProvider` coordination in `HandsFreeController`, and still has the broken FG service wiring (which is the actual crash cause). "Hidden" is not "removed."

**Keep wake word disabled by default, only fix the FG service wiring:** Rejected. Removes the immediate crash but keeps a 5+ MB SDK dependency that the user cannot use, plus all the `ActivationController` coordination code, plus the platform tile/widget infrastructure for a feature nobody can configure. The FG service rewire is the same work either way; bundling the wake-word removal halves the long-term maintenance surface.

**Make foreground service global (always-on while app is running):** Rejected. The FG service exists to signal "user-initiated audio task active." Running it on the Settings or Agenda tab creates a permanent notification that confuses users. Tying it to session lifecycle gives the right semantics.

**Keep `backgroundListeningEnabled` as an opt-out toggle:** Considered. Rejected for V1 — the user's intent is "lock-screen-keeps-listening should just work." Setting adds UI surface, test surface, and migration complexity for a behavior nobody asked to disable. If a user later wants foreground-only mode, that's a follow-up opt-out.

---

## Known Compromises and Follow-Up Direction

### One-direction migration (V1 pragmatism)

The migration flag `wake_word_removal_migration_done` is set once and never inspected again. If a future proposal re-introduces wake word with the same setting names, the migration won't re-run for existing installs. This is intentional: re-introducing wake word is unlikely (Siri Shortcuts is the chosen alternative).

### Always-on background recording

After P026, the only way to disable background recording is to leave the Record tab or close the app. Power-conscious users who want explicit control will need a follow-up proposal adding an opt-out toggle. Acceptable tradeoff for the simplification — adding a "background listening: on/off" setting later is straightforward (the plumbing already exists in the form of the FG service).

### TTS no longer continues across foreground→background transition (verify)

`UIBackgroundModes: audio` stays for the mic, but the iOS audio session's behavior under TTS specifically depends on whether `flutter_tts` opts into background audio. Should be verified in T5 manual smoke test step 4 — if TTS gets cut on background, document as known regression and follow up.

### Notification channel `voice_agent_background` lingers on Android after FG service starts/stops cycles

`flutter_foreground_task` caches the channel registration in `NotificationManager`. The user can see the channel in app notification settings even when no notification is currently visible. Harmless but visible. Optional follow-up: provide a runtime call to delete the channel during certain teardowns. Not worth native code for one cosmetic stale entry.

### Migration first-launch latency

The migration runs synchronously inside `AppConfigService.load()` and adds 9 SharedPreferences `remove()` calls + 1 SecureStorage `delete()` to the critical startup path. On iOS this can add 50–200ms cold-start latency one time. Acceptable trade-off.

### `appForegroundedProvider` is now the lone reason for the lifecycle observer

After P026, `AppShellScaffold.didChangeAppLifecycleState` only updates `appForegroundedProvider` (used by sync gating per ADR-NET-002). Could be extracted into a tiny `AppForegroundObserver` widget so `AppShellScaffold` reverts to `ConsumerWidget`. Out of scope for P026; track as follow-up.
