// Screens of the app rendered to PNG with its real fonts, for the reports of
// the redesign's off-roadmap tasks (S1–S5, 2026-11-15-va-graphite-*), when
// the phone is not at hand. Skipped in `make test`; run with
//
//   flutter test --dart-define=SHOTS=<dir> test/screenshots
//
// Data are made up here, as in the other widget tests: no owner's data.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'package:voice_agent/app/app.dart';
import 'package:voice_agent/core/audio/audio_feedback_provider.dart';
import 'package:voice_agent/core/audio/audio_feedback_service.dart';
import 'package:voice_agent/core/background/background_service_provider.dart';
import 'package:voice_agent/core/config/app_config.dart';
import 'package:voice_agent/core/config/app_config_provider.dart';
import 'package:voice_agent/core/config/app_config_service.dart';
import 'package:voice_agent/core/config/vad_config.dart';
import 'package:voice_agent/core/media_button/media_button_provider.dart';
import 'package:voice_agent/core/models/agenda.dart';
import 'package:voice_agent/core/models/matter.dart';
import 'package:voice_agent/core/models/routine.dart';
import 'package:voice_agent/core/models/sync_queue_item.dart';
import 'package:voice_agent/core/models/today.dart';
import 'package:voice_agent/core/models/transcript.dart';
import 'package:voice_agent/core/models/transcript_with_status.dart';
import 'package:voice_agent/core/network/connectivity_service.dart';
import 'package:voice_agent/core/notifications/agenda_notification_scheduler.dart';
import 'package:voice_agent/core/notifications/domain/notification_service.dart';
import 'package:voice_agent/core/notifications/notification_providers.dart';
import 'package:voice_agent/core/storage/storage_provider.dart';
import 'package:voice_agent/core/storage/storage_service.dart';
import 'package:voice_agent/core/tts/tts_provider.dart';
import 'package:voice_agent/core/tts/tts_service.dart';
import 'package:voice_agent/features/agenda/domain/agenda_repository.dart';
import 'package:voice_agent/features/agenda/presentation/agenda_providers.dart';
import 'package:voice_agent/features/api_sync/sync_provider.dart';
import 'package:voice_agent/features/matters/presentation/matters_providers.dart';
import 'package:voice_agent/features/recording/domain/hands_free_engine.dart';
import 'package:voice_agent/features/recording/presentation/recording_providers.dart';
import 'package:voice_agent/features/shopping/presentation/shopping_providers.dart';
import 'package:voice_agent/features/today/domain/today_repository.dart';
import 'package:voice_agent/features/today/presentation/today_providers.dart';

import '../features/matters/fake_matters_repository.dart';
import '../features/shopping/fake_shopping_repository.dart';
import '../features/today/fake_day_story_repository.dart';
import '../helpers/stub_background_service.dart';
import '../helpers/stub_media_button.dart';
import '../helpers/stub_session_control.dart';

const _out = String.fromEnvironment('SHOTS');

class _StubStorage with TelemetryStorageNoop implements StorageService {
  @override Future<String> getDeviceId() async => 'shots';
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
  @override Future<void> setCaptureGate({required bool open}) async {}
  @override Future<bool> hasPermission() async => true;
  @override Stream<HandsFreeEngineEvent> start({required VadConfig config}) => _ctrl.stream;
  @override Future<void> stop() async {}
  @override Future<void> interruptCapture() async {}
  @override void dispose() => _ctrl.close();
}

class _Config extends AppConfigService {
  _Config(this._config);
  final AppConfig _config;
  @override Future<AppConfig> load() async => _config;
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

class _Agenda implements AgendaRepository {
  @override
  Future<AgendaResponse> fetchAgenda(String date) async => AgendaResponse(
        date: date,
        granularity: 'day',
        from: date,
        to: date,
        routineItems: [
          AgendaRoutineItem(routineId: 'r1', routineName: 'Rachunek za prąd', kind: RoutineKind.oneOff, scheduledFor: '2026-11-14', overdue: true),
          AgendaRoutineItem(routineId: 'r2', routineName: 'Telefon do mamy', kind: RoutineKind.recurring, scheduledFor: date, startTime: '13:30', overdue: false),
          AgendaRoutineItem(routineId: 'r3', routineName: 'Trening — nogi', kind: RoutineKind.recurring, scheduledFor: date, startTime: '18:00', overdue: false),
        ],
      );
  @override Future<CachedAgenda?> getCachedAgenda(String date) async => null;
  @override Future<void> cacheAgenda(String date, AgendaResponse response) async {}
  @override Future<void> resolveOccurrence(String routineId, OccurrenceStatus status, {String? scheduledFor}) async {}
  @override Future<void> unresolveOccurrence(String routineId, {String? scheduledFor}) async {}
  @override Future<void> refreshCalendars() async {}
}

class _Notifications implements NotificationService {
  @override Future<void> init() async {}
  @override Future<bool> requestPermission() async => true;
  @override Future<bool> isPermitted() async => true;
  @override Future<void> schedule(ScheduledNotification n) async {}
  @override Future<void> cancel(int id) async {}
  @override Future<Map<int, ScheduledNotification>> currentlyScheduled() async => const {};
  @override Future<void> cancelAll() async {}
}

class _Today implements TodayRepository {
  @override
  Future<TodayView> fetchToday() async => TodayView.fromMap({
        'day': '2026-11-15',
        'title': 'Niedziela, 15 listopada',
        'food': {
          'has_target': true,
          'left_kcal': 1240,
          'kcal_max': 2100,
          'warning': '',
          'line': 'Zostało 1240 kcal',
          'next_meal': {'menu_entry_id': 'e', 'slot': 'lunch', 'slot_label': 'Obiad', 'name': 'kurczak z kaszą', 'kcal': 620},
        },
        'agenda': {
          'items': [
            {'kind': 'meeting', 'title': 'Spacer z Fafikiem', 'time': '08:30'},
            {'kind': 'task', 'key': 'r:1', 'routine_id': 'r1', 'title': 'Rachunek za prąd', 'overdue': true, 'note': 'od wczoraj'},
            {'kind': 'task', 'key': 'r:2', 'routine_id': 'r2', 'title': 'Telefon do mamy', 'time': '13:30'},
            {'kind': 'meeting', 'title': 'Trening — nogi', 'time': '18:00'},
          ],
          'tasks_open': 2,
        },
        'matters': {
          'in_progress': 2,
          'items': [
            {'id': 'm1', 'title': 'Remont łazienki', 'line': 'czeka na wycenę od glazurnika'},
            {'id': 'm2', 'title': 'Wymiana okien', 'line': 'zadzwonić po termin pomiaru'},
          ],
        },
        'shopping': {'to_buy': 3, 'line': '3 do kupienia'},
      });
  @override Future<void> run(TodayAction action) async {}
}

List<Override> _overrides(AppearanceMode mode) => [
      storageServiceProvider.overrideWithValue(_StubStorage()),
      connectivityServiceProvider.overrideWith((_) => _NoOpConnectivity()),
      handsFreeEngineProvider.overrideWithValue(_IdleHfEngine()),
      appConfigServiceProvider.overrideWithValue(_Config(AppConfig(
        groqApiKey: 'k',
        apiUrl: 'http://192.168.0.139:8898/api/v1/voice/transcript',
        appearance: mode,
      ))),
      ttsServiceProvider.overrideWithValue(_Tts()),
      audioFeedbackServiceProvider.overrideWithValue(_Feedback()),
      backgroundServiceProvider.overrideWithValue(StubBackgroundService()),
      mediaButtonProvider.overrideWithValue(StubMediaButtonPort()),
      agendaRepositoryProvider.overrideWithValue(_Agenda()),
      notificationServiceProvider.overrideWithValue(_Notifications()),
      agendaNotificationSchedulerProvider.overrideWithValue(
        AgendaNotificationScheduler(service: _Notifications(), location: tz.local, clock: DateTime.now),
      ),
      todayRepositoryProvider.overrideWithValue(_Today()),
      dayStoryRepositoryProvider.overrideWithValue(FakeDayStoryRepository()),
      mattersRepositoryProvider.overrideWithValue(FakeMattersRepository(matters: [
        const MatterSummary(id: 'm1', title: 'Remont łazienki', keywords: 'łazienka, kafelki', status: MatterStatus.active, nextStep: 'wybrać baterię', waitingFor: 'wycena od glazurnika'),
        const MatterSummary(id: 'm2', title: 'Wymiana okien', keywords: 'okna, PCV', status: MatterStatus.active, nextStep: 'zadzwonić po termin pomiaru'),
        const MatterSummary(id: 'm3', title: 'Kolano', keywords: 'ortopeda', status: MatterStatus.waiting, waitingFor: 'wyniki rezonansu'),
      ])),
      shoppingRepositoryProvider.overrideWithValue(FakeShoppingRepository()
        ..toBuy = [
          sampleItem(id: 'a', text: 'mleko owsiane', storeTypes: ['grocery']),
          sampleItem(id: 'b', text: 'kabel HDMI'),
          sampleItem(id: 'c', text: 'chleb żytni', storeTypes: ['grocery']),
        ]),
      ...sessionControlTestOverrides,
    ];

Future<void> _loadFonts() async {
  final sora = FontLoader('Sora');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    sora.addFont(Future.value(ByteData.sublistView(File('assets/fonts/Sora-$w.ttf').readAsBytesSync())));
  }
  await sora.load();
  final root = Platform.environment['FLUTTER_ROOT'] ?? '${Platform.environment['HOME']}/development/flutter';
  final icons = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.sublistView(
        File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf').readAsBytesSync())));
  await icons.load();
}

Future<void> _shot(WidgetTester tester, String name) async {
  await tester.pump(const Duration(milliseconds: 400));
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary).first);
  await tester.runAsync(() async {
    final ui.Image image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(_out).createSync(recursive: true);
    File('$_out/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

Future<void> _tab(WidgetTester tester, IconData icon) async {
  await tester.tap(find.byIcon(icon));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tz_data.initializeTimeZones();

  for (final mode in [AppearanceMode.light, AppearanceMode.dark]) {
    testWidgets('screens in ${mode.name}', (tester) async {
      await _loadFonts();
      tester.view.physicalSize = const Size(412 * 2.625, 915 * 2.625);
      tester.view.devicePixelRatio = 2.625;
      tester.view.padding = const FakeViewPadding(top: 24 * 2.625, bottom: 16 * 2.625);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(ProviderScope(overrides: _overrides(mode), child: const App()));
      await tester.pumpAndSettle();
      final m = mode.name;
      await _shot(tester, '01-dzis-$m');
      await _tab(tester, Icons.event_outlined);
      await _shot(tester, '02-agenda-$m');
      await _tab(tester, Icons.folder_open_outlined);
      await _shot(tester, '03-sprawy-$m');
      await _tab(tester, Icons.shopping_cart_outlined);
      await _shot(tester, '04-zakupy-$m');
      await _tab(tester, Icons.forum_outlined);
      await _shot(tester, '05-rozmowy-$m');
      await _tab(tester, Icons.wb_sunny_outlined);
      await tester.tap(find.byKey(const Key('app-settings')));
      await tester.pumpAndSettle();
      await _shot(tester, '06-ustawienia-$m');
    }, skip: _out.isEmpty);
  }
}
