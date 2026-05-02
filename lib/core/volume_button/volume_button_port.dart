/// Events emitted by hardware volume button presses (iPhone hardware
/// keys, AirPods stem volume swipe, Apple Watch crown).
///
/// Why we route these to engagement: iOS uniformly blocks
/// `MPRemoteCommand` (toggle / next / prev) while the audio session is
/// `.playAndRecord` with an active mic engine. Volume buttons travel a
/// separate path (`AVAudioSession.outputVolume` KVO) that is NOT
/// gated by the same call-mode rule, so the press still reaches the
/// app on a locked screen with a hot mic.
enum VolumeButtonEvent { up, down }

/// Port interface for listening to hardware volume button presses.
///
/// Lives in `core/` so higher layers can depend on it without coupling
/// to platform channel details. The concrete adapter is
/// [VolumeButtonService] backed by platform channels registered in
/// `AppDelegate.swift` via `VolumeButtonBridge`.
abstract class VolumeButtonPort {
  /// Stream of volume up / down events forwarded from the native layer.
  Stream<VolumeButtonEvent> get events;

  /// Starts the native KVO observer on `AVAudioSession.outputVolume`.
  Future<void> activate();

  /// Stops the native KVO observer.
  Future<void> deactivate();
}
