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

  Future<void> updateNotification({required String title, required String body});
  bool get isRunning;
}
