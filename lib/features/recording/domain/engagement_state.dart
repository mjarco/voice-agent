/// Runtime state of the tap-to-engage listening machine introduced by
/// P037 v2 (Candidate B). The engagement machine is the high-level
/// "are we currently capturing speech for one turn or not?" model that
/// drives audio-session category transitions and the 30 s auto-disengage
/// timer.
///
/// Layered above this, [HandsFreeSessionState] still carries the segment
/// job list so the UI can render in-flight transcription/persistence work.
sealed class EngagementState {
  const EngagementState();
}

/// Resting state. Audio session is `.playback`; mic is not engaged. The
/// app remains the active media participant so AirPods short-click is
/// routed via `MPRemoteCommandCenter`.
class EngagementIdle extends EngagementState {
  const EngagementIdle();
}

/// Engagement opened. Audio session is `.playAndRecord`, VAD is running,
/// the 30 s auto-disengage timer is active. Transitions to
/// [EngagementCapturing] on VAD start-of-speech (which cancels the timer)
/// or back to [EngagementIdle] on `disengage()` / `tickTimeout()`.
class EngagementListening extends EngagementState {
  const EngagementListening();
}

/// VAD detected start-of-speech and is accumulating an utterance. The
/// 30 s timer was cancelled at start-of-speech. Transitions back to
/// [EngagementIdle] on `disengage()` (typically called when the engine
/// reports the segment is ready and the controller decides to close the
/// turn).
class EngagementCapturing extends EngagementState {
  const EngagementCapturing();
}

/// Unrecoverable engagement error. Mirrors [HandsFreeSessionError] at the
/// engagement layer. The owning [HandsFreeController] surfaces the
/// detailed error message via [HandsFreeSessionError]; this variant is
/// only used to gate transitions inside [EngagementController].
class EngagementError extends EngagementState {
  const EngagementError(this.message);

  final String message;
}
