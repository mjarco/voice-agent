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
import 'package:voice_agent/core/models/agent_action.dart';
import 'package:voice_agent/core/providers/agent_reply_provider.dart';
import 'package:voice_agent/core/models/matter.dart';
import 'package:voice_agent/core/models/routine.dart';
import 'package:voice_agent/core/subject/utterance_subject.dart';
import 'package:voice_agent/core/network/pin_writer.dart';
import 'package:voice_agent/features/chat/domain/chat_repository.dart';
import 'package:voice_agent/core/network/sse_client.dart';
import 'package:voice_agent/features/chat/presentation/chat_providers.dart';
import 'package:go_router/go_router.dart';
import 'package:voice_agent/core/notifications/agenda_notification_scheduler.dart';
import 'package:voice_agent/core/notifications/domain/notification_service.dart';
import 'package:voice_agent/core/notifications/notification_providers.dart';
import 'package:voice_agent/core/home_widget/home_widget_provider.dart';
import 'package:voice_agent/core/home_widget/widget_tap_channel.dart';
import 'package:voice_agent/core/models/today.dart';
import 'package:voice_agent/core/session_control/mic_mode.dart';
import 'package:voice_agent/features/diet/domain/diet_repository.dart';
import 'package:voice_agent/features/diet/presentation/diet_day_screen.dart';
import 'package:voice_agent/features/diet/presentation/diet_providers.dart';
import 'package:voice_agent/features/matters/presentation/matters_providers.dart';
import 'package:voice_agent/features/today/domain/today_repository.dart';
import 'package:voice_agent/features/today/presentation/today_providers.dart';
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
import '../features/matters/fake_matters_repository.dart';

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
  void hold() {}

  @override
  Future<void> releaseHold({required bool close}) async {}
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

/// Counts the widget mic's asks for listening.
class _ListenHfController extends _TrackingHfController {
  _ListenHfController(super.ref);

  int listenCalls = 0;

  @override
  void listen() => listenCalls++;
}

class _CountingTodayRepo implements TodayRepository {
  int reads = 0;

  @override
  Future<TodayView> fetchToday() async {
    reads++;
    return TodayView.fromMap({'day': '2026-11-15', 'title': 'Dziś'});
  }

  @override
  Future<void> run(TodayAction action) async {}
}

/// The diet's day fails to read: its screen still opens, which is all the
/// widget's tap needs.
class _OfflineDiet implements DietRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      Future<Never>.error(Exception('offline'));
}

/// The diet's day fails to read; a meal removed is recorded.
class _UndoDiet implements DietRepository {
  final removed = <String>[];
  @override
  Future<void> removeMeal(String id) async => removed.add(id);
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      Future<Never>.error(Exception('offline'));
}

/// A chat with no models or backends: a new thread opens empty.
class _EmptyChat implements ChatRepository {
  @override
  Future<List<ModelInfo>> getModels({String? backend}) async => const [];
  @override
  Future<BackendOptions> getBackends() async => const BackendOptions(backends: []);
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// Records what a thread sent; the stream ends with no event.
class _SendingChat extends _EmptyChat {
  final sent = <({String content, Map<String, dynamic>? subject})>[];

  @override
  Stream<SseEvent> streamChat({
    required String sessionId,
    required String content,
    required String idempotencyKey,
    String? model,
    String? backend,
    Map<String, dynamic>? subject,
  }) {
    sent.add((content: content, subject: subject));
    return const Stream.empty();
  }
}

class _NoPins implements PinWriter {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
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

    await tester.tap(find.byIcon(Icons.event_outlined));
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
    await tester.tap(find.byIcon(Icons.event_outlined));
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

    await tester.tap(find.byIcon(Icons.event_outlined));
    await tester.pumpAndSettle();
    await tester.tap(todayNavIcon);
    await tester.pumpAndSettle();

    expect(controller.stopCalls, 0);
    expect(controller.startCalls, 1, reason: 'only the explicit start');
    expect(controller.state, isA<HandsFreeListening>());
  });

  group('home-screen widget taps (ADR-PLATFORM-015)', () {
    late _ListenHfController controller;
    late _CountingTodayRepo today;

    Future<StreamController<WidgetTap>> pump(
      WidgetTester tester, {
      WidgetTap? cold,
    }) async {
      final warm = StreamController<WidgetTap>();
      addTearDown(warm.close);
      today = _CountingTodayRepo();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          ..._baseOverrides,
          micModesEnabledProvider.overrideWithValue(true),
          handsFreeControllerProvider.overrideWith((ref) {
            controller = _ListenHfController(ref);
            return controller;
          }),
          todayRepositoryProvider.overrideWithValue(today),
          dietRepositoryProvider.overrideWithValue(_OfflineDiet()),
          mattersRepositoryProvider.overrideWithValue(FakeMattersRepository()),
          pendingWidgetTapProvider.overrideWith((ref) => cold),
          widgetTapStreamProvider.overrideWith((ref) => warm.stream),
        ],
        child: const App(),
      ));
      await tester.pumpAndSettle();
      return warm;
    }

    int tab(WidgetTester tester) =>
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex;

    testWidgets('the calories open the diet\'s day over Dziś; Back lands '
        'on Dziś, read again', (tester) async {
      final warm = await pump(tester);
      await tester.tap(find.byIcon(Icons.event_outlined));
      await tester.pumpAndSettle();

      warm.add(WidgetTap.food);
      await tester.pumpAndSettle();
      expect(find.byType(DietDayScreen), findsOneWidget);

      final reads = today.reads;
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(DietDayScreen), findsNothing);
      expect(tab(tester), 0);
      expect(today.reads, greaterThan(reads));
    });

    testWidgets('the tasks open Dziś, the matters open Sprawy',
        (tester) async {
      final warm = await pump(tester);
      warm.add(WidgetTap.matters);
      await tester.pumpAndSettle();
      expect(tab(tester), 2);

      warm.add(WidgetTap.tasks);
      await tester.pumpAndSettle();
      expect(tab(tester), 0);
    });

    testWidgets('the mic opens Dziś and asks to listen, once per tap',
        (tester) async {
      final warm = await pump(tester);
      await tester.tap(find.byIcon(Icons.event_outlined));
      await tester.pumpAndSettle();

      // A warm tap comes through onNewIntent, before the activity resumes.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      warm.add(WidgetTap.listen);
      await tester.pumpAndSettle();
      expect(tab(tester), 0);
      expect(controller.listenCalls, 0, reason: 'not before it is in front');

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(controller.listenCalls, 1);

      warm.add(WidgetTap.listen);
      await tester.pumpAndSettle();
      expect(controller.listenCalls, 2, reason: 'in front, at once');
    });

    testWidgets('leaving the app reads the day again, for the widget',
        (tester) async {
      await pump(tester);
      final reads = today.reads;

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();

      expect(today.reads, reads + 1);
    });

    testWidgets('a tap that launched the app is taken once', (tester) async {
      await pump(tester, cold: WidgetTap.listen);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(tab(tester), 0);
      expect(controller.listenCalls, 1);
      final container =
          ProviderScope.containerOf(tester.element(find.byType(App)));
      expect(container.read(pendingWidgetTapProvider), isNull);
    });
  });

  group('the subject of an utterance (ADR-NET-008)', () {
    Future<ProviderContainer> pump(WidgetTester tester,
        {ChatRepository? chat}) async {
      final matters = FakeMattersRepository(details: {
        'm1': const MatterDetail(matter: MatterSummary(id: 'm1', title: 'Remont łazienki', status: MatterStatus.active)),
      });
      await tester.pumpWidget(ProviderScope(
        overrides: [
          ..._baseOverrides,
          todayRepositoryProvider.overrideWithValue(_CountingTodayRepo()),
          mattersRepositoryProvider.overrideWithValue(matters),
          chatRepositoryProvider.overrideWithValue(chat ?? _EmptyChat()),
          pinWriterProvider.overrideWithValue(_NoPins()),
          shoppingProposalsPortProvider.overrideWithValue(FakeShoppingProposals()),
        ],
        child: const App(),
      ));
      await tester.pumpAndSettle();
      return ProviderScope.containerOf(tester.element(find.byType(App)));
    }

    testWidgets('on a matter the field takes text; sending opens a thread on '
        'the matter and sends it there', (tester) async {
      final chat = _SendingChat();
      await pump(tester, chat: chat);
      final router = GoRouter.of(tester.element(find.byType(NavigationBar)));
      unawaited(router.push('/matter/m1'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('field-send')), findsNothing);
      await tester.tap(find.byKey(const Key('field-text')));
      await tester.pump();
      expect(tester.testTextInput.isVisible, isTrue);
      await tester.enterText(find.byKey(const Key('field-text')), 'Kupić płytki ');
      await tester.pump();
      await tester.tap(find.byKey(const Key('field-send')));
      await tester.pumpAndSettle();

      expect(router.state.uri.toString(), '/conversation/new?matter=m1');
      expect(chat.sent.map((e) => e.content), ['Kupić płytki']);
      expect(chat.sent.single.subject.toString(), contains('m1'));
    });

    testWidgets('on Dziś with no conversation a typed text opens a new one and '
        'is sent with the send key', (tester) async {
      final chat = _SendingChat();
      await pump(tester, chat: chat);
      final router = GoRouter.of(tester.element(find.byType(NavigationBar)));

      await tester.enterText(find.byKey(const Key('field-text')), 'Co mam dziś?');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pumpAndSettle();

      expect(router.state.uri.toString(), '/conversation/new');
      expect(chat.sent.map((e) => e.content), ['Co mam dziś?']);
    });

    UtteranceSubject subjectNow(ProviderContainer c) => c.read(utteranceSubjectReaderProvider)();

    testWidgets('a matter on top is the subject; Dzień elsewhere, and with the app hidden',
        (tester) async {
      final c = await pump(tester);
      final router = GoRouter.of(tester.element(find.byType(NavigationBar)));
      expect(subjectNow(c), UtteranceSubject.day);

      unawaited(router.push('/matter/m1'));
      await tester.pumpAndSettle();
      expect(find.text('Powiedz albo napisz w tej sprawie…'), findsOneWidget);
      expect(subjectNow(c), const UtteranceSubject.matter('m1'));

      // The phone locked, or the app hidden, while on the matter.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      expect(subjectNow(c), UtteranceSubject.day);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(subjectNow(c), const UtteranceSubject.matter('m1'));

      // Napisz on the matter opens a new thread on it; under it the subject
      // is Dzień again, as the thread sends its own.
      await tester.tap(find.byKey(const Key('field-write')));
      await tester.pumpAndSettle();
      expect(router.state.uri.toString(), '/conversation/new?matter=m1');
      expect(subjectNow(c), UtteranceSubject.day);

      router.pop();
      await tester.pumpAndSettle();
      expect(subjectNow(c), const UtteranceSubject.matter('m1'));
    });
  });

  group('the diet: Jedzenie and the card of a meal (ADR-NET-009)', () {
    testWidgets('on the diet the subject is Jedzenie; the meal a reply logged '
        'stands under it, and Cofnij removes it', (tester) async {
      final diet = _UndoDiet();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          ..._baseOverrides,
          todayRepositoryProvider.overrideWithValue(_CountingTodayRepo()),
          mattersRepositoryProvider.overrideWithValue(FakeMattersRepository()),
          dietRepositoryProvider.overrideWithValue(diet),
        ],
        child: const App(),
      ));
      await tester.pumpAndSettle();
      final c = ProviderScope.containerOf(tester.element(find.byType(App)));
      final router = GoRouter.of(tester.element(find.byType(NavigationBar)));

      unawaited(router.push('/diet'));
      await tester.pumpAndSettle();
      expect(c.read(utteranceSubjectReaderProvider)(), UtteranceSubject.diet);

      c.read(latestAgentActionsProvider.notifier).state = const [
        AgentAction.mealLogged(mealId: 'm-1', name: 'piwo', day: '2026-11-15', time: '22:11',
            kcal: 270, kcalLow: 250, kcalHigh: 290, leftKcal: 410, warning: 'low'),
      ];
      c.read(latestAgentReplyProvider.notifier).state = 'Zapisałem piwo, 270 kcal.';
      await tester.pumpAndSettle();
      expect(find.text('✓ piwo · 22:11'), findsOneWidget);
      expect(find.text('270 (250–290) kcal · zostało 410'), findsOneWidget);

      final changes = c.read(dietChangedProvider);
      await tester.tap(find.byKey(const Key('meal-action-undo-m-1')));
      await tester.pumpAndSettle();
      expect(diet.removed, ['m-1']);
      expect(find.byKey(const Key('meal-action-m-1')), findsNothing);
      expect(find.text('Cofnięto: piwo'), findsOneWidget);
      expect(c.read(dietChangedProvider), changes + 1);
      expect(c.read(latestAgentActionsProvider), isEmpty);
    });

    testWidgets('on Dziś the reply stands without a card', (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          ..._baseOverrides,
          todayRepositoryProvider.overrideWithValue(_CountingTodayRepo()),
          mattersRepositoryProvider.overrideWithValue(FakeMattersRepository()),
        ],
        child: const App(),
      ));
      await tester.pumpAndSettle();
      final c = ProviderScope.containerOf(tester.element(find.byType(App)));
      c.read(latestAgentActionsProvider.notifier).state = const [
        AgentAction.mealLogged(mealId: 'm-1', name: 'piwo', day: '2026-11-15', time: '22:11',
            kcal: 270, kcalLow: 250, kcalHigh: 290),
      ];
      c.read(latestAgentReplyProvider.notifier).state = 'Zapisałem piwo, 270 kcal.';
      await tester.pumpAndSettle();
      expect(find.text('Zapisałem piwo, 270 kcal.'), findsOneWidget);
      expect(find.byKey(const Key('meal-action-m-1')), findsNothing);
    });
  });
}
