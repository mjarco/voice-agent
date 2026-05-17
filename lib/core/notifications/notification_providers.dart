import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:voice_agent/core/notifications/agenda_notification_scheduler.dart';
import 'package:voice_agent/core/notifications/data/local_notification_service.dart';
import 'package:voice_agent/core/notifications/domain/notification_service.dart';

/// **Service providers only** (per ADR-ARCH-008): ephemeral cross-feature
/// state belongs in `core/providers/`. The deep-link / tap-stream providers
/// live in `core/providers/deep_link_providers.dart` and are wired in T3.
///
/// In the foreground, `notificationServiceProvider` is overridden in
/// `app_main.dart` after `coreBoot()` so the widget tree sees the same
/// instance the bootstrap built (P040 §Background Refresh — "Foreground
/// bundle injection"). The fallback constructor below is for tests that
/// don't override; production wiring always overrides.
final notificationServiceProvider = Provider<NotificationService>((ref) {
  throw UnimplementedError(
    'notificationServiceProvider must be overridden in main() '
    'with the instance built by coreBoot(). Tests should override too.',
  );
});

/// Provides the pure reconciler. Reads `notificationServiceProvider` and
/// uses `tz.local` (set during `LocalNotificationService.init()`). Production
/// wiring overrides this with an instance using the production clock; tests
/// inject a fixed clock + location.
final agendaNotificationSchedulerProvider =
    Provider<AgendaNotificationScheduler>((ref) {
  final service = ref.watch(notificationServiceProvider);
  return AgendaNotificationScheduler(
    service: service,
    location: tz.local,
    clock: DateTime.now,
  );
});

/// Exposes the tap stream of [LocalNotificationService] as a typed
/// `Stream<String>`. Consumers in T3 will read this via
/// `notificationTapStreamProvider` placed in `core/providers/` (per
/// ADR-ARCH-008 — ephemeral cross-feature state lives in `core/providers/`).
/// This provider is internal plumbing exposed for that wiring step only.
final localNotificationTapStreamProvider = Provider<Stream<String>>((ref) {
  final service = ref.watch(notificationServiceProvider);
  if (service is LocalNotificationService) {
    return service.tapStream;
  }
  // Tests with FakeNotificationService get an empty stream.
  return const Stream<String>.empty();
});
