import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/app/app.dart';
import 'package:voice_agent/core/audio/audio_feedback_provider.dart';
import 'package:voice_agent/core/audio/audio_feedback_service.dart';
import 'package:voice_agent/core/background/background_service_provider.dart';
import 'package:voice_agent/core/config/app_config.dart';
import 'package:voice_agent/core/config/app_config_provider.dart';
import 'package:voice_agent/core/config/app_config_service.dart';
import 'package:voice_agent/core/config/vad_config.dart';
import 'package:voice_agent/core/models/agenda.dart';
import 'package:voice_agent/core/models/routine.dart';
import 'package:voice_agent/core/models/sync_queue_item.dart';
import 'package:voice_agent/core/models/transcript.dart';
import 'package:voice_agent/core/models/transcript_with_status.dart';
import 'package:voice_agent/core/network/connectivity_service.dart';
import 'package:voice_agent/core/storage/storage_provider.dart';
import 'package:voice_agent/features/api_sync/sync_provider.dart';
import 'package:voice_agent/core/storage/storage_service.dart';
import 'package:voice_agent/core/tts/tts_provider.dart';
import 'package:voice_agent/core/tts/tts_service.dart';
import 'package:voice_agent/features/agenda/domain/agenda_repository.dart';
import 'package:voice_agent/features/agenda/presentation/agenda_providers.dart';
import 'package:voice_agent/features/recording/domain/hands_free_engine.dart';
import 'package:voice_agent/features/recording/domain/hands_free_session_state.dart';
import 'package:voice_agent/features/recording/presentation/hands_free_controller.dart';
import 'package:voice_agent/features/recording/presentation/recording_providers.dart';

import '../helpers/stub_background_service.dart';
import '../helpers/stub_session_control.dart';

// ── Stub dependencies ─────────────────────────────────────────────────────────

class _StubStorage implements StorageService {
  @override Future<String> getDeviceId() async => 'test';
  @override Future<List<TranscriptWithStatus>> getTranscriptsWithStatus({int limit = 20, int offset = 0}) async => [];
  @override Future<void> saveTranscript(Transcript t) async {}
  @override Future<Transcript?> getTranscript(String id) async => null;
  @override Future<List<Transcript>> getTranscripts({int limit = 50, int offset = 0}) async => [];
  @override Future<void> deleteTranscript(String id) async {}
  @override Future<void> enqueue(String transcriptId) async {}
  @override Future<List<SyncQueueItem>> getPendingItems() async => [];
  @override Future<void> markSending(String id) async {}
  @override Future<void> markSent(String id) async {}
  @override Future<void> markFailed(String id, String error, {int? overrideAttempts}) async {}
  @override Future<void> markPendingForRetry(String id) async {}
  @override Future<void> reactivateForResend(String transcriptId) async {}
  @override Future<int> recoverStaleSending() async => 0;
  @override Future<List<SyncQueueItem>> getFailedItems({int? maxAttempts}) async => [];
}

class _NoOpConnectivity extends ConnectivityService {
  @override
  Stream<ConnectivityStatus> get statusStream => const Stream.empty();
}

class _IdleHfEngine implements HandsFreeEngine {
  final _ctrl = StreamController<HandsFreeEngineEvent>.broadcast();
  @override Future<bool> hasPermission() async => true;
  @override Stream<HandsFreeEngineEvent> start({required VadConfig config}) => _ctrl.stream;
  @override Future<void> stop() async {}
  @override Future<void> interruptCapture() async {}
  @override void dispose() => _ctrl.close();
}

class _FixedConfigService extends AppConfigService {
  _FixedConfigService(this._config);
  final AppConfig _config;
  @override
  Future<AppConfig> load() async => _config;
}

class _StubTtsService implements TtsService {
  @override ValueListenable<bool> get isSpeaking => ValueNotifier(false);
  @override Future<void> speak(String text, {String? languageCode}) async {}
  @override Future<void> stop() async {}
  @override void dispose() {}
}

class _StubAudioFeedback implements AudioFeedbackService {
  @override Future<void> startProcessingFeedback() async {}
  @override Future<void> stopLoop() async {}
  @override Future<void> playSuccess() async {}
  @override Future<void> playError() async {}
  @override void dispose() {}
}

class _StubAgendaRepository implements AgendaRepository {
  @override
  Future<AgendaResponse> fetchAgenda(String date) async => AgendaResponse(
        date: date, granularity: 'day', from: date, to: date, items: [], routineItems: []);
  @override Future<CachedAgenda?> getCachedAgenda(String date) async => null;
  @override Future<void> cacheAgenda(String date, AgendaResponse response) async {}
  @override Future<void> markActionItemDone(String recordId) async {}
  @override Future<void> updateOccurrenceStatus(
    String routineId, String occurrenceId, OccurrenceStatus status) async {}
}

List<Override> get _baseOverrides => [
  storageServiceProvider.overrideWithValue(_StubStorage()),
  connectivityServiceProvider.overrideWith((_) => _NoOpConnectivity()),
  handsFreeEngineProvider.overrideWithValue(_IdleHfEngine()),
  appConfigServiceProvider.overrideWithValue(
    _FixedConfigService(const AppConfig(groqApiKey: 'test-key')),
  ),
  ttsServiceProvider.overrideWithValue(_StubTtsService()),
  audioFeedbackServiceProvider.overrideWithValue(_StubAudioFeedback()),
  backgroundServiceProvider.overrideWithValue(StubBackgroundService()),
  agendaRepositoryProvider.overrideWithValue(_StubAgendaRepository()),
  ...sessionControlTestOverrides,
];

// ── Tracking HandsFreeController stubs ───────────────────────────────────────

/// Tracks startSession/stopSession calls without doing real work.
/// Mirrors the real controller's idle-guard so tests reflect actual behavior.
class _TrackingHfController extends HandsFreeController {
  _TrackingHfController(super.ref);

  int startCalls = 0;
  int stopCalls = 0;

  @override
  Future<void> startSession({bool triggeredByActivation = false}) async {
    if (state is! HandsFreeIdle && state is! HandsFreeSessionError) return;
    startCalls++;
    state = HandsFreeListening([]);
  }

  @override
  Future<void> stopSession() async {
    if (state is HandsFreeIdle) return;
    stopCalls++;
    state = const HandsFreeIdle();
  }
}

/// Variant with a controllable drain delay for race-condition tests.
class _SlowStopHfController extends _TrackingHfController {
  _SlowStopHfController(super.ref, this._drainCompleter);

  final Completer<void> _drainCompleter;

  @override
  Future<void> stopSession() async {
    if (state is HandsFreeIdle) return;
    stopCalls++;
    await _drainCompleter.future;
    state = const HandsFreeIdle();
  }
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  // Finder for the Record icon inside the NavigationBar (avoids ambiguity with
  // the mic icon on the RecordingScreen itself).
  final recordNavIcon = find.descendant(
    of: find.byType(NavigationBar),
    matching: find.byIcon(Icons.mic),
  );

  testWidgets('switching away from Record tab calls stopSession', (tester) async {
    late _TrackingHfController controller;

    await tester.pumpWidget(ProviderScope(
      overrides: [
        ..._baseOverrides,
        handsFreeControllerProvider.overrideWith((ref) {
          controller = _TrackingHfController(ref);
          return controller;
        }),
      ],
      child: const App(),
    ));
    await tester.pumpAndSettle();

    expect(controller.startCalls, 1); // RecordingScreen.initState

    await tester.tap(find.byIcon(Icons.calendar_today));
    await tester.pumpAndSettle();

    expect(controller.stopCalls, 1);
  });

  testWidgets('switching back to Record tab calls startSession', (tester) async {
    late _TrackingHfController controller;

    await tester.pumpWidget(ProviderScope(
      overrides: [
        ..._baseOverrides,
        handsFreeControllerProvider.overrideWith((ref) {
          controller = _TrackingHfController(ref);
          return controller;
        }),
      ],
      child: const App(),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.calendar_today));
    await tester.pumpAndSettle(); // stopSession called, state → idle

    await tester.tap(recordNavIcon);
    await tester.pumpAndSettle();

    expect(controller.startCalls, 2); // 1 from initState + 1 from tab return
  });

  testWidgets('session recovers when user returns to Record during stopSession drain',
      (tester) async {
    final drainCompleter = Completer<void>();
    late _SlowStopHfController controller;

    await tester.pumpWidget(ProviderScope(
      overrides: [
        ..._baseOverrides,
        handsFreeControllerProvider.overrideWith((ref) {
          controller = _SlowStopHfController(ref, drainCompleter);
          return controller;
        }),
      ],
      child: const App(),
    ));
    await tester.pumpAndSettle();

    expect(controller.startCalls, 1);

    // Navigate away — stopSession starts but won't finish until drainCompleter fires.
    await tester.tap(find.byIcon(Icons.calendar_today));
    await tester.pumpAndSettle();

    expect(controller.stopCalls, 1);
    expect(controller.startCalls, 1); // unchanged

    // Navigate back — startSession is called but the guard blocks it (not idle yet).
    await tester.tap(recordNavIcon);
    await tester.pumpAndSettle();

    expect(controller.startCalls, 1); // still blocked

    // Complete the drain — the .then() callback registers addPostFrameCallback.
    drainCompleter.complete();
    await tester.pumpAndSettle(); // frame fires → currentIndex == 2 → startSession

    expect(controller.startCalls, 2); // recovery call
  });
}
