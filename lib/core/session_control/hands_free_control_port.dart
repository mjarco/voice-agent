/// Port interface for controlling the hands-free recording session.
///
/// Lives in `core/` so the [SessionControlDispatcher] depends only on
/// core types, preserving the dependency rule. The adapter is
/// `HandsFreeController` in `features/recording/` (T3).
abstract class HandsFreeControlPort {
  /// Stops the hands-free session: closes the mic, stops the foreground
  /// service, and drains in-flight jobs.
  Future<void> stopSession();

  /// Whether the user has manually suspended the hands-free session
  /// (e.g. tap-to-record or press-and-hold). When true, the dispatcher
  /// skips [stopSession] because the user wins.
  bool get isSuspendedForManualRecording;
}
