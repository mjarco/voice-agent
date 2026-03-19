import 'dart:typed_data';

/// Classifies a fixed-size PCM-16 LE frame as speech or non-speech.
///
/// Implementations wrap a native VAD library. The interface is kept synchronous
/// because VAD inference on a 10–30 ms frame must not block the audio stream.
///
/// Lifecycle: call [init] once before [classify], call [dispose] when the
/// session ends to release native resources.
abstract interface class VadService {
  /// Initialise the underlying VAD model/engine.
  ///
  /// Must be called before [classify]. May be called again after [dispose]
  /// to reinitialise. Throws [VadException] if initialisation fails.
  Future<void> init();

  /// Classify a single PCM frame.
  ///
  /// [pcmFrame] must be exactly [frameSize] bytes of 16-bit LE mono PCM at
  /// 16 kHz. Returns [VadLabel.speech] or [VadLabel.nonSpeech].
  ///
  /// Throws [VadException] if called before [init] or after [dispose].
  VadLabel classify(Uint8List pcmFrame);

  /// The number of bytes the native VAD expects per [classify] call.
  ///
  /// Typically 320 bytes (160 samples × 2 bytes = 10 ms at 16 kHz), but
  /// the concrete implementation determines this value.
  ///
  /// The orchestrator must maintain a remainder buffer and emit only complete
  /// frames to [classify]. Any bytes left over after extracting whole frames
  /// are held in the remainder buffer until the next chunk arrives. Partial
  /// frames must never be zero-padded — padding distorts PCM signal and
  /// produces incorrect VAD labels.
  int get frameSize;

  /// Release native resources. After [dispose], [classify] must not be called.
  void dispose();
}

enum VadLabel { speech, nonSpeech }

class VadException implements Exception {
  const VadException(this.message);

  final String message;

  @override
  String toString() => 'VadException: $message';
}
