import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
import 'package:voice_agent/core/providers/session_active_provider.dart';
import 'package:voice_agent/features/agenda/domain/agenda_repository.dart';
import 'package:voice_agent/features/agenda/domain/agenda_state.dart';
import 'package:voice_agent/features/agenda/presentation/agenda_notifier.dart';
import 'package:voice_agent/features/agenda/presentation/agenda_providers.dart';

class _MockRepository implements AgendaRepository {
  AgendaResponse? nextFetchResult;
  CachedAgenda? nextCachedResult;
  Exception? fetchError;
  Exception? actionError;

  int fetchCount = 0;
  String? lastMarkDoneId;
  String? lastUpdateRoutineId;
  String? lastUpdateOccurrenceId;
  OccurrenceStatus? lastUpdateStatus;

  AgendaResponse _defaultResponse(String date) => AgendaResponse(
        date: date,
        granularity: 'day',
        from: date,
        to: date,
        items: [],
        routineItems: [],
      );

  @override
  Future<AgendaResponse> fetchAgenda(String date) async {
    fetchCount++;
    if (fetchError != null) throw fetchError!;
    return nextFetchResult ?? _defaultResponse(date);
  }

  @override
  Future<CachedAgenda?> getCachedAgenda(String date) async => nextCachedResult;

  @override
  Future<void> cacheAgenda(String date, AgendaResponse response) async {}

  @override
  Future<void> markActionItemDone(String recordId) async {
    lastMarkDoneId = recordId;
    if (actionError != null) throw actionError!;
  }

  @override
  Future<void> updateOccurrenceStatus(
    String routineId,
    String occurrenceId,
    OccurrenceStatus status,
  ) async {
    lastUpdateRoutineId = routineId;
    lastUpdateOccurrenceId = occurrenceId;
    lastUpdateStatus = status;
    if (actionError != null) throw actionError!;
  }
}

AgendaResponse _responseWithItems() => AgendaResponse(
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
    );

/// Minimal in-memory NotificationService for tests (mirrors the production
/// snapshot semantics so the scheduler diff behaves realistically).
class _FakeNotificationService implements NotificationService {
  final Map<int, ScheduledNotification> _snapshot = {};
  bool permitted = true;

  Map<int, ScheduledNotification> get snapshot => Map.unmodifiable(_snapshot);

  @override
  Future<void> init() async {}
  @override
  Future<bool> requestPermission() async => permitted;
  @override
  Future<bool> isPermitted() async => permitted;
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    tz_data.initializeTimeZones();
  });

  late _MockRepository repo;
  late _FakeNotificationService notifications;
  late AppConfigService configService;
  late ProviderContainer container;

  setUp(() {
    // Mock SharedPreferences (no platform plugin in the unit harness).
    SharedPreferences.setMockInitialValues({});

    repo = _MockRepository();
    notifications = _FakeNotificationService();
    configService = AppConfigService();
    final scheduler = AgendaNotificationScheduler(
      service: notifications,
      location: tz.local,
      clock: DateTime.now,
    );
    container = ProviderContainer(
      overrides: [
        agendaRepositoryProvider.overrideWithValue(repo),
        notificationServiceProvider.overrideWithValue(notifications),
        agendaNotificationSchedulerProvider.overrideWithValue(scheduler),
        appConfigServiceProvider.overrideWithValue(configService),
      ],
    );
  });

  tearDown(() {
    container.dispose();
  });

  AgendaNotifier buildNotifier() =>
      container.read(agendaNotifierProvider.notifier);

  group('AgendaNotifier', () {
    test('constructor triggers loadAgenda and transitions to loaded',
        () async {
      repo.nextFetchResult = _responseWithItems();
      final notifier = buildNotifier();

      // Wait for async load
      await Future<void>.delayed(Duration.zero);

      expect(notifier.state, isA<AgendaLoaded>());
      final loaded = notifier.state as AgendaLoaded;
      expect(loaded.response.items, hasLength(1));
      expect(loaded.response.routineItems, hasLength(1));
    });

    test('transitions to error on fetch failure', () async {
      repo.fetchError = Exception('Network error');
      final notifier = buildNotifier();

      await Future<void>.delayed(Duration.zero);

      expect(notifier.state, isA<AgendaError>());
      expect((notifier.state as AgendaError).message, contains('Network error'));
    });

    test('error state carries cached data', () async {
      final cached = CachedAgenda(
        response: _responseWithItems(),
        fetchedAt: DateTime(2026, 4, 19, 10, 0),
      );
      repo.nextCachedResult = cached;
      repo.fetchError = Exception('Offline');
      final notifier = buildNotifier();

      await Future<void>.delayed(Duration.zero);

      expect(notifier.state, isA<AgendaError>());
      final errorState = notifier.state as AgendaError;
      expect(errorState.cached, isNotNull);
      expect(errorState.cached!.response.items, hasLength(1));
    });

    test('selectDate changes date and triggers reload', () async {
      final notifier = buildNotifier();
      await Future<void>.delayed(Duration.zero);

      repo.fetchCount = 0;
      notifier.selectDate(DateTime(2026, 4, 20));
      await Future<void>.delayed(Duration.zero);

      expect(notifier.selectedDate, DateTime(2026, 4, 20));
      expect(repo.fetchCount, 1);
    });

    test('previousDay moves back one day', () async {
      final notifier = buildNotifier();
      await Future<void>.delayed(Duration.zero);

      final before = notifier.selectedDate;
      notifier.previousDay();
      await Future<void>.delayed(Duration.zero);

      expect(
        notifier.selectedDate,
        DateTime(before.year, before.month, before.day - 1),
      );
    });

    test('nextDay moves forward one day', () async {
      final notifier = buildNotifier();
      await Future<void>.delayed(Duration.zero);

      final before = notifier.selectedDate;
      notifier.nextDay();
      await Future<void>.delayed(Duration.zero);

      expect(
        notifier.selectedDate,
        DateTime(before.year, before.month, before.day + 1),
      );
    });

    test('goToToday resets to current date', () async {
      final notifier = buildNotifier();
      await Future<void>.delayed(Duration.zero);

      notifier.selectDate(DateTime(2025, 1, 1));
      await Future<void>.delayed(Duration.zero);

      notifier.goToToday();
      await Future<void>.delayed(Duration.zero);

      expect(notifier.isToday, isTrue);
    });

    test('markDone calls repository and returns true on success', () async {
      final notifier = buildNotifier();
      await Future<void>.delayed(Duration.zero);

      final result = await notifier.markDone('rec-1');

      expect(result, isTrue);
      expect(repo.lastMarkDoneId, 'rec-1');
    });

    test('markDone returns false on failure', () async {
      final notifier = buildNotifier();
      await Future<void>.delayed(Duration.zero);

      repo.actionError = Exception('Server error');
      final result = await notifier.markDone('rec-1');

      expect(result, isFalse);
    });

    test('skipOccurrence calls repository with skipped status', () async {
      final notifier = buildNotifier();
      await Future<void>.delayed(Duration.zero);

      final result = await notifier.skipOccurrence('rtn-1', 'occ-1');

      expect(result, isTrue);
      expect(repo.lastUpdateRoutineId, 'rtn-1');
      expect(repo.lastUpdateOccurrenceId, 'occ-1');
      expect(repo.lastUpdateStatus, OccurrenceStatus.skipped);
    });

    test('completeOccurrence calls repository with done status', () async {
      final notifier = buildNotifier();
      await Future<void>.delayed(Duration.zero);

      final result = await notifier.completeOccurrence('rtn-1', 'occ-1');

      expect(result, isTrue);
      expect(repo.lastUpdateStatus, OccurrenceStatus.done);
    });

    test('skipOccurrence returns false on failure', () async {
      final notifier = buildNotifier();
      await Future<void>.delayed(Duration.zero);

      repo.actionError = Exception('Offline');
      final result = await notifier.skipOccurrence('rtn-1', 'occ-1');

      expect(result, isFalse);
    });

    test('refresh reloads data', () async {
      final notifier = buildNotifier();
      await Future<void>.delayed(Duration.zero);

      repo.fetchCount = 0;
      await notifier.refresh();

      expect(repo.fetchCount, 1);
      expect(notifier.state, isA<AgendaLoaded>());
    });
  });

  // ── P040: reconcile firing conditions and session-edge wiring ──────────
  //
  // The proposal (§Reconciler Triggers, §Session Gating) defines explicit
  // rules for when the reconciler runs. These tests pin them down at the
  // notifier level so a regression (e.g., firing on non-today, firing from
  // error state) is caught at CI.

  group('P040 reconcile firing conditions', () {
    test('reconcile fires after loaded(today)', () async {
      // Default _MockRepository.fetchAgenda returns today's date string from
      // the notifier's _dateString getter, which uses DateTime.now → "today".
      repo.nextFetchResult = _responseWithItems();
      buildNotifier();
      await Future<void>.delayed(Duration.zero);

      // The pure scheduler always writes the 4 summary IDs at minimum.
      expect(notifications.snapshot.keys, containsAll([1000, 1001, 1002, 1003]),
          reason: 'reconciler should have scheduled the 4 daily summaries');
    });

    test('reconcile does NOT fire on error(cached)', () async {
      final cached = CachedAgenda(
        response: _responseWithItems(),
        fetchedAt: DateTime(2026, 4, 19, 10, 0),
      );
      repo.nextCachedResult = cached;
      repo.fetchError = Exception('Offline');

      buildNotifier();
      await Future<void>.delayed(Duration.zero);

      expect(notifications.snapshot, isEmpty,
          reason: 'stale cache must not drive OS notification scheduling');
    });

    test('reconcile does NOT fire on loaded(non-today)', () async {
      repo.nextFetchResult = _responseWithItems();
      final notifier = buildNotifier();
      await Future<void>.delayed(Duration.zero);

      // Clear what initial today-load scheduled.
      await notifications.cancelAll();

      // Navigate to a non-today date.
      notifier.selectDate(DateTime(2030, 1, 1));
      await Future<void>.delayed(Duration.zero);

      expect(notifications.snapshot, isEmpty,
          reason: 'non-today responses are for browsing, not scheduling');
    });

    test('lastAgendaFetchAt is persisted after loaded', () async {
      final before = DateTime.now();
      buildNotifier();
      // Allow the fire-and-forget setLastAgendaFetchAt write to complete.
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final saved = await configService.getLastAgendaFetchAt();
      expect(saved, isNotNull,
          reason: 'P040 §Reconciler Triggers #2 + bg 50-min skip guard '
              'both depend on this timestamp');
      expect(saved!.isAfter(before.subtract(const Duration(seconds: 1))),
          isTrue);
    });
  });

  group('P040 session-edge wiring', () {
    test('session edge true→false triggers refresh (fetch + reconcile)',
        () async {
      buildNotifier();
      await Future<void>.delayed(Duration.zero);

      // Force the listener to observe a transition. ref.listen ignores the
      // initial value but fires on subsequent changes.
      container.read(sessionActiveProvider.notifier).state = true;
      await Future<void>.delayed(Duration.zero);
      repo.fetchCount = 0;

      // The edge of interest:
      container.read(sessionActiveProvider.notifier).state = false;
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(repo.fetchCount, greaterThan(0),
          reason: 'true→false edge must call refresh() which re-fetches');
    });

    test('session edge false→true triggers reconcile-only (no fetch)',
        () async {
      repo.nextFetchResult = _responseWithItems();
      buildNotifier();
      await Future<void>.delayed(Duration.zero);
      // Snapshot is now populated with summaries (and a routine reminder).
      repo.fetchCount = 0;

      container.read(sessionActiveProvider.notifier).state = true;
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(repo.fetchCount, 0,
          reason: 'false→true edge must NOT re-fetch; it reconciles cached');
    });
  });
}
