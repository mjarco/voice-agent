import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:voice_agent/core/audio/audio_feedback_provider.dart';
import 'package:voice_agent/core/background/background_service.dart';
import 'package:voice_agent/core/background/background_service_provider.dart';
import 'package:voice_agent/core/config/app_config_provider.dart';
import 'package:voice_agent/core/providers/session_active_provider.dart';
import 'package:voice_agent/core/config/vad_config.dart';
import 'package:voice_agent/core/models/transcript.dart';
import 'package:voice_agent/core/session_control/hands_free_control_port.dart';
import 'package:voice_agent/core/storage/storage_provider.dart';
import 'package:voice_agent/core/tts/tts_provider.dart';
import 'package:voice_agent/features/recording/domain/engagement_controller.dart';
import 'package:voice_agent/features/recording/domain/engagement_state.dart';
import 'package:voice_agent/features/recording/domain/hands_free_engine.dart';
import 'package:voice_agent/features/recording/domain/hands_free_session_state.dart';
import 'package:voice_agent/features/recording/domain/segment_job.dart';
import 'package:voice_agent/features/recording/presentation/recording_providers.dart';

/// Hands-free session controller (P037 v2 — tap-to-engage refactor, T4).
///
/// Wraps an [EngagementController] (T3) which owns the high-level
/// `Idle / Listening / Capturing / Error` lifecycle and the 30 s
/// auto-disengage timer (T6). This controller still owns:
///   • session-start guard (permission → Groq key → API URL)
///   • engine event mapping → [HandsFreeListeningPhase] sub-state
///   • job queue + serial STT slot + persist+enqueue with rollback
///   • foreground-service lifecycle (audio session category transitions)
///
/// In the v2 one-shot model the publicly exposed states collapse to
/// [HandsFreeIdle] / [HandsFreeListening] / [HandsFreeSessionError].
/// The pre-v2 `WithBacklog`, `Capturing`, `Stopping`, and
/// `SuspendedByUser` distinctions live as fields on
/// [HandsFreeListening.phase] (capturing / stopping) or are simply gone
/// (`SuspendedByUser` was a continuous-listening artefact and disappears
/// in the one-shot model: a "user pause" maps to closing the engagement).
///
/// T7 (UI wiring of AirPods short-click → [engage]) is intentionally out
/// of scope for this PR. The legacy session-start path
/// ([startSession]) preserves the old "auto-start when the screen mounts"
/// behaviour by internally calling [engage] so existing UI keeps working.
class HandsFreeController extends StateNotifier<HandsFreeSessionState>
    with WidgetsBindingObserver
    implements HandsFreeControlPort {
  HandsFreeController(this._ref, {EngagementController? engagement})
      : _engagement = engagement ?? EngagementController(),
        super(const HandsFreeIdle()) {
    WidgetsBinding.instance.addObserver(this);
    // P037 v2 one-shot model: when the engagement layer transitions to
    // Idle externally (e.g. 30 s timer expiry without speech), tear the
    // engine down and reflect it in the public state. The re-entry
    // guard (`state is! HandsFreeIdle`) prevents recursion when
    // [_disengageOneShot] itself drives engagement to Idle.
    _engagementSub = _engagement.stream.listen((_) {
      // Guard against the controller being disposed mid-flight; stream
      // events may still arrive on the same microtask.
      if (!mounted) return;
      // Re-read the current engagement state instead of trusting the
      // emitted event: the event may be stale (e.g. a disengage→engage
      // pair issued synchronously by suspend+resume produces two
      // microtask events; by the time the first runs, engagement is
      // already Listening again and we must not tear the engine down).
      if (_engagement.state is EngagementIdle && state is! HandsFreeIdle) {
        unawaited(_disengageOneShot());
      }
    });
  }

  final Ref _ref;
  final EngagementController _engagement;

  HandsFreeEngine? _engine;
  StreamSubscription<HandsFreeEngineEvent>? _engineSub;
  StreamSubscription<EngagementState>? _engagementSub;

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

  // Tracks the most recent engine sub-phase so [_listeningOrBacklog] can
  // reflect capture/stopping in the collapsed [HandsFreeListening] state.
  HandsFreeListeningPhase _phase = HandsFreeListeningPhase.listening;

  // Manual-recording suspension: the [HandsFreeControlPort] still exposes
  // [isSuspendedForManualRecording] for [SessionControlDispatcher]. In the
  // one-shot v2 model "suspended for manual recording" simply means the
  // engagement was closed; the flag persists across the closure so the
  // dispatcher knows to skip [stopSession].
  bool _suspendedForManualRecording = false;

  // User-initiated suspension (P034 carry-over). In the v2 one-shot model
  // the public state collapses to [HandsFreeIdle] when paused, but we
  // still track *why* it was paused so that auto-resume paths
  // ([resumeAfterTts] / [resumeAfterManualRecording]) honour the user's
  // explicit pause intent and do NOT silently re-engage.
  bool _suspendedByUser = false;

  @override
  bool get isSuspendedForManualRecording => _suspendedForManualRecording;

  /// Engagement-layer state (testability hook). Exposes the underlying
  /// [EngagementController] state without leaking the controller itself.
  EngagementState get engagementState => _engagement.state;

  // ── Public API: legacy compatibility surface ─────────────────────────────

  /// Interrupts the active VAD segment and releases the microphone so that
  /// manual recording can start. The job backlog is preserved.
  ///
  /// In the v2 one-shot model this collapses to "close the engagement and
  /// remember that we're in manual-recording mode so [resumeAfter*] knows
  /// to re-engage". Mid-capture, the in-flight segment is discarded via
  /// [HandsFreeEngine.interruptCapture] so the mic releases promptly.
  Future<void> suspendForManualRecording() async {
    if (state is HandsFreeIdle || state is HandsFreeSessionError) {
      return;
    }
    if (state is HandsFreeListening &&
        (state as HandsFreeListening).phase ==
            HandsFreeListeningPhase.capturing) {
      await _engine?.interruptCapture();
    } else {
      await _engineSub?.cancel();
      await _engine?.stop();
    }
    _engineSub = null;
    _engine = null;
    _engagement.disengage();
    _suspendedForManualRecording = true;
    state = HandsFreeIdle(jobs: List.unmodifiable(_jobs));
  }

  /// Toggles user-initiated suspension. Called by media button dispatch.
  /// Returns true if the session is now suspended, false if resumed.
  ///
  /// In v2 this maps to engage/disengage on the underlying engagement.
  Future<bool> toggleUserSuspend() async {
    if (_suspendedByUser) {
      await resumeByUser();
      return false;
    }
    await suspendByUser();
    return true;
  }

  Future<void> suspendByUser() async {
    if (_suspendedByUser) return;

    // Fast path: engine already idle from TTS or manual-recording suspend
    // — just flip the flag so resume*() honours the user's pause intent.
    if (state is HandsFreeIdle &&
        (_suspendedForTts || _suspendedForManualRecording)) {
      _suspendedByUser = true;
      return;
    }

    if (state is HandsFreeIdle || state is HandsFreeSessionError) return;
    _suspendedByUser = true;
    await _closeEngagement(toAmbientFor: AudioSessionTarget.playback);
    state = HandsFreeIdle(jobs: List.unmodifiable(_jobs));
  }

  Future<void> resumeByUser() async {
    if (!_suspendedByUser) return;
    _suspendedByUser = false;
    if (_suspendedForManualRecording) return;
    if (_suspendedForTts) return;
    _resumeEngagement();
  }

  /// Restarts the VAD engine with the current [appConfigProvider] VAD config.
  ///
  /// Called when the user changes VAD parameters in Advanced Settings.
  Future<void> reloadVadConfig() async {
    if (state is HandsFreeIdle || state is HandsFreeSessionError) return;
    if (_suspendedForManualRecording) return;
    if (_suspendedByUser) return;

    await _engineSub?.cancel();
    _engineSub = null;
    await _engine?.stop();
    _engine = null;
    if (!mounted) return;

    _startEngine(_ref.read(appConfigProvider).vadConfig);
    _phase = HandsFreeListeningPhase.listening;
    state = _listeningOrBacklog();
  }

  /// Restarts the VAD engine after manual recording completes.
  Future<void> resumeAfterManualRecording() async {
    if (!_suspendedForManualRecording) return;
    _suspendedForManualRecording = false;
    if (_suspendedByUser) return;
    _resumeEngagement();
  }

  // Tracks whether the most recent engagement closure was due to a TTS
  // suspend; only that path should auto-resume when TTS ends.
  bool _suspendedForTts = false;

  /// Pauses the VAD engine while TTS is playing to prevent the mic from
  /// picking up speaker output. In the v2 one-shot model this collapses
  /// to closing the engagement; [resumeAfterTts] re-engages.
  Future<void> suspendForTts() async {
    if (_suspendedForTts) return;
    if (_suspendedForManualRecording) return;
    if (state is HandsFreeIdle || state is HandsFreeSessionError) return;
    _suspendedForTts = true;
    await _closeEngagement(toAmbientFor: AudioSessionTarget.playback);
    state = HandsFreeIdle(jobs: List.unmodifiable(_jobs));
  }

  /// Re-engages after TTS finishes playing.
  Future<void> resumeAfterTts() async {
    if (!_suspendedForTts) return;
    _suspendedForTts = false;
    if (_suspendedForManualRecording) return;
    if (_suspendedByUser) return;
    _resumeEngagement();
  }

  /// Re-opens an engagement after a soft-suspend (TTS / manual recording /
  /// user pause). Skips the [startSession] start-up guards because they
  /// were already validated on the first start; the session is just being
  /// re-engaged. Mirrors the pre-v2 inline `_startEngine` + state assign.
  void _resumeEngagement() {
    if (state is! HandsFreeIdle) return;
    _engagement.engage();
    _phase = HandsFreeListeningPhase.listening;
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

  // ── Public API: lifecycle ─────────────────────────────────────────────────

  /// Open an engagement: run the start-up guards, flip the audio session
  /// to `.playAndRecord` and start the VAD engine. Invoked by the
  /// existing UI auto-start path; T7 will later wire AirPods short-click
  /// here directly.
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

    if (_jobs.isEmpty) {
      _jobCounter = 0;
    }
    _phase = HandsFreeListeningPhase.listening;
    _engagement.engage();
    _startEngine(_ref.read(appConfigProvider).vadConfig);
    // State is left as-is — the controller transitions into a concrete
    // [HandsFreeListening] (with the right phase) when the first engine
    // event arrives. This matches the pre-v2 contract and keeps the
    // session-start side effects behaviour-equivalent.
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

    // P037 v2: stopService now defaults to AudioSessionTarget.playback so
    // the app keeps the media-participant slot and AirPods buttons remain
    // routed to its MPRemoteCommandCenter targets. The legacy ambient
    // behaviour is still available via the new parameter for callers that
    // want to fully yield.
    await _ref.read(backgroundServiceProvider).stopService();

    _engagement.disengage();

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
    _suspendedForManualRecording = false;
    _suspendedByUser = false;
    _suspendedForTts = false;
    _phase = HandsFreeListeningPhase.listening;
  }

  /// Tear down the engine + audio session without draining the job queue
  /// or clearing the [_suspendedForManualRecording] flag. Used by the
  /// "soft pause" paths ([suspendForTts], [suspendForManualRecording],
  /// [suspendByUser]) where we want to come back to listening shortly.
  /// P037 v2 one-shot: close the engagement after a captured utterance
  /// or a 30 s silence timeout. Stops the engine, switches the audio
  /// session back to .playback (so AirPods buttons keep routing), and
  /// transitions to [HandsFreeIdle] preserving the in-flight job
  /// queue. Does NOT drain jobs — STT and persistence continue
  /// asynchronously via [_sttSlot].
  Future<void> _disengageOneShot() async {
    if (!mounted) return;
    if (state is HandsFreeIdle || state is HandsFreeSessionError) return;
    _ref.read(sessionActiveProvider.notifier).state = false;
    await _ref
        .read(backgroundServiceProvider)
        .stopService(target: AudioSessionTarget.playback);
    if (!mounted) return;
    _engagement.disengage();
    await _engineSub?.cancel();
    _engineSub = null;
    await _engine?.stop();
    _engine = null;
    if (!mounted) return;
    _phase = HandsFreeListeningPhase.listening;
    state = HandsFreeIdle(jobs: List.unmodifiable(_jobs));
  }

  Future<void> _closeEngagement({
    required AudioSessionTarget toAmbientFor,
  }) async {
    _ref.read(sessionActiveProvider.notifier).state = false;
    await _ref
        .read(backgroundServiceProvider)
        .stopService(target: toAmbientFor);
    _engagement.disengage();
    await _engineSub?.cancel();
    _engineSub = null;
    await _engine?.stop();
    _engine = null;
    _phase = HandsFreeListeningPhase.listening;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_engagementSub?.cancel());
    unawaited(_engagement.dispose());
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
        _phase = HandsFreeListeningPhase.listening;
        state = _listeningOrBacklog();

      case EngineCapturing():
        unawaited(_ref.read(ttsServiceProvider).stop());
        _phase = HandsFreeListeningPhase.capturing;
        // Inform the engagement layer so the 30 s timer is cancelled.
        _engagement.markCaptureStarted();
        state = _listeningOrBacklog();

      case EngineStopping():
        _phase = HandsFreeListeningPhase.stopping;
        state = _listeningOrBacklog();

      case EngineSegmentReady(wavPath: final path):
        _onSegmentReady(path);
        // Note: engine continues listening after a segment in this
        // commit. Full one-shot (disengage on segment ready) is
        // deferred — it requires a coordinated update of ~25 tests
        // that assume continuous mode.

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

  /// Returns the current public state with an up-to-date [_jobs]
  /// snapshot. Reads [_engagement.state] (not the current
  /// [HandsFreeSessionState]) to decide between idle/listening — that
  /// way job-progression updates from the async [_sttSlot] don't flip
  /// [HandsFreeIdle] back to [HandsFreeListening] after a one-shot
  /// disengage, while engine events that arrive after [startSession]
  /// (when the public state is still the seeded [HandsFreeIdle]) still
  /// drive the controller into [HandsFreeListening] correctly.
  HandsFreeSessionState _listeningOrBacklog() {
    final jobs = List<SegmentJob>.unmodifiable(_jobs);
    if (_engagement.state is EngagementIdle) {
      return HandsFreeIdle(jobs: jobs);
    }
    return HandsFreeListening(jobs, phase: _phase);
  }

  void _terminateWithError(
    String message, {
    bool requiresSettings = false,
  }) {
    // Flip the session-active flag so SyncWorker stops background draining
    // immediately (P027, ADR-NET-002).
    _ref.read(sessionActiveProvider.notifier).state = false;
    unawaited(_ref.read(backgroundServiceProvider).stopService());
    _engagement.markError(message);
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
