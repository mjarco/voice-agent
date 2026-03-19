/// State of a single transcription job within a hands-free session.
sealed class SegmentJobState {
  const SegmentJobState();
}

/// WAV file ready; waiting for the STT serial slot.
class QueuedForTranscription extends SegmentJobState {
  const QueuedForTranscription();
}

/// Active Groq STT request in-flight.
class Transcribing extends SegmentJobState {
  const Transcribing();
}

/// STT result received; writing Transcript + enqueue to storage.
class Persisting extends SegmentJobState {
  const Persisting();
}

/// Transcript saved and enqueued. WAV deleted by SttService.
class Completed extends SegmentJobState {
  const Completed(this.transcriptId);

  final String transcriptId;
}

/// Segment rejected before transcription (too short, empty text, write
/// failure, or queue full). WAV deleted by controller.
class Rejected extends SegmentJobState {
  const Rejected(this.reason);

  final String reason;
}

/// STT or storage error. WAV already deleted by SttService (if transcription
/// was attempted) or by controller (if rejected pre-transcription).
class JobFailed extends SegmentJobState {
  const JobFailed(this.message);

  final String message;
}

/// A single segment job tracked by [HandsFreeController].
class SegmentJob {
  const SegmentJob({
    required this.id,
    required this.label,
    required this.state,
    this.wavPath,
  });

  final String id;

  /// Display label shown in the segment list (e.g. "Segment 1 — 14:03:22").
  final String label;

  final SegmentJobState state;

  /// Path to the WAV temp file. Null once the file has been handed to
  /// SttService or deleted.
  final String? wavPath;

  SegmentJob copyWith({SegmentJobState? state, String? wavPath}) {
    return SegmentJob(
      id: id,
      label: label,
      state: state ?? this.state,
      wavPath: wavPath ?? this.wavPath,
    );
  }
}
