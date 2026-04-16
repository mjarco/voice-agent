/// Built-in keywords available in the Porcupine SDK.
enum BuiltInKeyword {
  jarvis,
  computer,
  alexa,
  americano,
  blueberry,
  bumblebee,
  grapefruit,
  grasshopper,
  picovoice,
  porcupine,
  terminator,
}

/// Typed errors emitted by [WakeWordService.errors].
sealed class WakeWordError {
  const WakeWordError();
}

class InvalidAccessKey extends WakeWordError {
  const InvalidAccessKey();
}

class CorruptModel extends WakeWordError {
  const CorruptModel({required this.path});
  final String path;
}

class AudioCaptureFailed extends WakeWordError {
  const AudioCaptureFailed({required this.reason});
  final String reason;
}

class UnknownWakeWordError extends WakeWordError {
  const UnknownWakeWordError({required this.message});
  final String message;
}

/// Abstract interface for wake word detection.
///
/// Implementations wrap a platform-specific wake word SDK (e.g. Picovoice
/// Porcupine). The interface is placed in `features/activation/domain/` for V1
/// (single consumer). If future features need wake word events, promote to
/// `core/`.
abstract class WakeWordService {
  /// Start listening for built-in keywords.
  Future<void> startBuiltIn({
    required String accessKey,
    required List<BuiltInKeyword> keywords,
    required List<double> sensitivities,
  });

  /// Start listening for custom-trained keyword models (.ppn files).
  Future<void> startCustom({
    required String accessKey,
    required List<String> keywordPaths,
    required List<double> sensitivities,
  });

  /// Stop listening and release audio resources.
  Future<void> stop();

  /// Emits the keyword index when a wake word is detected.
  Stream<int> get detections;

  /// Emits typed errors from the wake word engine.
  Stream<WakeWordError> get errors;

  /// Whether the service is currently listening for wake words.
  bool get isListening;

  /// Release all resources. The service cannot be reused after disposal.
  void dispose();
}
