/// Tunable VAD parameters persisted in SharedPreferences.
///
/// Values are applied at [HandsFreeEngine.start()] time and are immutable
/// for the duration of a session. Changes take effect on the next session.
class VadConfig {
  const VadConfig({
    required this.positiveSpeechThreshold,
    required this.negativeSpeechThreshold,
    required this.hangoverMs,
    required this.minSpeechMs,
    required this.preRollMs,
  });

  /// Default values matching the VAD pipeline's original hardcoded constants.
  const VadConfig.defaults()
      : positiveSpeechThreshold = 0.40,
        negativeSpeechThreshold = 0.35,
        hangoverMs = 500,
        minSpeechMs = 400,
        preRollMs = 300;

  /// Probability above which a frame is considered speech. Range [0.1, 0.9].
  final double positiveSpeechThreshold;

  /// Probability below which a frame is considered non-speech. Range [0.1, 0.8].
  final double negativeSpeechThreshold;

  /// Milliseconds of non-speech to wait before ending a segment. Range [100, 2000].
  final int hangoverMs;

  /// Minimum milliseconds of speech required for a valid segment. Range [100, 1000].
  final int minSpeechMs;

  /// Milliseconds of audio to include before detected speech onset. Range [100, 800].
  final int preRollMs;

  /// Returns a copy with any provided fields replaced.
  VadConfig copyWith({
    double? positiveSpeechThreshold,
    double? negativeSpeechThreshold,
    int? hangoverMs,
    int? minSpeechMs,
    int? preRollMs,
  }) {
    return VadConfig(
      positiveSpeechThreshold:
          positiveSpeechThreshold ?? this.positiveSpeechThreshold,
      negativeSpeechThreshold:
          negativeSpeechThreshold ?? this.negativeSpeechThreshold,
      hangoverMs: hangoverMs ?? this.hangoverMs,
      minSpeechMs: minSpeechMs ?? this.minSpeechMs,
      preRollMs: preRollMs ?? this.preRollMs,
    );
  }

  /// Returns a copy with all fields clamped to their valid ranges.
  ///
  /// Called by [AppConfigService.load()] to silently correct out-of-range
  /// SharedPreferences values rather than passing them raw to the VAD pipeline.
  VadConfig clamp() {
    return VadConfig(
      positiveSpeechThreshold:
          positiveSpeechThreshold.clamp(0.1, 0.9),
      negativeSpeechThreshold:
          negativeSpeechThreshold.clamp(0.1, 0.8),
      hangoverMs: hangoverMs.clamp(100, 2000),
      minSpeechMs: minSpeechMs.clamp(100, 1000),
      preRollMs: preRollMs.clamp(100, 800),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is VadConfig &&
        other.positiveSpeechThreshold == positiveSpeechThreshold &&
        other.negativeSpeechThreshold == negativeSpeechThreshold &&
        other.hangoverMs == hangoverMs &&
        other.minSpeechMs == minSpeechMs &&
        other.preRollMs == preRollMs;
  }

  @override
  int get hashCode => Object.hash(
        positiveSpeechThreshold,
        negativeSpeechThreshold,
        hangoverMs,
        minSpeechMs,
        preRollMs,
      );

  @override
  String toString() => 'VadConfig('
      'pos=$positiveSpeechThreshold, '
      'neg=$negativeSpeechThreshold, '
      'hang=${hangoverMs}ms, '
      'min=${minSpeechMs}ms, '
      'pre=${preRollMs}ms)';
}
