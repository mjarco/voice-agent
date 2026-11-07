/// Target audio session category to apply when [BackgroundService.stopService]
/// tears down the engaged listening state.
///
/// - [playback]: switch to `.playback` (no mic). The app remains the active
///   media participant so AirPods media-button presses are routed to its
///   `MPRemoteCommandCenter` targets. P037 v2 default: required for the
///   tap-to-engage flow because the AirPods short-click must reach the app
///   when it is in the resting (idle) state.
/// - [ambient]: legacy behaviour; switch to `.ambient`. Yields media-button
///   routing to the foreground "now playing" app and stops occupying the
///   audio output unit. Kept for backward compatibility with callers that
///   want the pre-P037 quiet-yield semantics.
enum AudioSessionTarget {
  playback,
  ambient,
}

/// A button of the foreground notification (Android). A press reaches the
/// app as its [id] through the notification actions port
/// (ADR-AUDIO-015).
class ServiceNotificationButton {
  const ServiceNotificationButton({required this.id, required this.text});

  final String id;
  final String text;

  @override
  bool operator ==(Object other) =>
      other is ServiceNotificationButton &&
      other.id == id &&
      other.text == text;

  @override
  int get hashCode => Object.hash(id, text);

  @override
  String toString() => 'ServiceNotificationButton($id, $text)';
}

/// Abstract interface for background service management.
///
/// Manages the platform-specific keepalive mechanism that prevents the OS from
/// killing the app process when backgrounded. On Android this is a foreground
/// service; on iOS it is the audio background mode entitlement combined with
/// an active audio session.
abstract class BackgroundService {
  Future<void> startService();

  /// Stop the foreground service / audio session keepalive.
  ///
  /// [target] selects the post-stop iOS audio session category. Defaults to
  /// [AudioSessionTarget.playback] (P037 v2): the app keeps owning the media
  /// participant slot so AirPods buttons still reach
  /// `MPRemoteCommandCenter`. Pass [AudioSessionTarget.ambient] for the
  /// legacy "fully yield" behaviour.
  Future<void> stopService({
    AudioSessionTarget target = AudioSessionTarget.playback,
  });

  /// Changes the notification of the running service. [buttons] replace
  /// the notification's buttons (Android only; none by default).
  Future<void> updateNotification({
    required String title,
    required String body,
    List<ServiceNotificationButton> buttons = const [],
  });
  bool get isRunning;
}
