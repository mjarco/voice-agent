import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:voice_agent/core/audio/audio_feedback_provider.dart';
import 'package:voice_agent/core/background/background_service_provider.dart';
import 'package:voice_agent/core/config/app_config_provider.dart';
import 'package:voice_agent/core/providers/session_active_provider.dart';
import 'package:voice_agent/core/config/vad_config.dart';
import 'package:voice_agent/core/models/transcript.dart';
import 'package:voice_agent/core/session_control/hands_free_control_port.dart';
import 'package:voice_agent/core/storage/storage_provider.dart';
import 'package:voice_agent/core/tts/tts_provider.dart';
import 'package:voice_agent/features/recording/domain/hands_free_engine.dart';
import 'package:voice_agent/features/recording/domain/hands_free_session_state.dart';
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
    with WidgetsBindingObserver
    implements HandsFreeControlPort {
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

  // ── Manual-recording suspension (T3: full implementation) ────────────────
  // In T2 the stubs allow `ref.listen` in RecordingScreen to compile without
  // producing side-effects. T3 fills in the real logic.

  // ignore: prefer_final_fields — T3 mutates this field
  bool _suspendedForManualRecording = false;
  bool _suspendedForTts = false;
  bool _suspendedByUser = false;

  @override
  bool get isSuspendedForManualRecording => _suspendedForManualRecording;

  /// Interrupts the active VAD segment and releases the microphone so that
  /// manual recording can start. The job backlog is preserved.
  ///
  /// Returns when the microphone has been released and [RecordingController]
  /// may call [startRecording].
  Future<void> suspendForManualRecording() async {
    if (state is HandsFreeCapturing) {
      await _engine?.interruptCapture(); // discards current segment
    } else if (state is HandsFreeListening ||
        state is HandsFreeWithBacklog ||
        state is HandsFreeStopping) {
      // HandsFreeStopping: stop() blocks on _wavWriteCompleter (~100–500ms).
      // The segment is worth keeping — accept the latency.
      await _engineSub?.cancel();
      await _engine?.stop();
    } else {
      // HandsFreeIdle or HandsFreeSessionError — nothing to release.
      return;
    }
    _engineSub = null;
    _engine = null;
    _suspendedForManualRecording = true;
    state = _listeningOrBacklog();
  }

  // ── User-initiated suspension (P034 T2) ─────────────────────────────────

  /// Toggles user-initiated suspension. Called by media button dispatch.
  /// Returns true if the session is now suspended, false if resumed.
  Future<bool> toggleUserSuspend() async {
    if (_suspendedByUser) {
      await resumeByUser();
      return false;
    } else {
      await suspendByUser();
      return true;
    }
  }

  Future<void> suspendByUser() async {
    if (_suspendedByUser) return;
    if (state is HandsFreeIdle || state is HandsFreeSessionError) return;

    // Fast path: engine already stopped by TTS or manual recording.
    if (_suspendedForTts || _suspendedForManualRecording) {
      _suspendedByUser = true;
      state = HandsFreeSuspendedByUser(List<SegmentJob>.unmodifiable(_jobs));
      return;
    }

    if (state is HandsFreeCapturing) {
      await _engine?.interruptCapture();
    } else {
      await _engineSub?.cancel();
      await _engine?.stop();
    }
    _engineSub = null;
    _engine = null;
    _suspendedByUser = true;
    state = HandsFreeSuspendedByUser(List<SegmentJob>.unmodifiable(_jobs));
  }

  Future<void> resumeByUser() async {
    if (!_suspendedByUser) return;
    _suspendedByUser = false;
    if (_suspendedForManualRecording || _suspendedForTts) {
      state = _listeningOrBacklog();
      return;
    }
    _startEngine(_ref.read(appConfigProvider).vadConfig);
    state = _listeningOrBacklog();
  }

  /// Restarts the VAD engine with the current [appConfigProvider] VAD config.
  ///
  /// Called when the user changes VAD parameters in Advanced Settings.
  /// No-op when idle, in error, or suspended for manual recording (the new
  /// config will be picked up automatically by [resumeAfterManualRecording]).
  Future<void> reloadVadConfig() async {
    if (state is HandsFreeIdle || state is HandsFreeSessionError) return;
    if (_suspendedForManualRecording) return;
    if (_suspendedByUser) return;

    if (state is HandsFreeCapturing) {
      await _engine?.interruptCapture();
    } else {
      await _engineSub?.cancel();
      _engineSub = null;
      await _engine?.stop();
    }
    _engine = null;
    _engineSub = null;
    if (!mounted) return;

    _startEngine(_ref.read(appConfigProvider).vadConfig);
    state = _listeningOrBacklog();
  }

  /// Restarts the VAD engine after manual recording completes.
  ///
  /// Does NOT clear [_jobs] or [_jobCounter] — the backlog is preserved.
  Future<void> resumeAfterManualRecording() async {
    if (!_suspendedForManualRecording) return;
    _suspendedForManualRecording = false;
    if (_suspendedByUser) return;
    _startEngine(_ref.read(appConfigProvider).vadConfig);
    state = _listeningOrBacklog();
  }


  // ── TTS suspension ──────────────────────────────────────────────────────

  /// Pauses the VAD engine while TTS is playing to prevent the mic from
  /// picking up speaker output.
  Future<void> suspendForTts() async {
    if (_suspendedForTts || _suspendedForManualRecording) return;
    if (state is HandsFreeIdle || state is HandsFreeSessionError) return;

    if (state is HandsFreeCapturing) {
      await _engine?.interruptCapture();
    } else {
      await _engineSub?.cancel();
      await _engine?.stop();
    }
    _engineSub = null;
    _engine = null;
    _suspendedForTts = true;
    state = _listeningOrBacklog();
  }

  /// Restarts the VAD engine after TTS finishes playing.
  Future<void> resumeAfterTts() async {
    if (!_suspendedForTts) return;
    _suspendedForTts = false;
    if (_suspendedForManualRecording || _suspendedByUser) return;
    _startEngine(_ref.read(appConfigProvider).vadConfig);
    state = _listeningOrBacklog();
  }

  // ── Background lifecycle ─────────────────────────────────────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // No-op: hands-free session continues across background transitions.
    // The foreground service (started explicitly by startSession() and
    // stopped by stopSession() / _terminateWithError()) keeps the process alive.
  }

  // ── Public API ────────────────────────────────────────────────────────────

  Future<void> startSession() async {
    if (state is! HandsFreeIdle && state is! HandsFreeSessionError) return;

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

    // Guard 3 — API URL.
    if (config.apiUrl == null || config.apiUrl!.isEmpty) {
      state = const HandsFreeSessionError(
        message: 'API URL not set.',
        requiresAppSettings: true,
        jobs: [],
      );
      return;
    }

    // All guards passed — mark the session active BEFORE starting the engine
    // so SyncWorker (P027, ADR-NET-002) can drain in the background from the
    // very first tick.
    _ref.read(sessionActiveProvider.notifier).state = true;

    // Start foreground service BEFORE engine so the iOS playAndRecord audio
    // session is set before mic capture begins (ADR-AUDIO-009 +
    // ADR-PLATFORM-006).
    final bg = _ref.read(backgroundServiceProvider);
    await bg.startService();
    unawaited(bg.updateNotification(
      title: 'Voice Agent',
      body: 'Recording session active',
    ));

    _jobs.clear();
    _jobCounter = 0;
    _startEngine(_ref.read(appConfigProvider).vadConfig);
  }

  // ── Helpers — engine lifecycle ────────────────────────────────────────────

  void _startEngine(VadConfig config) {
    final engine = _ref.read(handsFreeEngineProvider);
    _engine = engine;
    final stream = engine.start(config: config);
    _engineSub = stream.listen(
      _onEngineEvent,
      onError: (Object e) => _terminateWithError('Engine error: $e'),
      onDone: _onEngineDone,
      cancelOnError: false,
    );
  }

  @override
  Future<void> stopSession() async {
    if (state is HandsFreeIdle) return;

    // Flip the session-active flag early so SyncWorker stops draining in the
    // background while we tear down (P027, ADR-NET-002).
    _ref.read(sessionActiveProvider.notifier).state = false;

    // Stop foreground service before engine teardown; on iOS this reverts the
    // audio session category from playAndRecord back to ambient before the
    // next (possibly unrelated) capture begins.
    await _ref.read(backgroundServiceProvider).stopService();

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
    _suspendedByUser = false;
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
        unawaited(_ref.read(ttsServiceProvider).stop());
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
    unawaited(_ref.read(audioFeedbackServiceProvider).startProcessingFeedback());
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
      unawaited(_ref.read(audioFeedbackServiceProvider).playError());
      _jobs[idx] = _jobs[idx].copyWith(state: JobFailed('STT error: $e'));
      state = _listeningOrBacklog();
      return;
    }

    // Delete WAV now that transcription is done.
    unawaited(_cleanupWav(wavPath));
    if (!mounted) return;

    if (sttText.trim().isEmpty) {
      unawaited(_ref.read(audioFeedbackServiceProvider).stopLoop());
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
        // Loop continues — sync_worker will play success/error on API response.
        _jobs[idx] = _jobs[idx].copyWith(state: Completed(transcript.id));
      } catch (e) {
        // Rollback: remove the transcript so it doesn't orphan.
        unawaited(storage.deleteTranscript(transcript.id));
        if (!mounted) return;
        unawaited(_ref.read(audioFeedbackServiceProvider).playError());
        _jobs[idx] =
            _jobs[idx].copyWith(state: JobFailed('Enqueue failed: $e'));
      }
    } catch (e) {
      if (!mounted) return;
      unawaited(_ref.read(audioFeedbackServiceProvider).playError());
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
    // Flip the session-active flag so SyncWorker stops background draining
    // immediately (P027, ADR-NET-002).
    _ref.read(sessionActiveProvider.notifier).state = false;
    unawaited(_ref.read(backgroundServiceProvider).stopService());
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
