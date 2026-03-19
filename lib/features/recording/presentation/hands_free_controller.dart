import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:voice_agent/core/config/app_config_provider.dart';
import 'package:voice_agent/features/recording/domain/hands_free_engine.dart';
import 'package:voice_agent/features/recording/domain/hands_free_session_state.dart';
import 'package:voice_agent/features/recording/domain/recording_state.dart';
import 'package:voice_agent/features/recording/domain/segment_job.dart';
import 'package:voice_agent/features/recording/presentation/recording_providers.dart';

/// T3a: session lifecycle for hands-free mode.
///
/// Responsibilities in this task:
///   • session-start guard (permission → Groq key → active-recording check)
///   • [HandsFreeEngineEvent] → [HandsFreeSessionState] mapping
///   • background lifecycle via [WidgetsBindingObserver]
///   • stopSession() with in-flight job drain
///
/// T3b adds: STT serial slot, job processing, persist + rollback.
class HandsFreeController extends StateNotifier<HandsFreeSessionState>
    with WidgetsBindingObserver {
  HandsFreeController(this._ref) : super(const HandsFreeIdle()) {
    WidgetsBinding.instance.addObserver(this);
  }

  final Ref _ref;

  HandsFreeEngine? _engine;
  StreamSubscription<HandsFreeEngineEvent>? _engineSub;

  // ── Job list ─────────────────────────────────────────────────────────────
  // Mutable list kept in controller; copied into each emitted state.
  final List<SegmentJob> _jobs = [];
  int _jobCounter = 0;

  // ── STT serial slot (T3b wires this up fully; stub here so T3a compiles) ─
  // ignore: unused_field
  Future<void>? _sttSlot;

  // ── Background lifecycle ─────────────────────────────────────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && this.state is! HandsFreeIdle) {
      _terminateWithError(
        'Interrupted: app backgrounded',
        requiresSettings: false,
      );
    }
  }

  // ── Public API ────────────────────────────────────────────────────────────

  Future<void> startSession() async {
    if (state is! HandsFreeIdle) return;

    final engine = _ref.read(handsFreeEngineProvider);

    // Guard 1 — microphone permission.
    final granted = await engine.hasPermission();
    if (!granted) {
      state = const HandsFreeSessionError(
        message: 'Microphone permission denied.',
        requiresSettings: true,
        jobs: [],
      );
      return;
    }

    // Guard 2 — Groq API key.
    await _ref.read(appConfigProvider.notifier).loadCompleted;
    final config = _ref.read(appConfigProvider);
    if (config.groqApiKey == null || config.groqApiKey!.isEmpty) {
      state = const HandsFreeSessionError(
        message: 'Groq API key not set.',
        requiresAppSettings: true,
        jobs: [],
      );
      return;
    }

    // Guard 3 — active manual recording.
    final recordingState = _ref.read(recordingControllerProvider);
    if (recordingState is RecordingActive) {
      state = const HandsFreeSessionError(
        message: 'Stop the current recording before starting hands-free mode.',
        jobs: [],
      );
      return;
    }

    // All guards passed — start engine.
    _jobs.clear();
    _jobCounter = 0;
    _engine = engine;

    final stream = engine.start();
    _engineSub = stream.listen(
      _onEngineEvent,
      onError: (Object e) => _terminateWithError('Engine error: $e'),
      onDone: _onEngineDone,
      cancelOnError: false,
    );
  }

  Future<void> stopSession() async {
    if (state is HandsFreeIdle) return;

    await _engineSub?.cancel();
    _engineSub = null;
    await _engine?.stop();
    _engine = null;

    // Drain: wait until no job is in Transcribing or Persisting state.
    await _drainInFlightJobs();

    state = const HandsFreeIdle();
    _jobs.clear();
    _jobCounter = 0;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _engineSub?.cancel();
    _engine?.dispose();
    super.dispose();
  }

  // ── Engine event mapping ─────────────────────────────────────────────────

  void _onEngineEvent(HandsFreeEngineEvent event) {
    switch (event) {
      case EngineListening():
        state = _listeningOrBacklog();

      case EngineCapturing():
        state = HandsFreeCapturing(List<SegmentJob>.unmodifiable(_jobs));

      case EngineStopping():
        state = HandsFreeStopping(List<SegmentJob>.unmodifiable(_jobs));

      case EngineSegmentReady(wavPath: final path):
        _onSegmentReady(path);

      case EngineError(
          message: final msg,
          requiresSettings: final rs,
        ):
        _terminateWithError(msg, requiresSettings: rs);
    }
  }

  void _onEngineDone() {
    // Stream closed normally (e.g. stop() was called). No action needed;
    // stopSession() already transitions to HandsFreeIdle.
  }

  // ── Segment acceptance (T3a stub — T3b fills in STT + persist) ───────────

  void _onSegmentReady(String wavPath) {
    _jobCounter++;
    final now = DateTime.now();
    final label =
        'Segment $_jobCounter — ${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}';

    final job = SegmentJob(
      id: const Uuid().v4(),
      label: label,
      state: const QueuedForTranscription(),
      wavPath: wavPath,
    );
    _jobs.add(job);

    // T3b: submit to STT serial slot here.
    // For T3a, job remains in QueuedForTranscription so tests can observe it.
    state = _listeningOrBacklog();
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  /// Returns [HandsFreeListening] or [HandsFreeWithBacklog] based on jobs.
  HandsFreeSessionState _listeningOrBacklog() {
    final active = _jobs.any((j) =>
        j.state is Transcribing ||
        j.state is Persisting ||
        j.state is QueuedForTranscription);
    final jobs = List<SegmentJob>.unmodifiable(_jobs);
    return active ? HandsFreeWithBacklog(jobs) : HandsFreeListening(jobs);
  }

  void _terminateWithError(
    String message, {
    bool requiresSettings = false,
  }) {
    unawaited(_engineSub?.cancel());
    _engineSub = null;
    unawaited(_engine?.stop());
    _engine = null;

    state = HandsFreeSessionError(
      message: message,
      requiresSettings: requiresSettings,
      jobs: List<SegmentJob>.unmodifiable(_jobs),
    );
  }

  /// Polls until no job is in [Transcribing] or [Persisting] state, with a
  /// 10-second safety timeout. Used by [stopSession] to drain in-flight work
  /// before emitting [HandsFreeIdle].
  Future<void> _drainInFlightJobs() async {
    const pollInterval = Duration(milliseconds: 100);
    const timeout = Duration(seconds: 10);
    final deadline = DateTime.now().add(timeout);

    bool hasInFlight() => _jobs.any(
          (j) => j.state is Transcribing || j.state is Persisting,
        );

    while (hasInFlight()) {
      if (DateTime.now().isAfter(deadline)) break;
      await Future.delayed(pollInterval);
    }
  }
}
