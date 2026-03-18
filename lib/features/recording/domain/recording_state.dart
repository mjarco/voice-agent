import 'package:voice_agent/core/models/transcript_result.dart';

sealed class RecordingState {
  const RecordingState();

  const factory RecordingState.idle() = RecordingIdle;
  const factory RecordingState.recording() = RecordingActive;
  const factory RecordingState.transcribing() = RecordingTranscribing;
  const factory RecordingState.completed(TranscriptResult result) =
      RecordingCompleted;
  const factory RecordingState.error(
    String message, {
    bool requiresSettings,
    bool requiresAppSettings,
  }) = RecordingError;
}

class RecordingIdle extends RecordingState {
  const RecordingIdle();
}

class RecordingActive extends RecordingState {
  const RecordingActive();
}

class RecordingTranscribing extends RecordingState {
  const RecordingTranscribing();
}

class RecordingCompleted extends RecordingState {
  const RecordingCompleted(this.result);
  final TranscriptResult result;
}

class RecordingError extends RecordingState {
  const RecordingError(
    this.message, {
    this.requiresSettings = false,
    this.requiresAppSettings = false,
  }) : assert(
          !(requiresSettings && requiresAppSettings),
          'requiresSettings and requiresAppSettings are mutually exclusive',
        );

  final String message;
  final bool requiresSettings;
  final bool requiresAppSettings;
}
