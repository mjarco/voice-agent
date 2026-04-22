# Proposal 028 — Background TTS Playback for Hands-Free Sessions

## Status: Draft

## Prerequisites

- P026 (Remove Wake Word, Rewire FG Service) — FG service start/stop tied
  to hands-free session lifecycle.
- P027 (Background Sync While Hands-Free Session Active) — transcripts
  reach personal-agent in the background. Without P027 there is nothing
  to TTS back while backgrounded.

## Scope
- Risk: Medium — changes Android foreground service semantics (permission +
  service type). iOS requires no platform change (already covered by
  `UIBackgroundModes: audio` + `.playAndRecord`).
- Layers: platform/android (manifest + FG service type), `core/background`
- Expected PRs: 1

## Problem Statement

After P026 + P027, transcripts arrive at personal-agent and the agent replies
even while the phone is locked. But the reply is not read aloud until the user
unlocks the app. On iOS 17+ this works by accident/design (the active
`.playAndRecord` audio session + `UIBackgroundModes: audio` let
`AVSpeechSynthesizer` play in the background). **On Android 14+, TTS
playback from a foreground service requires the service to declare the
`mediaPlayback` service type and hold the `FOREGROUND_SERVICE_MEDIA_PLAYBACK`
permission.** Today the manifest declares only
`FOREGROUND_SERVICE_MICROPHONE`, so TTS triggered via
`FlutterTtsService.speak()` while backgrounded is silently throttled or
killed by the system.

Observed (iOS, after P027): reply is spoken live, as expected.
Observed on Android 14+ (expected, per research): reply would not be audible
in the background — the user would only hear it on returning to the app.

## Are We Solving the Right Problem?

**Root cause:** Android 14+ hardened the foreground service model: each FG
service must declare which special work it is doing. Our FG service declares
only `microphone`. When TTS playback is triggered, Android considers this
"media playback" and enforces the matching service type. Without the right
declaration, the audio is suppressed.

**Alternatives dismissed:**
- *Don't do TTS in background, show a silent notification instead.* Rejected.
  Defeats the hands-free flow — the user has a phone in a pocket and can't
  look at a notification.
- *Move TTS playback to a separate, short-lived FG service started only when
  a reply arrives.* Rejected as complexity for no gain. We already have a
  long-lived FG service tied to the session; adding a second short-lived one
  creates coordination headaches.
- *Use Android `MediaSession`/`MediaStyle` notifications for TTS.* Overkill
  for single-utterance TTS; the foreground service with `mediaPlayback` type
  is the idiomatic solution.

**Smallest change:** Add the `FOREGROUND_SERVICE_MEDIA_PLAYBACK` permission
and register both `microphone` and `mediaPlayback` service types when
starting the FG service.

## Goals

- TTS playback reads the agent reply aloud while the phone is locked, on
  both iOS and Android, while a hands-free session is active.
- No regression in foreground TTS.

## Non-Goals

- Sync changes. Scope of P027.
- iOS-specific work. Already covered by `UIBackgroundModes: audio` +
  `.playAndRecord` from P026's audio session.
- TTS voice/language selection changes (existing `flutter_tts` config
  stays).
- TTS audio routing under phone calls / Bluetooth intricacies — platform
  defaults apply.
- Android MediaSession integration (play/pause controls, lock-screen art).

## User-Visible Changes

After P027 + P028, with a hands-free session active and the phone locked:

- User speaks → transcript syncs (P027) → agent replies → **TTS reads the
  reply aloud through the speaker**, audible while the phone is locked, on
  both iOS and Android.
- No new UI. The persistent Android notification ("Voice Agent — Recording
  session active") stays; only the underlying FG service type changes.

## Solution Design

### Android: declare `mediaPlayback` permission and service type

Three changes, two Android-side and one cross-platform:

1. **Manifest** (`android/app/src/main/AndroidManifest.xml`): add
   `<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK"/>`.
2. **FG service registration**
   (`lib/core/background/flutter_foreground_task_service.dart:49-55`):
   change `serviceTypes: [ForegroundServiceTypes.microphone]` to
   `serviceTypes: [ForegroundServiceTypes.microphone,
   ForegroundServiceTypes.mediaPlayback]`.
3. **Lift the P027 TTS foreground gate**
   (`lib/features/api_sync/sync_worker.dart`, `_handleReply()`): P027 added
   `if (isAppForegrounded()) unawaited(ttsService.speak(...));` as a
   temporary guard until Android's FG service type issue was fixed. P028
   removes the `isAppForegrounded()` check and calls TTS unconditionally
   when `getTtsEnabled()` is true. Without this removal, the manifest +
   service-type change has no observable effect.

Android supports multi-type FG services in the manifest since API 29,
but the strict typed-service enforcement (with `FOREGROUND_SERVICE_*`
per-type permissions) begins at **Android 14 / API 34**. On API 24-33 the
manifest permission is a harmless no-op; on API 34+ it is required for
media playback while a typed FG service is active. Both types remain
active for the full duration of a hands-free session — no dynamic switching.

### iOS — no platform changes required

`UIBackgroundModes: audio` is already declared (P019 → preserved in P026).
The `AudioSessionBridge` already sets `.playAndRecord` with
`[.defaultToSpeaker, .allowBluetooth, .mixWithOthers]` at session start.
`flutter_tts` plays via `AVSpeechSynthesizer`, which routes through the
active audio session. Manual smoke in P028 confirms this works.

### `FlutterTtsService` stays unchanged

The service's `speak()` method does not touch audio session state. With
P026's `AudioSessionBridge` holding `.playAndRecord` on iOS and P028's
`mediaPlayback` service type on Android, TTS playback reaches the speaker
in both foreground and background.

### TTS-VAD interaction remains intact

`HandsFreeController.suspendForTts()` / `resumeAfterTts()` pauses VAD while
TTS plays to avoid mic feedback. This is triggered by `ttsPlayingProvider`
and fires regardless of whether the Record tab is visible — the listener
lives on `RecordingScreen` which is kept alive by the IndexedStack while
the tab exists.

## Affected Mutation Points

**Needs change:**
- `android/app/src/main/AndroidManifest.xml` — add
  `FOREGROUND_SERVICE_MEDIA_PLAYBACK` permission.
- `lib/core/background/flutter_foreground_task_service.dart:49-55` — add
  `ForegroundServiceTypes.mediaPlayback` to `serviceTypes`.
- `lib/features/api_sync/sync_worker.dart` — remove the P027
  `if (isAppForegrounded())` guard around `unawaited(ttsService.speak(...))`
  in `_handleReply()`. TTS is again invoked whenever `getTtsEnabled()` is
  true, regardless of foreground state.

**No change needed:**
- iOS native (bridge, Info.plist, entitlements).
- `FlutterTtsService` or its provider.
- VAD suspend/resume on TTS (`HandsFreeController.suspendForTts`) —
  triggered from `ttsPlayingProvider`, works regardless of app visibility.

## Tasks

| # | Task | Layer | Notes |
|---|------|-------|-------|
| T1 | Add `FOREGROUND_SERVICE_MEDIA_PLAYBACK` permission to `AndroidManifest.xml`. Update `FlutterForegroundTaskService.startService()` to declare both `microphone` and `mediaPlayback` service types. Remove the P027 `isAppForegrounded()` TTS foreground-gate in `sync_worker.dart` `_handleReply()`. Extend `flutter_foreground_task_service_test.dart` (if present) with an assertion that `startService` passes both service types. Update `sync_worker_test.dart` to remove the "TTS skipped when backgrounded" case added in P027. Manual smoke on iPhone 12 Pro + Android 14+ device: speak during locked session, verify TTS is audible. | platform/android, core/background, features/api_sync, test | Single small PR |

## Test Impact / Verification

**Existing tests affected:** none (`flutter_foreground_task_service_test.dart`
tests the service interface, not the Android-specific service types passed
to the platform).

**New tests:** none required — the change is a declaration. Verify in manual
smoke.

**Manual verification (required before marking Implemented):**
- iOS iPhone 12 Pro, release build: lock screen during active session,
  speak, verify TTS is audible through speaker while locked.
- Android 14+ device, release build: same flow. Verify no
  `ForegroundServiceStartNotAllowedException`,
  `SecurityException: Starting FGS with type mediaPlayback`, or
  `InvalidForegroundServiceTypeException` in logcat. Verify TTS audible
  while locked.
- Android pre-14 device (if available): same flow. No permission error
  expected (permission is a no-op there); TTS should also be audible.
- Both platforms: session-idle state after tab switch → no FG service → no
  regression.

**Commands:** `flutter analyze && flutter test`.

## Acceptance Criteria

1. With a hands-free session active on iOS, phone locked, personal-agent
   reply triggers TTS that is audible through the speaker without unlocking.
2. With a hands-free session active on Android 14+, same behavior — TTS
   audible while locked, no logcat errors about service type violations.
3. `flutter analyze` and `flutter test` both pass.
4. `AndroidManifest.xml` contains `FOREGROUND_SERVICE_MEDIA_PLAYBACK`
   permission.
5. `FlutterForegroundTaskService.startService()` registers both `microphone`
   and `mediaPlayback` service types.

## Risks

| Risk | Mitigation |
|------|------------|
| `flutter_foreground_task` SDK version may not support `ForegroundServiceTypes.mediaPlayback` | Verified: pubspec locks `flutter_foreground_task: ^9.2.2` which supports multi-type services. Re-verify during T1 implementation. |
| TTS audio routing under phone calls | iOS ducks or suspends our audio — desired behavior. Android follows OS audio focus. No explicit handling needed; default behavior is correct. |
| Android OEM-specific FG service killers | Out of scope — existed pre-P028. The `mediaPlayback` type does not change OEM kill behavior. |
| `flutter_tts` on Android may internally require its own audio focus request that fails under our FG service | If smoke reveals this, add `audioSession`/`awaitSynthCompletion` config to `FlutterTtsService`. Not expected based on research. |

## Known Compromises and Follow-Up Direction

- **No lock-screen media controls.** We don't surface the TTS as a
  `MediaSession`, so the user can't pause/skip from the lock screen.
  Acceptable — replies are short and per-utterance. A future proposal could
  add `MediaSession` if the UX needs it.
- **Battery impact** of continuous `mediaPlayback`-typed FG service is
  negligibly different from `microphone`-only. Both keep the process alive
  the same way.

## ADR Impact

No ADR changes. The change is a platform manifest + service type adjustment
to support behavior already sanctioned by P019/P026 (background audio for
active sessions). If there's an ADR that explicitly names
`FOREGROUND_SERVICE_MICROPHONE` as the single FG service type, amend it to
name both. Otherwise no documentation change.
