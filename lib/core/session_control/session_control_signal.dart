/// Immutable value object representing session-control signals from the
/// backend response envelope.
///
/// Parsed from the `session_control` key in the chat reply JSON body.
/// See proposal P029 and personal-agent P049 for the wire contract.
class SessionControlSignal {
  const SessionControlSignal({
    required this.resetSession,
    required this.stopRecording,
  });

  final bool resetSession;
  final bool stopRecording;

  /// True when both booleans are false -- the envelope was present but
  /// carries no actionable signal. The dispatcher returns early on noop.
  bool get isNoop => !resetSession && !stopRecording;

  /// Parses the `session_control` key from a decoded JSON response body.
  ///
  /// Returns `null` when the key is absent or its value is not a `Map`.
  /// Returns a non-null [SessionControlSignal] (possibly with [isNoop]
  /// true) when the envelope is present as a map. Missing boolean keys
  /// inside the map default to `false`. Unknown keys are ignored.
  static SessionControlSignal? fromBody(Map<String, dynamic> body) {
    final raw = body['session_control'];
    if (raw is! Map) return null;
    return SessionControlSignal(
      resetSession: raw['reset_session'] == true,
      stopRecording: raw['stop_recording'] == true,
    );
  }

  @override
  String toString() =>
      'SessionControlSignal(resetSession: $resetSession, stopRecording: $stopRecording)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SessionControlSignal &&
          other.resetSession == resetSession &&
          other.stopRecording == stopRecording;

  @override
  int get hashCode => Object.hash(resetSession, stopRecording);
}
