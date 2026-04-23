sealed class RecordingState {
  const RecordingState();

  const factory RecordingState.idle() = RecordingIdle;
  const factory RecordingState.recording() = RecordingActive;
  const factory RecordingState.paused() = RecordingPaused;
  const factory RecordingState.transcribing() = RecordingTranscribing;
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

class RecordingPaused extends RecordingState {
  const RecordingPaused();
}

class RecordingTranscribing extends RecordingState {
  const RecordingTranscribing();
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
