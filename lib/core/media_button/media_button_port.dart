/// Events emitted by a media button source (e.g. AirPods play/pause).
enum MediaButtonEvent { togglePlayPause }

/// Port interface for listening to hardware media-button presses.
///
/// Lives in `core/` so higher layers can depend on it without coupling
/// to platform channel details. The concrete adapter is
/// [MediaButtonService] backed by platform channels registered in
/// `AppDelegate.swift` (iOS) and `MainActivity.kt` (Android).
abstract class MediaButtonPort {
  /// Stream of media button events forwarded from the native layer.
  Stream<MediaButtonEvent> get events;

  /// Registers the app as the active media-button receiver on the
  /// platform (e.g. enables `MPRemoteCommandCenter` on iOS, activates
  /// `MediaSessionCompat` on Android).
  Future<void> activate();

  /// Unregisters the app as the active media-button receiver and
  /// releases platform resources.
  Future<void> deactivate();
}
