import 'dart:async';

import 'package:voice_agent/features/recording/domain/engagement_state.dart';

/// Auto-disengage timeout for the [EngagementController]. Hard-coded per
/// the P037 v2 task list (T6) — exposed via [AppConfig] later.
const Duration kListeningEngagementTimeout = Duration(seconds: 30);

/// State machine for the P037 v2 tap-to-engage listening lifecycle (T3).
///
/// Owns:
///   • the [EngagementState] (`Idle / Listening / Capturing / Error`),
///   • the 30 s auto-disengage timer (T6),
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
class EngagementController {
  EngagementController({Duration? timeout})
      : _timeout = timeout ?? kListeningEngagementTimeout;

  final Duration _timeout;
  final _controller = StreamController<EngagementState>.broadcast();

  EngagementState _state = const EngagementIdle();
  Timer? _timer;
  bool _disposed = false;

  /// Current engagement state.
  EngagementState get state => _state;

  /// Stream of engagement state changes.
  Stream<EngagementState> get stream => _controller.stream;

  /// Open an engagement: Idle → Listening. Starts the auto-disengage
  /// timer. Idempotent when already engaged.
  void engage() {
    _ensureNotDisposed();
    if (_state is EngagementListening || _state is EngagementCapturing) return;
    _cancelTimer();
    _setState(const EngagementListening());
    _timer = Timer(_timeout, tickTimeout);
  }

  /// Mark VAD start-of-speech: Listening → Capturing. Cancels the
  /// auto-disengage timer (the segment will end naturally on VAD
  /// end-of-speech). No-op if not in Listening.
  void markCaptureStarted() {
    _ensureNotDisposed();
    if (_state is! EngagementListening) return;
    _cancelTimer();
    _setState(const EngagementCapturing());
  }

  /// Close the current engagement: any non-Idle → Idle. Cancels the
  /// auto-disengage timer. Idempotent when already idle.
  void disengage() {
    _ensureNotDisposed();
    if (_state is EngagementIdle) return;
    _cancelTimer();
    _setState(const EngagementIdle());
  }

  /// Auto-disengage trigger fired by the 30 s timer. Public so tests
  /// (and future synchronous-fake callers) can drive the transition
  /// without waiting for real time. Equivalent to [disengage] when in
  /// Listening; no-op otherwise.
  void tickTimeout() {
    _ensureNotDisposed();
    if (_state is! EngagementListening) return;
    _cancelTimer();
    _setState(const EngagementIdle());
  }

  /// Mark an unrecoverable engagement-layer error. Cancels the timer.
  void markError(String message) {
    _ensureNotDisposed();
    _cancelTimer();
    _setState(EngagementError(message));
  }

  /// Release timer + stream resources. Safe to call multiple times.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _cancelTimer();
    await _controller.close();
  }

  // ── internals ────────────────────────────────────────────────────────

  void _setState(EngagementState next) {
    _state = next;
    if (!_controller.isClosed) {
      _controller.add(next);
    }
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _ensureNotDisposed() {
    assert(!_disposed, 'EngagementController used after dispose()');
  }
}
