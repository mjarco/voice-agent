/// A button pressed in the foreground notification (Android,
/// ADR-AUDIO-015). The ids are the buttons' ids in the notification.
enum NotificationAction { pause, resume, stop }

/// Presses on the buttons of the foreground service's notification.
abstract class NotificationActionPort {
  Stream<NotificationAction> get actions;
}

/// Where the notification has no buttons (iOS): nothing is ever pressed.
class NoNotificationActions implements NotificationActionPort {
  const NoNotificationActions();

  @override
  Stream<NotificationAction> get actions => const Stream.empty();
}
