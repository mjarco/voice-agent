import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/core/config/app_config.dart';
import 'package:voice_agent/core/config/app_config_provider.dart';
import 'package:voice_agent/core/providers/api_client_provider.dart';
import 'package:voice_agent/features/location_log/presentation/location_log_providers.dart';

/// At each app start and each settings change: hands the native pipeline the
/// URL and token, which it cannot read itself, and has it take the subscription
/// out again. A failure here must never reach the rest of the app.
final locationLogSyncProvider = Provider<void>((ref) {
  if (!ref.watch(locationLogAvailableProvider)) return;
  final port = ref.watch(locationLogPortProvider);

  Future<void> push(AppConfig config) async {
    try {
      await port.setCredentials(
        apiUrl: deriveBaseUrl(config.apiUrl),
        token: config.apiToken,
      );
    } catch (_) {
      // The Settings screen shows the send error this would cause.
    }
  }

  ref.listen<AppConfig>(appConfigProvider, (previous, next) {
    if (previous?.apiUrl != next.apiUrl ||
        previous?.apiToken != next.apiToken) {
      push(next);
    }
  });

  () async {
    await ref.read(appConfigProvider.notifier).loadCompleted;
    await push(ref.read(appConfigProvider));
    try {
      await port.reconcile();
    } catch (_) {
      // The next app start, reboot or Settings change tries again.
    }
  }();
});

/// On each return to the app, lets the native side see whether the location
/// permission changed, as when "always" was granted on the system's settings
/// page, and register the geofences again (ADR-PLATFORM-010), and pull the
/// triggers if due (ADR-NET-007). A failure here must never reach the rest of
/// the app.
final locationLogResumeProvider = Provider<void>((ref) {
  if (!ref.watch(locationLogAvailableProvider)) return;
  final port = ref.watch(locationLogPortProvider);
  final lifecycle = AppLifecycleListener(
    onResume: () async {
      try {
        await port.appResumed();
      } catch (_) {
        // The next start, or the hourly pull, catches up anyway.
      }
    },
  );
  ref.onDispose(lifecycle.dispose);
});
