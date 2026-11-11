import 'package:voice_agent/core/session_control/mic_mode.dart';

/// A command from the G2 glasses' control page in glass-native
/// (ADR-AUDIO-016): the microphone mode the owner picked there.
enum GlassesCommand { listening, standby, off }

/// The way in from glass-native and the way back to it: commands come in,
/// every change of [MicMode] goes out so the glasses show the real mode.
abstract class GlassesControlPort {
  Stream<GlassesCommand> get commands;

  /// Tells glass-native the mode (and records it for its status query).
  Future<void> reportMode(MicMode mode);
}

/// Where there is no glass-native (iOS): no commands, nothing reported.
class NoGlassesControl implements GlassesControlPort {
  const NoGlassesControl();

  @override
  Stream<GlassesCommand> get commands => const Stream.empty();

  @override
  Future<void> reportMode(MicMode mode) async {}
}
