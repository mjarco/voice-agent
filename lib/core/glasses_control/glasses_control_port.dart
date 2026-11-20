import 'package:voice_agent/core/session_control/mic_mode.dart';

/// A command from glass-native: the microphone mode the owner picked on
/// the glasses' control page (ADR-AUDIO-016), or a button held and
/// released (`hold`, `release`; ADR-AUDIO-017).
enum GlassesCommand { listening, standby, off, hold, release }

/// The way in from glass-native and the way back to it: commands come in,
/// every change of [MicMode] goes out so the glasses show the real mode.
abstract class GlassesControlPort {
  Stream<GlassesCommand> get commands;

  /// Tells glass-native the mode (and records it for its status query).
  Future<void> reportMode(MicMode mode);

  /// Hands glass-native a document to show (G4, [GlassesDocs]); without
  /// glass-native it reaches no one.
  Future<void> show(Map<String, Object?> doc);
}

/// Where there is no glass-native (iOS): no commands, nothing reported.
class NoGlassesControl implements GlassesControlPort {
  const NoGlassesControl();

  @override
  Stream<GlassesCommand> get commands => const Stream.empty();

  @override
  Future<void> reportMode(MicMode mode) async {}

  @override
  Future<void> show(Map<String, Object?> doc) async {}
}
