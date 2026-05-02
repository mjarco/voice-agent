/// Runtime state of the engagement machine.
///
/// The engagement machine is the high-level "is the user actively
/// engaged in a hands-free turn?" model that drives capture-gate
/// transitions in the always-on capture model (P038).
///
/// Layered above this, [HandsFreeSessionState] still carries the
/// segment job list so the UI can render in-flight
/// transcription/persistence work.
///
/// **History:**
/// - P037 v2 added a third [EngagementCapturing] variant and a 30 s
///   auto-disengage timer that ran while [EngagementListening].
/// - P038 (2026-05-02) collapsed the model back to two active variants
///   (Idle / Listening) and removed the timer. Engagement is now
///   driven exclusively by user gesture (volume buttons), per-segment
///   one-shot disengage, and explicit error.
sealed class EngagementState {
  const EngagementState();
}

/// Resting state. Capture gate is closed; the recorder may still be
/// running with chunks discarded (always-on capture model from P038).
class EngagementIdle extends EngagementState {
  const EngagementIdle();
}

/// Engagement opened. Capture gate is open; VAD is processing audio
/// chunks. Transitions back to [EngagementIdle] on `disengage()`.
class EngagementListening extends EngagementState {
  const EngagementListening();
}

/// Unrecoverable engagement error. Mirrors [HandsFreeSessionError] at
/// the engagement layer. The owning [HandsFreeController] surfaces the
/// detailed error message via [HandsFreeSessionError]; this variant is
/// only used to gate transitions inside [EngagementController].
class EngagementError extends EngagementState {
  const EngagementError(this.message);

  final String message;
}
