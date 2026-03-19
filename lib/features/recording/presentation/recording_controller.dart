import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:voice_agent/core/config/app_config_provider.dart';
import 'package:voice_agent/core/models/transcript.dart';
import 'package:voice_agent/core/storage/storage_provider.dart';
import 'package:voice_agent/features/recording/domain/recording_service.dart';
import 'package:voice_agent/features/recording/domain/recording_state.dart';
import 'package:voice_agent/features/recording/domain/stt_exception.dart';
import 'package:voice_agent/features/recording/domain/stt_service.dart';

class RecordingController extends StateNotifier<RecordingState>
    with WidgetsBindingObserver {
  RecordingController(this._service, this._sttService, this._ref)
      : super(const RecordingState.idle()) {
    WidgetsBinding.instance.addObserver(this);
  }

  final RecordingService _service;
  final SttService _sttService;
  final Ref _ref;
  StreamSubscription<Duration>? _elapsedSub;
  Duration _currentElapsed = Duration.zero;

  Duration get currentElapsed => _currentElapsed;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && this.state is RecordingActive) {
      cancelRecording();
    }
  }

  Future<void> startRecording() async {
    final granted = await _service.requestPermission();
    if (!granted) {
      state = const RecordingState.error(
        'Microphone permission denied. Please enable it in app settings.',
        requiresSettings: true,
      );
      return;
    }

    // Await the initial config load so we read the persisted key, not the default null.
    await _ref.read(appConfigProvider.notifier).loadCompleted;
    final config = _ref.read(appConfigProvider);
    if (config.groqApiKey == null || config.groqApiKey!.isEmpty) {
      state = const RecordingState.error(
        'Groq API key not set.',
        requiresAppSettings: true,
      );
      return;
    }

    try {
      if (!await _sttService.isModelLoaded()) {
        await _sttService.loadModel();
      }

      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/recording_${DateTime.now().millisecondsSinceEpoch}.wav';

      _currentElapsed = Duration.zero;
      _elapsedSub = _service.elapsed.listen((d) {
        _currentElapsed = d;
      });

      await _service.start(outputPath: path);
      state = const RecordingState.recording();
    } catch (e) {
      _cleanupSubscription();
      state = RecordingState.error('Failed to start recording: $e');
    }
  }

  /// Stop recording, transcribe, save to storage, enqueue for sync, emit idle.
  /// If [silentOnEmpty] is true and the transcription result is empty,
  /// emits [RecordingIdle] without an error (used for press-and-hold).
  Future<void> stopAndTranscribe({bool silentOnEmpty = false}) async {
    try {
      final recordingResult = await _service.stop();
      _cleanupSubscription();

      state = const RecordingState.transcribing();

      final transcriptResult = await _sttService.transcribe(
        recordingResult.filePath,
      );

      if (!mounted) return;

      if (transcriptResult.text.trim().isEmpty) {
        state = silentOnEmpty
            ? const RecordingState.idle()
            : const RecordingState.error('Transcription returned empty text.');
        return;
      }

      final storage = _ref.read(storageServiceProvider);
      final deviceId = await storage.getDeviceId();
      if (!mounted) return;

      final transcript = Transcript(
        id: const Uuid().v4(),
        text: transcriptResult.text.trim(),
        language: transcriptResult.detectedLanguage,
        audioDurationMs: transcriptResult.audioDurationMs,
        deviceId: deviceId,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );

      await storage.saveTranscript(transcript);
      if (!mounted) return;

      try {
        await storage.enqueue(transcript.id);
        if (!mounted) return;
        state = const RecordingState.idle();
      } catch (e) {
        // Rollback: remove the transcript so it doesn't orphan.
        unawaited(storage.deleteTranscript(transcript.id));
        if (!mounted) return;
        state = RecordingState.error('Failed to enqueue transcript: $e');
      }
    } catch (e) {
      _cleanupSubscription();
      if (e is SttException) {
        state = RecordingState.error(e.message);
      } else {
        state = RecordingState.error('Transcription failed: $e');
      }
    }
  }

  Future<void> cancelRecording() async {
    try {
      await _service.cancel();
    } catch (_) {
      // Best-effort cleanup
    }
    _cleanupSubscription();
    state = const RecordingState.idle();
  }

  void resetToIdle() {
    state = const RecordingState.idle();
  }

  void _cleanupSubscription() {
    _elapsedSub?.cancel();
    _elapsedSub = null;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cleanupSubscription();
    super.dispose();
  }
}
