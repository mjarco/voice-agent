import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:voice_agent/core/config/app_config_provider.dart';
import 'package:voice_agent/core/models/transcript.dart';
import 'package:voice_agent/core/storage/storage_provider.dart';
import 'package:voice_agent/features/recording/domain/hands_free_engine.dart';
import 'package:voice_agent/features/recording/domain/hands_free_session_state.dart';
import 'package:voice_agent/features/recording/domain/recording_state.dart';
import 'package:voice_agent/features/recording/domain/segment_job.dart';
import 'package:voice_agent/features/recording/presentation/recording_providers.dart';

/// T3a + T3b: session lifecycle and job processing for hands-free mode.
///
/// T3a responsibilities (merged):
///   • session-start guard (permission → Groq key → active-recording check)
///   • [HandsFreeEngineEvent] → [HandsFreeSessionState] mapping
///   • background lifecycle via [WidgetsBindingObserver]
///   • stopSession() with in-flight job drain
///
/// T3b additions:
///   • STT serial slot — jobs processed one at a time
///   • Bounded job queue (max [_maxJobs] non-terminal jobs)
///   • [StorageService.saveTranscript] + [enqueue] with rollback on enqueue failure
///   • WAV cleanup for rejections and session stop
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

  /// Maximum number of non-terminal jobs held at once. Incoming segments
  /// are rejected (WAV deleted) when this limit is reached.
  static const int _maxJobs = 4;

  // ── STT serial slot ───────────────────────────────────────────────────────
  // All segment jobs are chained onto this future so they run sequentially.
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

    final stream = engine.start(config: _ref.read(appConfigProvider).vadConfig);
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

    // Reject all queued (not-yet-started) jobs and clean up their WAV files.
    for (int i = 0; i < _jobs.length; i++) {
      if (_jobs[i].state is QueuedForTranscription) {
        final wavPath = _jobs[i].wavPath;
        _jobs[i] = _jobs[i].copyWith(state: const Rejected('Session stopped'));
        unawaited(_cleanupWav(wavPath));
      }
    }

    // Drain: wait until no job is in Transcribing or Persisting state.
    await _drainInFlightJobs();

    state = const HandsFreeIdle();
    _jobs.clear();
    _jobCounter = 0;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Clean up WAV files for any remaining unprocessed jobs.
    for (final job in _jobs) {
      unawaited(_cleanupWav(job.wavPath));
    }
    unawaited(_engineSub?.cancel());
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

  // ── Segment acceptance ────────────────────────────────────────────────────

  void _onSegmentReady(String wavPath) {
    // Count non-terminal jobs (Queued, Transcribing, Persisting).
    final activeCount = _jobs
        .where((j) =>
            j.state is QueuedForTranscription ||
            j.state is Transcribing ||
            j.state is Persisting)
        .length;

    if (activeCount >= _maxJobs) {
      // Queue is full — drop the incoming segment without creating a job.
      unawaited(_cleanupWav(wavPath));
      return;
    }

    _jobCounter++;
    final now = DateTime.now();
    final label =
        'Segment $_jobCounter — ${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}';

    final jobId = const Uuid().v4();
    final job = SegmentJob(
      id: jobId,
      label: label,
      state: const QueuedForTranscription(),
      wavPath: wavPath,
    );
    _jobs.add(job);
    state = _listeningOrBacklog();

    // Chain onto the STT serial slot so jobs run sequentially.
    _sttSlot = (_sttSlot ?? Future.value())
        .then((_) => _processJob(jobId))
        .catchError((_) {}); // errors handled inside _processJob
  }

  // ── Job processing ────────────────────────────────────────────────────────

  Future<void> _processJob(String jobId) async {
    if (!mounted) return;

    final idx = _jobs.indexWhere((j) => j.id == jobId);
    if (idx == -1) return;

    final job = _jobs[idx];
    if (job.state is! QueuedForTranscription) return; // already rejected

    final wavPath = job.wavPath!;

    // ── Transcribing ──
    _jobs[idx] = job.copyWith(state: const Transcribing());
    if (mounted) state = _listeningOrBacklog();

    String sttText;
    String detectedLanguage;
    int audioDurationMs;

    try {
      final result =
          await _ref.read(sttServiceProvider).transcribe(wavPath);
      sttText = result.text;
      detectedLanguage = result.detectedLanguage;
      audioDurationMs = result.audioDurationMs;
    } catch (e) {
      unawaited(_cleanupWav(wavPath));
      if (!mounted) return;
      _jobs[idx] = _jobs[idx].copyWith(state: JobFailed('STT error: $e'));
      state = _listeningOrBacklog();
      return;
    }

    // Delete WAV now that transcription is done.
    unawaited(_cleanupWav(wavPath));
    if (!mounted) return;

    if (sttText.trim().isEmpty) {
      _jobs[idx] =
          _jobs[idx].copyWith(state: const Rejected('Empty transcription'));
      state = _listeningOrBacklog();
      return;
    }

    // ── Persisting ──
    _jobs[idx] = _jobs[idx].copyWith(state: const Persisting());
    state = _listeningOrBacklog();

    final storage = _ref.read(storageServiceProvider);

    try {
      final deviceId = await storage.getDeviceId();
      if (!mounted) return;

      final transcript = Transcript(
        id: const Uuid().v4(),
        text: sttText.trim(),
        language: detectedLanguage,
        audioDurationMs: audioDurationMs,
        deviceId: deviceId,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );

      await storage.saveTranscript(transcript);
      if (!mounted) return;

      try {
        await storage.enqueue(transcript.id);
        if (!mounted) return;
        _jobs[idx] = _jobs[idx].copyWith(state: Completed(transcript.id));
      } catch (e) {
        // Rollback: remove the transcript so it doesn't orphan.
        unawaited(storage.deleteTranscript(transcript.id));
        if (!mounted) return;
        _jobs[idx] =
            _jobs[idx].copyWith(state: JobFailed('Enqueue failed: $e'));
      }
    } catch (e) {
      if (!mounted) return;
      _jobs[idx] =
          _jobs[idx].copyWith(state: JobFailed('Persist error: $e'));
    }

    if (mounted) state = _listeningOrBacklog();
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

  /// Deletes the WAV temp file at [wavPath]. No-op if null or already deleted.
  Future<void> _cleanupWav(String? wavPath) async {
    if (wavPath == null) return;
    try {
      await File(wavPath).delete();
    } catch (_) {}
  }
}
