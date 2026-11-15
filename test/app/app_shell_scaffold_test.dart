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
import 'package:voice_agent/core/notifications/agenda_notification_scheduler.dart';
import 'package:voice_agent/core/notifications/domain/notification_service.dart';
import 'package:voice_agent/core/notifications/notification_providers.dart';
import 'package:voice_agent/core/session_control/mic_mode.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'package:voice_agent/core/models/sync_queue_item.dart';
import 'package:voice_agent/core/models/transcript.dart';
import 'package:voice_agent/core/models/transcript_with_status.dart';
import 'package:voice_agent/core/network/connectivity_service.dart';
import 'package:voice_agent/core/network/shopping_proposals_port.dart';
import 'package:voice_agent/core/storage/storage_provider.dart';
import 'package:voice_agent/features/api_sync/sync_provider.dart';
import 'package:voice_agent/core/storage/storage_service.dart';
import 'package:voice_agent/core/tts/tts_provider.dart';
import 'package:voice_agent/core/tts/tts_service.dart';
import 'package:voice_agent/features/agenda/domain/agenda_repository.dart';
import 'package:voice_agent/features/agenda/presentation/agenda_providers.dart';
import 'package:voice_agent/core/media_button/media_button_provider.dart';
import 'package:voice_agent/features/recording/domain/hands_free_engine.dart';
import 'package:voice_agent/features/recording/domain/hands_free_session_state.dart';
import 'package:voice_agent/features/recording/presentation/hands_free_controller.dart';
import 'package:voice_agent/features/recording/presentation/recording_providers.dart';
import 'package:voice_agent/features/shopping/presentation/shopping_providers.dart';

import '../core/network/fake_shopping_proposals.dart';
import '../features/shopping/fake_shopping_repository.dart';
import '../helpers/stub_background_service.dart';
import '../helpers/stub_media_button.dart';
import '../helpers/stub_session_control.dart';

// ── Stub dependencies ─────────────────────────────────────────────────────────

class _StubStorage with TelemetryStorageNoop implements StorageService {
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
  @override
  Future<void> setCaptureGate({required bool open}) async {}

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
        date: date, granularity: 'day', from: date, to: date, routineItems: []);
  @override Future<CachedAgenda?> getCachedAgenda(String date) async => null;
  @override Future<void> cacheAgenda(String date, AgendaResponse response) async {}
  @override
  Future<void> resolveOccurrence(
    String routineId,
    OccurrenceStatus status, {
    String? scheduledFor,
  }) async {}
  @override
  Future<void> unresolveOccurrence(String routineId,
      {String? scheduledFor}) async {}
  @override Future<void> refreshCalendars() async {}
}

/// Minimal in-memory NotificationService for widget tests.
class _StubNotificationService implements NotificationService {
  final Map<int, ScheduledNotification> _snapshot = {};
  @override
  Future<void> init() async {}
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<bool> isPermitted() async => true;
  @override
  Future<void> schedule(ScheduledNotification n) async => _snapshot[n.id] = n;
  @override
  Future<void> cancel(int id) async => _snapshot.remove(id);
  @override
  Future<Map<int, ScheduledNotification>> currentlyScheduled() async =>
      Map.unmodifiable(_snapshot);
  @override
  Future<void> cancelAll() async => _snapshot.clear();
}

List<Override> get _baseOverrides {
  final notifications = _StubNotificationService();
  return [
    storageServiceProvider.overrideWithValue(_StubStorage()),
    connectivityServiceProvider.overrideWith((_) => _NoOpConnectivity()),
    handsFreeEngineProvider.overrideWithValue(_IdleHfEngine()),
    appConfigServiceProvider.overrideWithValue(
      _FixedConfigService(const AppConfig(
          groqApiKey: 'test-key', apiUrl: 'https://test.example.com/api')),
    ),
    ttsServiceProvider.overrideWithValue(_StubTtsService()),
    audioFeedbackServiceProvider.overrideWithValue(_StubAudioFeedback()),
    backgroundServiceProvider.overrideWithValue(StubBackgroundService()),
    mediaButtonProvider.overrideWithValue(StubMediaButtonPort()),
    agendaRepositoryProvider.overrideWithValue(_StubAgendaRepository()),
    notificationServiceProvider.overrideWithValue(notifications),
    agendaNotificationSchedulerProvider.overrideWithValue(
      AgendaNotificationScheduler(
        service: notifications,
        location: tz.local,
        clock: DateTime.now,
      ),
    ),
    ...sessionControlTestOverrides,
  ];
}

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

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tz_data.initializeTimeZones();

  // Dziś's icon inside the NavigationBar (ADR-ARCH-013).
  final todayNavIcon = find.descendant(
    of: find.byType(NavigationBar),
    matching: find.byIcon(Icons.wb_sunny_outlined),
  );

  testWidgets('opening the Shopping tab reads the proposals again',
      (tester) async {
    final proposals = FakeShoppingProposals();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        ..._baseOverrides,
        shoppingRepositoryProvider.overrideWithValue(FakeShoppingRepository()),
        shoppingProposalsPortProvider.overrideWithValue(proposals),
      ],
      child: const App(),
    ));
    await tester.pumpAndSettle();

    final shopping = find.byIcon(Icons.shopping_cart_outlined);
    await tester.tap(shopping);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shopping-proposal-p1')), findsNothing);

    await tester.tap(todayNavIcon);
    await tester.pumpAndSettle();
    proposals.rows = [sampleProposal()];
    await tester.tap(shopping);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('shopping-proposal-p1')), findsOneWidget);
  });

  testWidgets(
      'switching tabs never touches the microphone, without the Android '
      'modes too (ADR-ARCH-013)', (tester) async {
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

    await controller.startSession();
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.calendar_today));
    await tester.pumpAndSettle();
    await tester.tap(todayNavIcon);
    await tester.pumpAndSettle();

    expect(controller.stopCalls, 0);
    expect(controller.startCalls, 1, reason: 'only the explicit start');
  });

  testWidgets('the app opens on Dziś with five Polish tabs', (tester) async {
    await tester.pumpWidget(ProviderScope(overrides: _baseOverrides, child: const App()));
    await tester.pumpAndSettle();
    for (final label in ['Dziś', 'Agenda', 'Sprawy', 'Zakupy', 'Rozmowy']) {
      expect(find.descendant(of: find.byType(NavigationBar), matching: find.text(label)), findsOneWidget);
    }
    expect(find.byKey(const Key('field-mic')), findsOneWidget, reason: 'the conversation field');
  });

  testWidgets('Back on another tab goes to Dziś, not out of the app', (tester) async {
    await tester.pumpWidget(ProviderScope(overrides: _baseOverrides, child: const App()));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.calendar_today));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('field-mic')), findsNothing);
    final popped = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(popped, isTrue, reason: 'handled inside the app');
    expect(find.byKey(const Key('field-mic')), findsOneWidget);
  });

  testWidgets(
      'Android modes: switching tabs away and back never touches the '
      'microphone (ADR-AUDIO-013)', (tester) async {
    late _TrackingHfController controller;

    await tester.pumpWidget(ProviderScope(
      overrides: [
        ..._baseOverrides,
        micModesEnabledProvider.overrideWithValue(true),
        handsFreeControllerProvider.overrideWith((ref) {
          controller = _TrackingHfController(ref);
          return controller;
        }),
      ],
      child: const App(),
    ));
    await tester.pumpAndSettle();

    await controller.startSession();
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.calendar_today));
    await tester.pumpAndSettle();
    await tester.tap(todayNavIcon);
    await tester.pumpAndSettle();

    expect(controller.stopCalls, 0);
    expect(controller.startCalls, 1, reason: 'only the explicit start');
    expect(controller.state, isA<HandsFreeListening>());
  });
}
