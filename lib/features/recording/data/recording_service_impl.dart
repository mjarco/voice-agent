import 'dart:async';
import 'dart:io';

import 'package:record/record.dart';
import 'package:voice_agent/features/recording/domain/recording_result.dart';
import 'package:voice_agent/features/recording/domain/recording_service.dart';

/// [RecordingService] implementation using the `record` package.
///
/// Audio configuration is hardcoded to match Whisper's expected input:
/// 16 kHz, mono, PCM 16-bit, WAV container (AudioEncoder.wav).
class RecordingServiceImpl implements RecordingService {
  RecordingServiceImpl({AudioRecorder? recorder})
      : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;

  static const _sampleRate = 16000;
  static const _config = RecordConfig(
    encoder: AudioEncoder.wav,
    sampleRate: _sampleRate,
    numChannels: 1,
    bitRate: 256000,
  );

  @override
  Future<bool> requestPermission() => _recorder.hasPermission();

  String? _currentPath;
  Timer? _elapsedTimer;
  DateTime? _startTime;
  final _elapsedController = StreamController<Duration>.broadcast();

  @override
  Stream<Duration> get elapsed => _elapsedController.stream;

  @override
  bool get isRecording => _currentPath != null;

  @override
  Future<void> start({required String outputPath}) async {
    _currentPath = outputPath;
    _startTime = DateTime.now();

    await _recorder.start(_config, path: outputPath);

    _elapsedTimer = Timer.periodic(
      const Duration(milliseconds: 200),
      (_) {
        if (_startTime != null) {
          _elapsedController.add(DateTime.now().difference(_startTime!));
        }
      },
    );
  }

  @override
  Future<RecordingResult> stop() async {
    final path = await _recorder.stop();
    final duration =
        _startTime != null ? DateTime.now().difference(_startTime!) : Duration.zero;

    _cleanup();

    if (path == null || path.isEmpty) {
      throw StateError('Recording stopped but no file was produced');
    }

    return RecordingResult(
      filePath: path,
      duration: duration,
      sampleRate: _sampleRate,
    );
  }

  @override
  Future<void> cancel() async {
    final path = _currentPath;
    await _recorder.stop();
    _cleanup();

    // Delete the partial file
    if (path != null) {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  void _cleanup() {
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
    _startTime = null;
    _currentPath = null;
    // Do NOT close _elapsedController — it's an app-lifetime singleton.
    // Subscribers stay connected across recording sessions.
    // The stream goes quiet until the next start().
  }
}
