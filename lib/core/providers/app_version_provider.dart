import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// The installed app version read from the bundle at runtime, formatted as
/// `<version> (<build>)` — e.g. `1.2.0 (4)`. This is sourced from
/// `pubspec.yaml`'s `version:` line (the single source of truth), so the
/// Settings screen always reflects the build that is actually installed.
///
/// Overridable in tests to avoid the platform channel.
final appVersionProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return '${info.version} (${info.buildNumber})';
});
