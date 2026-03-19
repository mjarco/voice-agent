import 'package:voice_agent/core/config/vad_config.dart';

/// Phase events emitted by [HandsFreeEngine] in real time.
///
/// The controller subscribes to [HandsFreeEngine.start] and maps these events
/// to [HandsFreeSessionState] updates.
sealed class HandsFreeEngineEvent {
  const HandsFreeEngineEvent();
}

/// Engine has started listening; no speech detected.
class EngineListening extends HandsFreeEngineEvent {
  const EngineListening();
}

/// Speech detected; segment is accumulating.
class EngineCapturing extends HandsFreeEngineEvent {
  const EngineCapturing();
}

/// Hangover or maxSegmentMs triggered; WAV being written asynchronously.
class EngineStopping extends HandsFreeEngineEvent {
  const EngineStopping();
}

/// WAV write complete; segment ready for transcription.
class EngineSegmentReady extends HandsFreeEngineEvent {
  const EngineSegmentReady(this.wavPath);

  final String wavPath;
}

/// Unrecoverable pipeline error (permission denied, VAD crash, backgrounded).
///
/// [requiresSettings] is true only for mic permission-denied events.
/// API-key errors are NOT emitted via EngineError — they are caught in
/// HandsFreeController.startSession() before engine.start() is called.
class EngineError extends HandsFreeEngineEvent {
  const EngineError(this.message, {this.requiresSettings = false});

  final String message;

  /// True when the error is a microphone permission denial.
  /// The UI should show "Open Settings" (openAppSettings()) in this case.
  final bool requiresSettings;
}

/// Domain-layer port for the hands-free audio pipeline.
///
/// The implementation ([HandsFreeOrchestrator]) lives in data/.
/// The controller in presentation/ depends only on this interface.
abstract interface class HandsFreeEngine {
  /// Check whether the app has microphone permission.
  Future<bool> hasPermission();

  /// Start the audio stream and VAD pipeline.
  ///
  /// Returns a stream of [HandsFreeEngineEvent]s that the controller maps to
  /// [HandsFreeSessionState] updates. The stream is closed when [stop]
  /// completes.
  Stream<HandsFreeEngineEvent> start({required VadConfig config});

  /// Stop the audio stream, release VAD resources, and flush the pre-roll
  /// buffer. Ongoing WAV writes are awaited before the stream closes.
  ///
  /// Safe to call before [start] returns (e.g., if a permission prompt is
  /// in progress). Idempotent — calling [stop] on an already-stopped engine
  /// is a no-op.
  Future<void> stop();

  /// Immediately stop the engine without waiting for any in-flight WAV write
  /// to complete. Discards the current audio segment. Closes the event stream.
  ///
  /// Use when the microphone must be released quickly (e.g. before starting
  /// a manual recording). The partial WAV file (if any) is deleted by the
  /// orchestrator once the background write finishes.
  ///
  /// After [interruptCapture] the engine is in stopped state; [start] may be
  /// called again on the same instance.
  Future<void> interruptCapture();

  /// Release all resources. Must be called when the owning controller is
  /// disposed. Safe to call after [stop].
  void dispose();
}
