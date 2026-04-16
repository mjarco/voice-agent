/// What triggered a hands-free recording session.
enum ActivationEvent {
  /// A wake word was detected by Porcupine.
  wakeWordDetected,

  /// The user tapped the Quick Settings tile or Control Center control.
  shortcutActivated,
}
