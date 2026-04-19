import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/models/agenda.dart';
import 'package:voice_agent/core/models/conversation_record.dart';
import 'package:voice_agent/core/models/routine.dart';
import 'package:voice_agent/features/agenda/domain/agenda_repository.dart';
import 'package:voice_agent/features/agenda/domain/agenda_state.dart';
import 'package:voice_agent/features/agenda/presentation/agenda_notifier.dart';

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

void main() {
  late _MockRepository repo;

  setUp(() {
    repo = _MockRepository();
  });

  group('AgendaNotifier', () {
    test('constructor triggers loadAgenda and transitions to loaded',
        () async {
      repo.nextFetchResult = _responseWithItems();
      final notifier = AgendaNotifier(repo);

      // Wait for async load
      await Future<void>.delayed(Duration.zero);

      expect(notifier.state, isA<AgendaLoaded>());
      final loaded = notifier.state as AgendaLoaded;
      expect(loaded.response.items, hasLength(1));
      expect(loaded.response.routineItems, hasLength(1));
    });

    test('transitions to error on fetch failure', () async {
      repo.fetchError = Exception('Network error');
      final notifier = AgendaNotifier(repo);

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
      final notifier = AgendaNotifier(repo);

      await Future<void>.delayed(Duration.zero);

      expect(notifier.state, isA<AgendaError>());
      final errorState = notifier.state as AgendaError;
      expect(errorState.cached, isNotNull);
      expect(errorState.cached!.response.items, hasLength(1));
    });

    test('selectDate changes date and triggers reload', () async {
      final notifier = AgendaNotifier(repo);
      await Future<void>.delayed(Duration.zero);

      repo.fetchCount = 0;
      notifier.selectDate(DateTime(2026, 4, 20));
      await Future<void>.delayed(Duration.zero);

      expect(notifier.selectedDate, DateTime(2026, 4, 20));
      expect(repo.fetchCount, 1);
    });

    test('previousDay moves back one day', () async {
      final notifier = AgendaNotifier(repo);
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
      final notifier = AgendaNotifier(repo);
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
      final notifier = AgendaNotifier(repo);
      await Future<void>.delayed(Duration.zero);

      notifier.selectDate(DateTime(2025, 1, 1));
      await Future<void>.delayed(Duration.zero);

      notifier.goToToday();
      await Future<void>.delayed(Duration.zero);

      expect(notifier.isToday, isTrue);
    });

    test('markDone calls repository and returns true on success', () async {
      final notifier = AgendaNotifier(repo);
      await Future<void>.delayed(Duration.zero);

      final result = await notifier.markDone('rec-1');

      expect(result, isTrue);
      expect(repo.lastMarkDoneId, 'rec-1');
    });

    test('markDone returns false on failure', () async {
      final notifier = AgendaNotifier(repo);
      await Future<void>.delayed(Duration.zero);

      repo.actionError = Exception('Server error');
      final result = await notifier.markDone('rec-1');

      expect(result, isFalse);
    });

    test('skipOccurrence calls repository with skipped status', () async {
      final notifier = AgendaNotifier(repo);
      await Future<void>.delayed(Duration.zero);

      final result = await notifier.skipOccurrence('rtn-1', 'occ-1');

      expect(result, isTrue);
      expect(repo.lastUpdateRoutineId, 'rtn-1');
      expect(repo.lastUpdateOccurrenceId, 'occ-1');
      expect(repo.lastUpdateStatus, OccurrenceStatus.skipped);
    });

    test('completeOccurrence calls repository with done status', () async {
      final notifier = AgendaNotifier(repo);
      await Future<void>.delayed(Duration.zero);

      final result = await notifier.completeOccurrence('rtn-1', 'occ-1');

      expect(result, isTrue);
      expect(repo.lastUpdateStatus, OccurrenceStatus.done);
    });

    test('skipOccurrence returns false on failure', () async {
      final notifier = AgendaNotifier(repo);
      await Future<void>.delayed(Duration.zero);

      repo.actionError = Exception('Offline');
      final result = await notifier.skipOccurrence('rtn-1', 'occ-1');

      expect(result, isFalse);
    });

    test('refresh reloads data', () async {
      final notifier = AgendaNotifier(repo);
      await Future<void>.delayed(Duration.zero);

      repo.fetchCount = 0;
      await notifier.refresh();

      expect(repo.fetchCount, 1);
      expect(notifier.state, isA<AgendaLoaded>());
    });
  });
}
