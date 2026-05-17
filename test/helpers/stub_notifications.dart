import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:voice_agent/core/notifications/agenda_notification_scheduler.dart';
import 'package:voice_agent/core/notifications/domain/notification_service.dart';
import 'package:voice_agent/core/notifications/notification_providers.dart';

/// In-memory stub for tests pumping any widget that transitively depends on
/// `agendaNotifierProvider` (and therefore on the notification chain).
class StubNotificationService implements NotificationService {
  final Map<int, ScheduledNotification> _snapshot = {};

  @override
  Future<void> init() async {}
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<bool> isPermitted() async => true;
  @override
  Future<void> schedule(ScheduledNotification n) async => _snapshot[n.id] = n;
  @override
  Future<void> cancel(int id) async => _snapshot.remove(id);
  @override
  Future<Map<int, ScheduledNotification>> currentlyScheduled() async =>
      Map.unmodifiable(_snapshot);
  @override
  Future<void> cancelAll() async => _snapshot.clear();
}

/// Returns the two notification provider overrides every widget test needs
/// after P040 (agendaNotifierProvider promotion in AppShellScaffold).
/// Call `tz_data.initializeTimeZones()` once in `setUpAll` before using.
List<Override> notificationStubOverrides() {
  final service = StubNotificationService();
  return [
    notificationServiceProvider.overrideWithValue(service),
    agendaNotificationSchedulerProvider.overrideWithValue(
      AgendaNotificationScheduler(
        service: service,
        location: tz.local,
        clock: DateTime.now,
      ),
    ),
  ];
}
