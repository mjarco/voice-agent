import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// The installed app version, read from the bundle at runtime. Sourced from
/// `pubspec.yaml`'s `version:` line (the single source of truth), so anything
/// that surfaces the version reflects the build actually installed.
class AppVersion {
  const AppVersion({required this.version, required this.build});

  /// The semantic version, e.g. `1.2.1`.
  final String version;

  /// The build number, e.g. `5`.
  final String build;

  /// Human-readable form for UI, e.g. `1.2.1 (5)`.
  String get display => '$version ($build)';

  /// Compact wire form for the `X-App-Version` sync header, e.g. `1.2.1+5` —
  /// mirrors the `pubspec.yaml` `version:` format so the backend can parse it.
  String get wire => '$version+$build';
}

/// Reads the installed [AppVersion] at runtime. Overridable in tests to avoid
/// the platform channel.
final appVersionProvider = FutureProvider<AppVersion>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return AppVersion(version: info.version, build: info.buildNumber);
});
