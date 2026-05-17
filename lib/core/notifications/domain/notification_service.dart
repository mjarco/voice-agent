import 'package:timezone/timezone.dart' as tz;

/// One scheduled OS notification. Equality is structural so the reconciler
/// (ADR-NOTIF-001) can diff value-stably against the in-memory snapshot.
class ScheduledNotification {
  const ScheduledNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.fireAt,
    required this.payload,
  });

  final int id;
  final String title;
  final String body;
  final tz.TZDateTime fireAt;
  final String payload;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ScheduledNotification &&
        other.id == id &&
        other.title == title &&
        other.body == body &&
        other.fireAt.millisecondsSinceEpoch == fireAt.millisecondsSinceEpoch &&
        other.payload == payload;
  }

  @override
  int get hashCode => Object.hash(
        id,
        title,
        body,
        fireAt.millisecondsSinceEpoch,
        payload,
      );

  @override
  String toString() =>
      'ScheduledNotification(id: $id, title: "$title", fireAt: $fireAt)';
}

/// Sole writer to the OS notification queue (ADR-NOTIF-001).
///
/// Foreground: lifetime-scoped singleton via Riverpod.
/// Background isolate: constructed per task spawn via coreBoot (ADR-PLATFORM-007);
/// snapshot is fresh per spawn — first reconcile rewrites the OS queue, which is
/// safe because the plugin's `schedule` replaces an existing entry by ID.
abstract class NotificationService {
  Future<void> init();

  /// Triggers the OS permission prompt on first call. No-op when already
  /// resolved (granted or denied). Returns true iff granted.
  Future<bool> requestPermission();

  Future<bool> isPermitted();

  Future<void> schedule(ScheduledNotification n);

  Future<void> cancel(int id);

  /// Returns the in-memory snapshot of currently scheduled notifications
  /// (NOT the plugin's pendingNotificationRequests — see ADR-NOTIF-001).
  /// Used by the reconciler as the diff source.
  Future<Map<int, ScheduledNotification>> currentlyScheduled();

  Future<void> cancelAll();
}
