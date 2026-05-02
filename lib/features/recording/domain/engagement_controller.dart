import 'dart:async';

import 'package:voice_agent/features/recording/domain/engagement_state.dart';

/// State machine for the hands-free engagement lifecycle.
///
/// Owns:
///   • the [EngagementState] (`Idle / Listening / Capturing / Error`),
///   • notifications to interested observers via [stream].
///
/// Lives in `features/recording/domain/` because it is a state machine
/// over the recording lifecycle and depends only on Dart core types
/// (no platform packages, no Riverpod).
///
/// The audio-session bridging that flips between `.playback` and
/// `.playAndRecord` is performed by the owning controller in
/// presentation/, which calls into `BackgroundService` from `core/`.
/// Keeping that bridge outside the state machine preserves the layering
/// rule (domain depends on no platform code) and lets the controller
/// orchestrate side effects synchronously around state transitions.
///
/// **P038 update (2026-05-02):** the original P037 v2 30 s
/// auto-disengage timer was removed. With the always-on capture +
/// volume-button engagement model the user has explicit hardware
/// control over the capture gate (Volume Up to engage, Volume Down to
/// suspend / interrupt TTS), so the auto-disengage safety net is
/// redundant and was producing surprising "session quietly closed"
/// behaviour. Engage / disengage are now driven exclusively by user
/// gesture, segment-ready (per-segment one-shot), or error.
class EngagementController {
  EngagementController();

  final _controller = StreamController<EngagementState>.broadcast();

  EngagementState _state = const EngagementIdle();
  bool _disposed = false;

  /// Current engagement state.
  EngagementState get state => _state;

  /// Stream of engagement state changes.
  Stream<EngagementState> get stream => _controller.stream;

  /// Open an engagement: any non-error → Listening. Idempotent when
  /// already engaged.
  void engage() {
    _ensureNotDisposed();
    if (_state is EngagementListening) return;
    _setState(const EngagementListening());
  }

  /// Close the current engagement: any non-Idle → Idle. Idempotent
  /// when already idle.
  void disengage() {
    _ensureNotDisposed();
    if (_state is EngagementIdle) return;
    _setState(const EngagementIdle());
  }

  /// Mark an unrecoverable engagement-layer error.
  void markError(String message) {
    _ensureNotDisposed();
    _setState(EngagementError(message));
  }

  /// Release stream resources. Safe to call multiple times.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _controller.close();
  }

  // ── internals ────────────────────────────────────────────────────────

  void _setState(EngagementState next) {
    _state = next;
    if (!_controller.isClosed) {
      _controller.add(next);
    }
  }

  void _ensureNotDisposed() {
    assert(!_disposed, 'EngagementController used after dispose()');
  }
}
