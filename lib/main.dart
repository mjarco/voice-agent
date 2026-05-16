// Default entrypoint, used by `flutter run` / `flutter test` when no
// explicit `--target` is passed. Delegates to `main_stable.dart` so the
// safe (no-telemetry) path is always the default.
//
// The dev-flavor build invokes `lib/main_dev.dart` directly via its
// Xcode scheme / Gradle flavor; see ADR-OBS-001 §2 and the build
// configs in `android/app/build.gradle.kts` and `ios/Flutter/*.xcconfig`.

import 'package:voice_agent/main_stable.dart' as stable;

Future<void> main() => stable.main();
