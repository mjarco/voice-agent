import 'package:voice_agent/features/recording/domain/recording_result.dart';

sealed class RecordingState {
  const RecordingState();

  const factory RecordingState.idle() = RecordingIdle;
  const factory RecordingState.recording() = RecordingActive;
  const factory RecordingState.completed(RecordingResult result) =
      RecordingCompleted;
  const factory RecordingState.error(String message) = RecordingError;
}

class RecordingIdle extends RecordingState {
  const RecordingIdle();
}

class RecordingActive extends RecordingState {
  const RecordingActive();
}

class RecordingCompleted extends RecordingState {
  const RecordingCompleted(this.result);
  final RecordingResult result;
}

class RecordingError extends RecordingState {
  const RecordingError(this.message);
  final String message;
}
