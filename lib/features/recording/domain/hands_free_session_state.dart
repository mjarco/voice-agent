import 'package:voice_agent/features/recording/domain/segment_job.dart';

/// Runtime state of a hands-free recording session.
///
/// All active variants carry a [jobs] list so the UI can render the segment
/// list without a separate provider. [HandsFreeIdle] carries no jobs because
/// the session is not running.
sealed class HandsFreeSessionState {
  const HandsFreeSessionState();
}

/// Session not running. No jobs.
class HandsFreeIdle extends HandsFreeSessionState {
  const HandsFreeIdle();
}

/// VAD running; no speech detected; no job backlog.
/// Cooldown (if active) is invisible — session stays Listening during cooldown.
class HandsFreeListening extends HandsFreeSessionState {
  const HandsFreeListening(this.jobs);

  final List<SegmentJob> jobs;
}

/// Speech frames accumulating in segment buffer.
class HandsFreeCapturing extends HandsFreeSessionState {
  const HandsFreeCapturing(this.jobs);

  final List<SegmentJob> jobs;
}

/// Hangover or maxSegmentMs triggered; WAV being written asynchronously.
class HandsFreeStopping extends HandsFreeSessionState {
  const HandsFreeStopping(this.jobs);

  final List<SegmentJob> jobs;
}

/// Listening; one or more STT jobs are pending or in-flight.
class HandsFreeWithBacklog extends HandsFreeSessionState {
  const HandsFreeWithBacklog(this.jobs);

  final List<SegmentJob> jobs;
}

/// User-initiated pause via media button. Engine stopped, backlog preserved.
class HandsFreeSuspendedByUser extends HandsFreeSessionState {
  const HandsFreeSuspendedByUser(this.jobs);

  final List<SegmentJob> jobs;
}

/// Unrecoverable error. Microphone released.
///
/// At most one of [requiresSettings] or [requiresAppSettings] may be true.
/// - [requiresSettings]: mic permission denied → UI shows "Open Settings"
/// - [requiresAppSettings]: API key missing → UI shows "Go to Settings"
class HandsFreeSessionError extends HandsFreeSessionState {
  const HandsFreeSessionError({
    required this.message,
    this.requiresSettings = false,
    this.requiresAppSettings = false,
    this.jobs = const [],
  }) : assert(
          !(requiresSettings && requiresAppSettings),
          'At most one of requiresSettings or requiresAppSettings may be true',
        );

  final String message;
  final bool requiresSettings;
  final bool requiresAppSettings;

  /// Jobs at the time of the error, for display in the segment list.
  final List<SegmentJob> jobs;
}
