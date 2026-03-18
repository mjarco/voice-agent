import 'package:voice_agent/features/recording/domain/recording_result.dart';

abstract class RecordingService {
  Future<void> start({required String outputPath});
  Future<RecordingResult> stop();
  Future<void> cancel();

  /// Broadcast stream that emits every ~200ms while recording.
  /// Completes on stop/cancel/error.
  Stream<Duration> get elapsed;

  bool get isRecording;
}
