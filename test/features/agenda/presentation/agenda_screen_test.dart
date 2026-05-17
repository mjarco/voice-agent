import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'package:voice_agent/core/config/app_config_provider.dart';
import 'package:voice_agent/core/config/app_config_service.dart';
import 'package:voice_agent/core/models/agenda.dart';
import 'package:voice_agent/core/models/conversation_record.dart';
import 'package:voice_agent/core/models/routine.dart';
import 'package:voice_agent/core/notifications/agenda_notification_scheduler.dart';
import 'package:voice_agent/core/notifications/domain/notification_service.dart';
import 'package:voice_agent/core/notifications/notification_providers.dart';
import 'package:voice_agent/features/agenda/domain/agenda_repository.dart';
import 'package:voice_agent/features/agenda/presentation/agenda_providers.dart';
import 'package:voice_agent/features/agenda/presentation/agenda_screen.dart';

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

class _StubRepository implements AgendaRepository {
  AgendaResponse? response;
  bool markDoneSuccess = true;
  bool updateStatusSuccess = true;

  _StubRepository({this.response});

  @override
  Future<AgendaResponse> fetchAgenda(String date) async =>
      response ??
      AgendaResponse(
        date: date,
        granularity: 'day',
        from: date,
        to: date,
        items: [],
        routineItems: [],
      );

  @override
  Future<CachedAgenda?> getCachedAgenda(String date) async => null;

  @override
  Future<void> cacheAgenda(String date, AgendaResponse response) async {}

  @override
  Future<void> markActionItemDone(String recordId) async {
    if (!markDoneSuccess) throw Exception('Failed');
  }

  @override
  Future<void> updateOccurrenceStatus(
    String routineId,
    String occurrenceId,
    OccurrenceStatus status,
  ) async {
    if (!updateStatusSuccess) throw Exception('Failed');
  }
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  _StubRepository? repository,
}) async {
  final repo = repository ?? _StubRepository();
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const AgendaScreen(),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) =>
            const Scaffold(body: Text('Settings')),
      ),
    ],
  );

  // Wire the deps the new P040 agendaNotifierProvider chain needs.
  final notifications = _StubNotificationService();
  final scheduler = AgendaNotificationScheduler(
    service: notifications,
    location: tz.local,
    clock: DateTime.now,
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        agendaRepositoryProvider.overrideWithValue(repo),
        notificationServiceProvider.overrideWithValue(notifications),
        agendaNotificationSchedulerProvider.overrideWithValue(scheduler),
        appConfigServiceProvider.overrideWithValue(AppConfigService()),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    tz_data.initializeTimeZones();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('AgendaScreen', () {
    testWidgets('renders AppBar with title', (tester) async {
      await _pumpScreen(tester);

      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('Agenda'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('renders gear icon that navigates to settings',
        (tester) async {
      await _pumpScreen(tester);

      expect(find.byKey(const Key('agenda-settings-icon')), findsOneWidget);

      await tester.tap(find.byKey(const Key('agenda-settings-icon')));
      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets('renders date navigation bar', (tester) async {
      await _pumpScreen(tester);

      expect(find.byKey(const Key('agenda-date-label')), findsOneWidget);
      expect(find.byKey(const Key('agenda-prev-day')), findsOneWidget);
      expect(find.byKey(const Key('agenda-next-day')), findsOneWidget);
    });

    testWidgets('shows empty state when no items', (tester) async {
      await _pumpScreen(tester);

      expect(find.text('No items for this date'), findsOneWidget);
    });

    testWidgets('renders action items', (tester) async {
      final repo = _StubRepository(
        response: AgendaResponse(
          date: '2026-04-19',
          granularity: 'day',
          from: '2026-04-19',
          to: '2026-04-19',
          items: [
            const AgendaItem(
              recordId: 'rec-1',
              text: 'Buy groceries',
              scheduledFor: '2026-04-19',
              timeWindow: TimeWindow.day,
              originRole: OriginRole.agent,
              status: RecordStatus.active,
              linkedConversationCount: 0,
            ),
          ],
          routineItems: [],
        ),
      );

      await _pumpScreen(tester, repository: repo);

      expect(find.text('Action Items'), findsOneWidget);
      expect(find.text('Buy groceries'), findsOneWidget);
      expect(find.byKey(const Key('action-item-rec-1')), findsOneWidget);
    });

    testWidgets('renders routine items with templates', (tester) async {
      final repo = _StubRepository(
        response: AgendaResponse(
          date: '2026-04-19',
          granularity: 'day',
          from: '2026-04-19',
          to: '2026-04-19',
          items: [],
          routineItems: [
            const AgendaRoutineItem(
              routineId: 'rtn-1',
              routineName: 'Morning routine',
              scheduledFor: '2026-04-19',
              startTime: '08:00',
              overdue: false,
              status: OccurrenceStatus.pending,
              occurrenceId: 'occ-1',
              templates: [RoutineTemplate(text: 'Meditate', sortOrder: 0)],
            ),
          ],
        ),
      );

      await _pumpScreen(tester, repository: repo);

      expect(find.text('Routines'), findsOneWidget);
      expect(find.text('Morning routine'), findsOneWidget);
      expect(find.text('08:00'), findsOneWidget);

      // Expand to see templates
      await tester.tap(find.text('Morning routine'));
      await tester.pumpAndSettle();

      expect(find.text('Meditate'), findsOneWidget);
    });

    testWidgets('done items show strikethrough', (tester) async {
      final repo = _StubRepository(
        response: AgendaResponse(
          date: '2026-04-19',
          granularity: 'day',
          from: '2026-04-19',
          to: '2026-04-19',
          items: [
            const AgendaItem(
              recordId: 'rec-1',
              text: 'Done task',
              scheduledFor: '2026-04-19',
              timeWindow: TimeWindow.day,
              originRole: OriginRole.user,
              status: RecordStatus.done,
              linkedConversationCount: 0,
            ),
          ],
          routineItems: [],
        ),
      );

      await _pumpScreen(tester, repository: repo);

      final textWidget = tester.widget<Text>(find.text('Done task'));
      expect(
        textWidget.style?.decoration,
        TextDecoration.lineThrough,
      );
    });

    testWidgets('tapping previous day changes date', (tester) async {
      await _pumpScreen(tester);

      final beforeText = tester
          .widget<Text>(find.byKey(const Key('agenda-date-label')))
          .data!;

      await tester.tap(find.byKey(const Key('agenda-prev-day')));
      await tester.pumpAndSettle();

      final afterText = tester
          .widget<Text>(find.byKey(const Key('agenda-date-label')))
          .data!;

      expect(afterText, isNot(equals(beforeText)));
    });

    testWidgets('Today button is hidden when showing today', (tester) async {
      await _pumpScreen(tester);

      expect(find.byKey(const Key('agenda-today-btn')), findsNothing);
    });

    testWidgets('Today button appears after navigating to another day',
        (tester) async {
      await _pumpScreen(tester);

      await tester.tap(find.byKey(const Key('agenda-prev-day')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('agenda-today-btn')), findsOneWidget);
    });
  });
}
