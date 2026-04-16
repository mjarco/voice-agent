/// Abstract interface for background service management.
///
/// Manages the platform-specific keepalive mechanism that prevents the OS from
/// killing the app process when backgrounded. On Android this is a foreground
/// service; on iOS it is the audio background mode entitlement combined with
/// an active audio session.
abstract class BackgroundService {
  Future<void> startService();
  Future<void> stopService();
  Future<void> updateNotification({required String title, required String body});
  bool get isRunning;
}
