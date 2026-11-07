/// How the audio focus was lost (Android's `AUDIOFOCUS_LOSS*`).
enum AudioFocusLoss {
  /// Another app plays for good: a video, music (`AUDIOFOCUS_LOSS`).
  permanent,

  /// A short interruption: a call, an assistant
  /// (`AUDIOFOCUS_LOSS_TRANSIENT`).
  transient,

  /// A short sound that may play over us: a notification chime, a
  /// navigation prompt (`AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK`).
  mayDuck,
}

/// The app's own transient audio focus, held while the microphone listens
/// (ADR-AUDIO-014). Lives in `core/` so features depend on it without the
/// platform channel; the adapter is [AudioFocusService], backed by
/// `AudioFocusBridge.kt` on Android.
abstract class AudioFocusPort {
  /// Asks for a transient focus (`AUDIOFOCUS_GAIN_TRANSIENT`). Returns
  /// false when the system refuses it, as it does during a call.
  Future<bool> request();

  /// Gives the focus back, so the sound of other apps resumes.
  Future<void> abandon();

  /// Losses of the focus while it is held.
  Stream<AudioFocusLoss> get losses;
}

/// The focus on a platform without one of ours (iOS): always granted, never
/// lost.
class NoAudioFocus implements AudioFocusPort {
  const NoAudioFocus();

  @override
  Future<bool> request() async => true;

  @override
  Future<void> abandon() async {}

  @override
  Stream<AudioFocusLoss> get losses => const Stream.empty();
}
