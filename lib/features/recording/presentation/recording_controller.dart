import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:voice_agent/features/recording/domain/recording_service.dart';
import 'package:voice_agent/features/recording/domain/recording_state.dart';

class RecordingController extends StateNotifier<RecordingState>
    with WidgetsBindingObserver {
  RecordingController(this._service) : super(const RecordingState.idle()) {
    WidgetsBinding.instance.addObserver(this);
  }

  final RecordingService _service;
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
    final status = await Permission.microphone.request();
    if (status.isDenied) {
      state = const RecordingState.error(
        'Microphone permission denied.',
      );
      return;
    }
    if (status.isPermanentlyDenied) {
      state = const RecordingState.error(
        'Microphone permission permanently denied. Please enable it in app settings.',
      );
      return;
    }

    try {
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
      state = RecordingState.error('Failed to start recording: $e');
    }
  }

  Future<void> stopRecording() async {
    try {
      final result = await _service.stop();
      _cleanupSubscription();
      state = RecordingState.completed(result);
    } catch (e) {
      _cleanupSubscription();
      state = RecordingState.error('Failed to stop recording: $e');
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
