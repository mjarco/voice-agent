import 'dart:typed_data';

import 'package:voice_agent/core/config/vad_config.dart';

/// Classifies a fixed-size PCM-16 LE frame as speech or non-speech.
///
/// Implementations wrap a native VAD library (Silero VAD via ONNX Runtime FFI).
///
/// Lifecycle: call [init] once before [classify], call [dispose] when the
/// session ends to release native resources.
abstract interface class VadService {
  /// Initialise the underlying VAD model/engine.
  ///
  /// Must be called before [classify]. May be called again after [dispose]
  /// to reinitialise. Throws [VadException] if initialisation fails.
  Future<void> init(VadConfig config);

  /// Classify a single PCM frame.
  ///
  /// [pcmFrame] must be exactly [frameSize] bytes of 16-bit LE mono PCM at
  /// 16 kHz. Returns [VadLabel.speech] or [VadLabel.nonSpeech].
  ///
  /// The call is async because the underlying ONNX Runtime inference crosses
  /// the FFI boundary asynchronously. Each 32 ms frame completes well within
  /// the next frame window on any supported device.
  ///
  /// Throws [VadException] if called before [init] or after [dispose].
  Future<VadLabel> classify(Uint8List pcmFrame);

  /// The number of bytes the native VAD expects per [classify] call.
  ///
  /// For Silero VAD v5 this is 1024 bytes (512 samples × 2 bytes = 32 ms at
  /// 16 kHz). The concrete implementation determines this value.
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
