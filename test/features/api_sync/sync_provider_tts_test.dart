import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/audio/audio_feedback_provider.dart';
import 'package:voice_agent/core/audio/audio_feedback_service.dart';
import 'package:voice_agent/core/config/app_config.dart';
import 'package:voice_agent/core/config/app_config_provider.dart';
import 'package:voice_agent/core/config/app_config_service.dart';
import 'package:voice_agent/core/models/sync_queue_item.dart';
import 'package:voice_agent/core/models/transcript.dart';
import 'package:voice_agent/core/models/transcript_with_status.dart';
import 'package:voice_agent/core/network/connectivity_service.dart';
import 'package:voice_agent/core/session_control/mic_mode.dart';
import 'package:voice_agent/core/storage/storage_provider.dart';
import 'package:voice_agent/core/storage/storage_service.dart';
import 'package:voice_agent/core/tts/tts_provider.dart';
import 'package:voice_agent/core/tts/tts_service.dart';
import 'package:voice_agent/features/api_sync/sync_provider.dart';

import '../../helpers/stub_session_control.dart';

class _Storage with TelemetryStorageNoop implements StorageService {
  @override Future<String> getDeviceId() async => 'test';
  @override Future<List<TranscriptWithStatus>> getTranscriptsWithStatus(
      {int limit = 20, int offset = 0}) async => [];
  @override Future<void> saveTranscript(Transcript t) async {}
  @override Future<Transcript?> getTranscript(String id) async => null;
  @override Future<List<Transcript>> getTranscripts(
      {int limit = 50, int offset = 0}) async => [];
  @override Future<void> deleteTranscript(String id) async {}
  @override Future<void> enqueue(String transcriptId) async {}
  @override Future<List<SyncQueueItem>> getPendingItems() async => [];
  @override Future<void> markSending(String id) async {}
  @override Future<void> markSent(String id) async {}
  @override Future<void> markFailed(String id, String error,
      {int? overrideAttempts}) async {}
  @override Future<void> markPendingForRetry(String id) async {}
  @override Future<void> reactivateForResend(String transcriptId) async {}
  @override Future<int> recoverStaleSending() async => 0;
  @override Future<List<SyncQueueItem>> getFailedItems(
      {int? maxAttempts}) async => [];
}

class _NoConnectivity extends ConnectivityService {
  @override
  Stream<ConnectivityStatus> get statusStream => const Stream.empty();
}

class _Tts implements TtsService {
  @override ValueListenable<bool> get isSpeaking => ValueNotifier(false);
  @override Future<void> speak(String text, {String? languageCode}) async {}
  @override Future<void> stop() async {}
  @override void dispose() {}
}

class _Feedback implements AudioFeedbackService {
  @override Future<void> startProcessingFeedback() async {}
  @override Future<void> stopLoop() async {}
  @override Future<void> playSuccess() async {}
  @override Future<void> playError() async {}
  @override void dispose() {}
}

class _Config extends AppConfigService {
  _Config(this._config);
  final AppConfig _config;
  @override
  Future<AppConfig> load() async => _config;
}

ProviderContainer _container({required bool ttsEnabled}) {
  final c = ProviderContainer(overrides: [
    storageServiceProvider.overrideWithValue(_Storage()),
    connectivityServiceProvider.overrideWith((_) => _NoConnectivity()),
    ttsServiceProvider.overrideWithValue(_Tts()),
    audioFeedbackServiceProvider.overrideWithValue(_Feedback()),
    appConfigServiceProvider.overrideWithValue(_Config(AppConfig(
      apiUrl: 'https://test.example.com/api',
      ttsEnabled: ttsEnabled,
    ))),
    ...sessionControlTestOverrides,
  ]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  setUpAll(() => WidgetsFlutterBinding.ensureInitialized());

  // ADR-AUDIO-013: a reply that arrives in Standby is not spoken.
  group('replies are spoken by mode', () {
    test('Listening and Off speak, Standby does not', () async {
      final c = _container(ttsEnabled: true);
      await c.read(appConfigProvider.notifier).loadCompleted;
      final worker = c.read(syncWorkerProvider);

      expect(worker.getTtsEnabled(), isTrue, reason: 'Off');
      c.read(micModeProvider.notifier).state = MicMode.listening;
      expect(worker.getTtsEnabled(), isTrue, reason: 'Listening');
      c.read(micModeProvider.notifier).state = MicMode.standby;
      expect(worker.getTtsEnabled(), isFalse, reason: 'Standby');
    });

    test('the TTS setting still wins in every mode', () async {
      final c = _container(ttsEnabled: false);
      await c.read(appConfigProvider.notifier).loadCompleted;
      final worker = c.read(syncWorkerProvider);

      for (final mode in MicMode.values) {
        c.read(micModeProvider.notifier).state = mode;
        expect(worker.getTtsEnabled(), isFalse, reason: mode.name);
      }
    });
  });
}
