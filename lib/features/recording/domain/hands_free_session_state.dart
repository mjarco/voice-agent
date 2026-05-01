import 'package:voice_agent/features/recording/domain/segment_job.dart';

/// Sub-phase of [HandsFreeListening], mirroring [EngagementState]
/// from the P037 v2 tap-to-engage refactor.
///
/// In the v2 one-shot model the session is either Idle or Listening at
/// the public/UI level. The internal phase is tracked here so the UI can
/// continue rendering distinct status text ("Listening...", "Capturing...",
/// "Processing segment...") without resurrecting the old per-phase
/// session-state classes.
enum HandsFreeListeningPhase {
  /// VAD running, no speech detected.
  listening,

  /// VAD detected start-of-speech; segment accumulating.
  capturing,

  /// Hangover or maxSegmentMs triggered; WAV being written asynchronously.
  stopping,
}

/// Runtime state of a hands-free recording session.
///
/// P037 v2 collapsed the previous fine-grained variants
/// (`HandsFreeListening` / `HandsFreeWithBacklog` / `HandsFreeCapturing`
/// / `HandsFreeStopping` / `HandsFreeSuspendedByUser`) into a single
/// [HandsFreeListening] case carrying a [HandsFreeListeningPhase]
/// indicator and the segment job list. [HandsFreeIdle] and
/// [HandsFreeSessionError] are unchanged.
sealed class HandsFreeSessionState {
  const HandsFreeSessionState();
}

/// Session not running. No jobs.
class HandsFreeIdle extends HandsFreeSessionState {
  const HandsFreeIdle();
}

/// Session is engaged. The [phase] indicates the engine sub-state
/// (listening / capturing / stopping); [jobs] carries the in-flight
/// transcription/persistence backlog.
class HandsFreeListening extends HandsFreeSessionState {
  const HandsFreeListening(
    this.jobs, {
    this.phase = HandsFreeListeningPhase.listening,
  });

  final List<SegmentJob> jobs;
  final HandsFreeListeningPhase phase;
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
