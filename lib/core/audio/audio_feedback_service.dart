abstract class AudioFeedbackService {
  /// Plays the start jingle then transitions to the processing loop.
  /// No-op when audio feedback is disabled.
  Future<void> startProcessingFeedback();

  /// Stops the processing loop unconditionally (does not guard on enabled).
  Future<void> stopLoop();

  /// Stops the loop then plays the success jingle (if enabled).
  Future<void> playSuccess();

  /// Stops the loop then plays the error jingle (if enabled).
  Future<void> playError();

  void dispose();
}
