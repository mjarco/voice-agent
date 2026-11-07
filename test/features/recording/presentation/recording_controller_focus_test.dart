import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/audio/audio_feedback_provider.dart';
import 'package:voice_agent/core/audio/audio_feedback_service.dart';
import 'package:voice_agent/core/audio_focus/audio_focus_port.dart';
import 'package:voice_agent/core/audio_focus/audio_focus_provider.dart';
import 'package:voice_agent/core/config/app_config.dart';
import 'package:voice_agent/core/config/app_config_provider.dart';
import 'package:voice_agent/core/config/app_config_service.dart';
import 'package:voice_agent/core/models/transcript_result.dart';
import 'package:voice_agent/features/recording/domain/recording_result.dart';
import 'package:voice_agent/features/recording/domain/recording_service.dart';
import 'package:voice_agent/features/recording/domain/recording_state.dart';
import 'package:voice_agent/features/recording/domain/stt_exception.dart';
import 'package:voice_agent/features/recording/domain/stt_service.dart';
import 'package:voice_agent/features/recording/presentation/recording_providers.dart';

// Push-to-talk holds the app's own transient focus while the button is held
// (ADR-AUDIO-014): requested before the recorder starts, given back once it
// stops.

class _Focus implements AudioFocusPort {
  _Focus(this.log);
  final List<String> log;
  bool granted = true;

  @override
  Future<bool> request() async {
    log.add('focus.request');
    return granted;
  }

  @override
  Future<void> abandon() async => log.add('focus.abandon');

  @override
  Stream<AudioFocusLoss> get losses => const Stream.empty();
}

class _Recorder implements RecordingService {
  _Recorder(this.log);
  final List<String> log;
  bool failStart = false;
  bool failStop = false;

  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<void> start({required String outputPath}) async {
    if (failStart) throw Exception('no mic');
    log.add('recorder.start');
  }

  @override
  Future<RecordingResult> stop() async {
    if (failStop) throw Exception('stop failed');
    log.add('recorder.stop');
    return const RecordingResult(
        filePath: '/tmp/t.wav', duration: Duration.zero, sampleRate: 16000);
  }

  @override
  Future<void> pause() async {}
  @override
  Future<void> resume() async {}
  @override
  Future<void> cancel() async => log.add('recorder.cancel');
  @override
  bool get isRecording => false;
  @override
  Stream<Duration> get elapsed => const Stream.empty();
}

class _FailingStt implements SttService {
  @override
  Future<bool> isModelLoaded() async => true;
  @override
  Future<void> loadModel() async {}
  @override
  Future<TranscriptResult> transcribe(String wavPath,
          {String? languageCode}) async =>
      throw SttException('offline');
}

class _NoAudioFeedback implements AudioFeedbackService {
  @override
  Future<void> startProcessingFeedback() async {}
  @override
  Future<void> stopLoop() async {}
  @override
  Future<void> playSuccess() async {}
  @override
  Future<void> playError() async {}
  @override
  void dispose() {}
}

class _Config extends AppConfigService {
  @override
  Future<AppConfig> load() async => const AppConfig(
      groqApiKey: 'gsk_test', apiUrl: 'https://test.example.com/api');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  late List<String> log;
  late _Focus focus;
  late _Recorder recorder;
  late ProviderContainer container;

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (_) async => '/tmp');
    log = [];
    focus = _Focus(log);
    recorder = _Recorder(log);
    container = ProviderContainer(overrides: [
      audioFocusProvider.overrideWithValue(focus),
      recordingServiceProvider.overrideWithValue(recorder),
      sttServiceProvider.overrideWithValue(_FailingStt()),
      audioFeedbackServiceProvider.overrideWithValue(_NoAudioFeedback()),
      appConfigServiceProvider.overrideWithValue(_Config()),
    ]);
  });

  tearDown(() {
    container.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
  });

  test('the focus is requested before the recorder starts', () async {
    await container.read(recordingControllerProvider.notifier).startRecording();

    expect(container.read(recordingControllerProvider),
        isA<RecordingActive>());
    expect(log, ['focus.request', 'recorder.start']);
  });

  test('a refused focus does not stop an explicit press', () async {
    focus.granted = false;
    await container.read(recordingControllerProvider.notifier).startRecording();

    expect(container.read(recordingControllerProvider),
        isA<RecordingActive>());
    expect(log, ['focus.request', 'recorder.start']);
  });

  test('the focus is given back once the recorder stops', () async {
    final ctrl = container.read(recordingControllerProvider.notifier);
    await ctrl.startRecording();
    log.clear();

    await ctrl.stopAndTranscribe(silentOnEmpty: true);

    expect(log.take(2), ['recorder.stop', 'focus.abandon']);
  });

  test('a failing stop still gives the focus back', () async {
    final ctrl = container.read(recordingControllerProvider.notifier);
    await ctrl.startRecording();
    log.clear();
    recorder.failStop = true;

    await ctrl.stopAndTranscribe(silentOnEmpty: true);

    expect(container.read(recordingControllerProvider), isA<RecordingError>());
    expect(log, ['focus.abandon']);
  });

  test('a cancel gives the focus back', () async {
    final ctrl = container.read(recordingControllerProvider.notifier);
    await ctrl.startRecording();
    log.clear();

    await ctrl.cancelRecording();

    expect(log, ['recorder.cancel', 'focus.abandon']);
  });

  test('a recorder that fails to start gives the focus back', () async {
    recorder.failStart = true;
    await container.read(recordingControllerProvider.notifier).startRecording();

    expect(container.read(recordingControllerProvider), isA<RecordingError>());
    expect(log, ['focus.request', 'focus.abandon']);
  });
}
