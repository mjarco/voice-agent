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

  final resolved = <String>[];
  AgendaException? resolveError;

  @override
  Future<void> resolveOccurrence(
    String routineId,
    String scheduledFor,
    OccurrenceStatus status,
  ) async {
    if (!updateStatusSuccess) throw Exception('Failed');
    if (resolveError != null) throw resolveError!;
    resolved.add('$routineId $scheduledFor ${status.toJson()}');
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
      GoRoute(path: '/', builder: (context, state) => const AgendaScreen()),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const Scaffold(body: Text('Settings')),
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
        find.descendant(of: find.byType(AppBar), matching: find.text('Agenda')),
        findsOneWidget,
      );
    });

    testWidgets('renders gear icon that navigates to settings', (tester) async {
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

    testWidgets('renders meetings first, without a checkbox', (tester) async {
      final repo = _StubRepository(
        response: const AgendaResponse(
          date: '2026-04-19',
          granularity: 'day',
          from: '2026-04-19',
          to: '2026-04-19',
          items: [],
          routineItems: [],
          calendarItems: [
            AgendaCalendarItem(
              calendar: 'CORP',
              uid: 'su',
              title: 'Stand-up',
              start: '2026-04-19T09:00:00+02:00',
              end: '2026-04-19T09:30:00+02:00',
              allDay: false,
            ),
            AgendaCalendarItem(
              calendar: 'FAMI',
              uid: 'trip',
              title: 'Trip',
              start: '2026-04-18',
              end: '2026-04-20',
              allDay: true,
            ),
          ],
        ),
      );

      await _pumpScreen(tester, repository: repo);

      expect(find.text('Meetings'), findsOneWidget);
      expect(find.text('Stand-up'), findsOneWidget);
      expect(find.text('09:00–09:30'), findsOneWidget);
      expect(find.text('2026-04-18 – 2026-04-20'), findsOneWidget);
      expect(find.text('CORP'), findsOneWidget);
      expect(find.text('No items for this date'), findsNothing);
      expect(find.byType(Checkbox), findsNothing);
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
      expect(textWidget.style?.decoration, TextDecoration.lineThrough);
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

    testWidgets('Today button appears after navigating to another day', (
      tester,
    ) async {
      await _pumpScreen(tester);

      await tester.tap(find.byKey(const Key('agenda-prev-day')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('agenda-today-btn')), findsOneWidget);
    });

    AgendaResponse routineAgenda(List<AgendaRoutineItem> items) =>
        AgendaResponse(
          date: '2026-10-26',
          granularity: 'day',
          from: '2026-10-26',
          to: '2026-10-26',
          items: [],
          routineItems: items,
        );

    const waiting = AgendaRoutineItem(
      routineId: 'rtn-inv',
      routineName: 'Invoice',
      scheduledFor: '2026-09-10',
      overdue: true,
      status: OccurrenceStatus.pending,
      templates: [],
    );

    testWidgets(
      'a routine row without a stored occurrence is ticked off through resolve (#363)',
      (tester) async {
        final repo = _StubRepository(response: routineAgenda([waiting]));
        await _pumpScreen(tester, repository: repo);

        expect(find.byKey(const Key('routine-since-rtn-inv')), findsOneWidget);
        expect(find.text('since 2026-09-10'), findsOneWidget);

        await tester.tap(find.text('Invoice'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('routine-complete-rtn-inv')));
        await tester.pumpAndSettle();

        expect(repo.resolved, ['rtn-inv 2026-09-10 done']);
      },
    );

    testWidgets('a refused tick-off shows its reason', (tester) async {
      final repo = _StubRepository(response: routineAgenda([waiting]))
        ..resolveError = AgendaException('Server error 409', statusCode: 409);
      await _pumpScreen(tester, repository: repo);

      await tester.tap(find.text('Invoice'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('routine-complete-rtn-inv')));
      await tester.pumpAndSettle();

      expect(find.text('Already done'), findsOneWidget);
    });

    testWidgets('a peer-mirrored row and a today row', (tester) async {
      final repo = _StubRepository(
        response: routineAgenda([
          const AgendaRoutineItem(
            routineId: 'rtn-peer',
            routineName: 'Upstream walk',
            scheduledFor: '2026-10-26',
            overdue: false,
            status: OccurrenceStatus.pending,
            templates: [],
            peerId: 'upstream',
          ),
        ]),
      );
      await _pumpScreen(tester, repository: repo);

      expect(find.textContaining('since'), findsNothing);
      await tester.tap(find.text('Upstream walk'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('routine-complete-rtn-peer')), findsNothing);
    });
  });
}
