# Proposal 035 — Dual Installation via Flutter Flavors

## Status: Draft

## Origin

Conversation 2026-04-25. The user wants to run two separate installations of
voice-agent on the same device simultaneously: a stable build and an
experimental build. This allows testing new features without risking the
production workflow.

## Prerequisites

None. This is a build/config change that does not depend on any feature proposal.

## Scope

- Risk: Medium — touches Android build config, iOS Xcode schemes/xcconfigs,
  app naming, and bundle identifiers. Wrong config can break signing or builds.
- Layers: `android/app/build.gradle.kts`, `android/app/src/main/AndroidManifest.xml`,
  `ios/Runner.xcodeproj`, `ios/Flutter/*.xcconfig`, `lib/app/app.dart`
- Expected PRs: 1

## Problem Statement

Currently there is a single build variant. Installing a dev/experimental build
overwrites the stable build on the device because both share the same
application ID (`com.voiceagent.voice_agent`) and bundle identifier
(`com.voiceagent.voiceAgent`).

The user needs both versions side by side so they can:
1. Keep the stable version running for daily use (voice capture workflow).
2. Test experimental features on the same device without losing stable state
   (SQLite database, settings, sync queue).

## Approach — Flutter Flavors

Use Flutter's built-in flavor system with two flavors: **stable** and **dev**.

### What changes per flavor

| Aspect | stable | dev |
|--------|--------|-----|
| Android applicationId | `com.voiceagent.voice_agent` (unchanged) | `com.voiceagent.voice_agent.dev` |
| iOS bundle identifier | `com.voiceagent.voiceAgent` (unchanged) | `com.voiceagent.voiceAgent.dev` |
| App display name (Android) | Voice Agent | Voice Agent DEV |
| App display name (iOS) | Voice Agent | Voice Agent DEV |
| SQLite database | Separate per app (OS sandboxing) | Separate per app (OS sandboxing) |
| Settings / preferences | Separate per app (OS sandboxing) | Separate per app (OS sandboxing) |

Data isolation is automatic — different application IDs mean different app
sandboxes on both iOS and Android. No code changes needed for storage.

### What stays the same

- All Dart code, features, architecture — identical across flavors.
- API endpoint configuration — each installation has its own settings, so the
  user can point dev to a different personal-agent instance if desired.
- No conditional compilation or `#if` blocks. The flavor only affects naming
  and identifiers.
- Platform channel names — they use `com.voiceagent/media_button` and
  `com.voiceagent/audio_session` (not the applicationId), so they work
  unchanged across flavors.
- Entitlements — `Runner.entitlements` is currently empty. No per-flavor
  entitlements needed. If Siri or App Group entitlements are added later,
  they will require per-flavor entitlement files.

## Design

### Android (build.gradle.kts)

Add `productFlavors` block:

```kotlin
flavorDimensions += "environment"
productFlavors {
    create("stable") {
        dimension = "environment"
        applicationId = "com.voiceagent.voice_agent"
        resValue("string", "app_name", "Voice Agent")
    }
    create("dev") {
        dimension = "environment"
        applicationId = "com.voiceagent.voice_agent.dev"
        resValue("string", "app_name", "Voice Agent DEV")
    }
}
```

Update `AndroidManifest.xml`: replace hardcoded `android:label="voice_agent"`
with `android:label="@string/app_name"`.

### iOS (Xcode) — detailed xcconfig and scheme setup

#### Step 1: Create 6 build configurations

Duplicate each of the 3 existing configurations (Debug, Release, Profile)
for each flavor:

| Existing | Stable copy | Dev copy |
|----------|-------------|----------|
| Debug | Debug-stable | Debug-dev |
| Release | Release-stable | Release-dev |
| Profile | Profile-stable | Profile-dev |

After duplication, the original Debug/Release/Profile configs can be removed
(Flutter will use the flavor-specific ones via schemes).

#### Step 2: Create per-flavor xcconfig files

**`ios/Flutter/stable.xcconfig`:**
```
PRODUCT_BUNDLE_IDENTIFIER=com.voiceagent.voiceAgent
DISPLAY_NAME=Voice Agent
```

**`ios/Flutter/dev.xcconfig`:**
```
PRODUCT_BUNDLE_IDENTIFIER=com.voiceagent.voiceAgent.dev
DISPLAY_NAME=Voice Agent DEV
```

#### Step 3: Wire xcconfig include chain

Each flavor-build configuration xcconfig includes the flavor file first,
then the existing base config (which already includes Pods and Generated):

**`ios/Flutter/Debug-stable.xcconfig`:**
```
#include "stable.xcconfig"
#include "Debug.xcconfig"
```

**`ios/Flutter/Debug-dev.xcconfig`:**
```
#include "dev.xcconfig"
#include "Debug.xcconfig"
```

**`ios/Flutter/Release-stable.xcconfig`:**
```
#include "stable.xcconfig"
#include "Release.xcconfig"
```

**`ios/Flutter/Release-dev.xcconfig`:**
```
#include "dev.xcconfig"
#include "Release.xcconfig"
```

**`ios/Flutter/Profile-stable.xcconfig`:**
```
#include "stable.xcconfig"
#include "Profile.xcconfig"
```

**`ios/Flutter/Profile-dev.xcconfig`:**
```
#include "dev.xcconfig"
#include "Profile.xcconfig"
```

The existing `Debug.xcconfig` and `Release.xcconfig` remain unchanged (they
include Pods and Generated). A `Profile.xcconfig` may need to be created if
it doesn't exist — it should mirror `Release.xcconfig`.

#### Step 4: Update Info.plist

Replace the hardcoded display name:
```xml
<key>CFBundleDisplayName</key>
<string>$(DISPLAY_NAME)</string>
```

`CFBundleName` can also use `$(PRODUCT_NAME)` which Xcode sets automatically.

#### Step 5: Create Xcode schemes

Rename the existing `Runner.xcscheme` to `stable`. Create a new `dev` scheme.

- **`stable` scheme**: uses `Debug-stable` / `Release-stable` / `Profile-stable`
- **`dev` scheme**: uses `Debug-dev` / `Release-dev` / `Profile-dev`

Flutter matches `--flavor <name>` to the Xcode scheme with the same name.

Both schemes should be marked as "shared" (in `xcshareddata/xcschemes/`) so
they are committed to git.

### Dart — flavor-aware visual indicator

Use `appFlavor` from `package:flutter/services.dart` (auto-populated by
Flutter 3.22+ when using flavors — no `--dart-define` needed):

```dart
import 'package:flutter/services.dart';

final isDev = appFlavor == 'dev';
```

If `isDev`, wrap MaterialApp in a `Banner` widget showing "DEV". This makes
it visually obvious which installation the user is looking at.

### Bare `flutter run` — resolved

Once `productFlavors` are defined on Android, bare `flutter run` (without
`--flavor`) fails. This is expected and not avoidable.

**Resolution:** All Makefile run/build/install targets will require `--flavor`.
The default targets (`run-ios`, `run-web`, `install-ios`) will use `stable`.
Bare `flutter run` from the command line will show a clear error asking for
`--flavor`. This is documented in the updated Makefile help.

### Makefile updates

Update all existing run/install targets to include `--flavor stable` by
default. Add `*-dev` variants:

```makefile
## run-ios: Run stable flavor on iOS Simulator
run-ios: _ensure-simulator
	flutter run -d iPhone --flavor stable

## run-ios-dev: Run dev flavor on iOS Simulator
run-ios-dev: _ensure-simulator
	flutter run -d iPhone --flavor dev

## install-ios: Build and install stable on physical iOS device
install-ios:
	... flutter run -d "$$DEVICE_ID" --flavor stable

## install-ios-dev: Build and install dev on physical iOS device
install-ios-dev:
	... flutter run -d "$$DEVICE_ID" --flavor dev
```

Similarly for `run-web`, `run-macos`. The `analyze` and `test` targets are
flavor-independent and need no changes.

## Tasks

- **T1**: Android — add `productFlavors` to `build.gradle.kts`, update
  `AndroidManifest.xml` to use `@string/app_name`
- **T2**: iOS — create all 6 build configurations (Debug/Release/Profile x
  stable/dev), create `stable.xcconfig` and `dev.xcconfig` with per-flavor
  identifiers, create 6 flavor-build xcconfig files with correct include
  chain, update `Info.plist` to use `$(DISPLAY_NAME)`, rename `Runner.xcscheme`
  to `stable` and create `dev` scheme
- **T3**: Dart — add flavor-aware "DEV" banner using `appFlavor` from
  `package:flutter/services.dart`
- **T4**: Makefile — update all run/build/install targets to include
  `--flavor stable`, add `-dev` variants
- **T5**: Verify — `make verify` passes, install both flavors on the same
  device, confirm they coexist with separate data

## Acceptance Criteria

1. `flutter run --flavor stable` installs with the current app ID and name.
2. `flutter run --flavor dev` installs alongside stable with `.dev` suffix.
3. Both apps appear on the home screen with distinct names.
4. Both apps maintain separate databases and settings.
5. `make verify` passes (analyze + test are flavor-independent).
6. All Makefile run/install targets work with `--flavor` and produce clear
   output indicating which flavor is being used.
7. `flutter run` without `--flavor` shows a clear error (expected behavior).
8. Dev build shows a visible "DEV" banner in the UI.

## Alternatives Considered

**Separate git branches**: Maintain a `dev` branch with different identifiers.
Rejected — merge conflicts on every change, easy to forget to sync.

**`--dart-define` only**: Pass the app name at build time but keep the same
application ID. Rejected — same app ID means installations overwrite each
other, which is the core problem.

**Separate clone / working directory**: Clone the repo twice, manually edit
identifiers. Rejected — maintenance burden, easy to drift.

## Open Questions

1. **Dev app icon**: Generate a tinted/badged variant of the current icon, or
   just rely on the name + banner difference? A tinted icon is nicer but
   requires creating an additional asset set. Can be done as a follow-up.
