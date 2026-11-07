import 'package:voice_agent/core/session_control/mic_mode.dart';

/// What can ask the microphone to change its [MicMode] (ADR-AUDIO-013).
enum MicModeEvent {
  /// A tap on the mic button while [MicMode.off].
  start,

  /// A headset press, a tap on the mic, or Pause, while listening.
  pause,

  /// A headset press, a tap on the mic, or Resume, while in standby.
  resume,

  /// The Stop button.
  stop,

  /// A farewell phrase ("do widzenia", "dobranoc").
  farewell,

  /// A call or another app taking the audio focus.
  interrupted,

  /// An engine error after the session started.
  error,

  /// The app swiped away from recents.
  taskRemoved,
}

/// The eight transitions of the three-mode model, and nothing else.
///
/// Returns the next mode, or null when [event] is ignored in [from].
MicMode? nextMicMode(MicMode from, MicModeEvent event) {
  return switch ((from, event)) {
    (MicMode.off, MicModeEvent.start) => MicMode.listening,
    (MicMode.listening, MicModeEvent.pause) => MicMode.standby,
    (MicMode.listening, MicModeEvent.interrupted) => MicMode.standby,
    (MicMode.listening, MicModeEvent.error) => MicMode.standby,
    (MicMode.standby, MicModeEvent.resume) => MicMode.listening,
    (MicMode.listening || MicMode.standby, MicModeEvent.stop) => MicMode.off,
    (MicMode.listening, MicModeEvent.farewell) => MicMode.off,
    (MicMode.listening || MicMode.standby, MicModeEvent.taskRemoved) =>
      MicMode.off,
    _ => null,
  };
}
