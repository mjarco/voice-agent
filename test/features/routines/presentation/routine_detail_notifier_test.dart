import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/models/routine.dart';
import 'package:voice_agent/features/routines/domain/routine_detail_state.dart';
import 'package:voice_agent/features/routines/domain/routines_repository.dart';
import 'package:voice_agent/features/routines/presentation/routine_detail_notifier.dart';

class _MockRepository implements RoutinesRepository {
  Routine? nextRoutine;
  List<RoutineOccurrence> nextOccurrences = [];
  Exception? fetchError;
  Exception? actionError;

  int fetchDetailCount = 0;
  int fetchOccurrencesCount = 0;
  String? lastActivateId;
  String? lastPauseId;
  String? lastArchiveId;
  String? lastTriggerId;
  String? lastTriggerDate;
  String? lastUpdateRoutineId;
  String? lastUpdateOccurrenceId;
  OccurrenceStatus? lastUpdateStatus;

  @override
  Future<Routine> fetchRoutineDetail(String id) async {
    fetchDetailCount++;
    if (fetchError != null) throw fetchError!;
    return nextRoutine ?? _defaultRoutine(id);
  }

  @override
  Future<List<RoutineOccurrence>> fetchOccurrences(String id) async {
    fetchOccurrencesCount++;
    if (fetchError != null) throw fetchError!;
    return nextOccurrences;
  }

  @override
  Future<void> activateRoutine(String id) async {
    lastActivateId = id;
    if (actionError != null) throw actionError!;
  }

  @override
  Future<void> pauseRoutine(String id) async {
    lastPauseId = id;
    if (actionError != null) throw actionError!;
  }

  @override
  Future<void> archiveRoutine(String id) async {
    lastArchiveId = id;
    if (actionError != null) throw actionError!;
  }

  @override
  Future<void> triggerRoutine(String id, String scheduledFor) async {
    lastTriggerId = id;
    lastTriggerDate = scheduledFor;
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

  @override
  Future<List<Routine>> fetchRoutines(RoutineStatus status) async => [];

  @override
  Future<List<RoutineProposal>> fetchProposals() async => [];

  @override
  Future<void> approveProposal(String proposalId) async {}

  @override
  Future<void> rejectProposal(String proposalId) async {}

  Routine _defaultRoutine(String id) => Routine(
        id: id,
        sourceRecordId: 'src-1',
        name: 'Test routine',
        rrule: 'FREQ=DAILY',
        cadence: 'daily',
        status: RoutineStatus.active,
        templates: const [RoutineTemplate(text: 'Item 1', sortOrder: 1)],
        createdAt: DateTime(2026, 4, 1),
        updatedAt: DateTime(2026, 4, 18),
      );
}

RoutineOccurrence _sampleOccurrence({
  String id = 'occ-1',
  OccurrenceStatus status = OccurrenceStatus.pending,
}) =>
    RoutineOccurrence(
      id: id,
      routineId: 'rtn-1',
      scheduledFor: '2026-04-19',
      timeWindow: TimeWindow.day,
      status: status,
      createdAt: DateTime(2026, 4, 19),
      updatedAt: DateTime(2026, 4, 19),
    );

void main() {
  late _MockRepository repo;

  setUp(() {
    repo = _MockRepository();
  });

  group('RoutineDetailNotifier', () {
    test('constructor triggers loadDetail and transitions to loaded', () async {
      repo.nextOccurrences = [_sampleOccurrence()];
      final notifier = RoutineDetailNotifier(repo, 'rtn-1');

      await Future<void>.delayed(Duration.zero);

      expect(notifier.state, isA<RoutineDetailLoaded>());
      final loaded = notifier.state as RoutineDetailLoaded;
      expect(loaded.routine.id, 'rtn-1');
      expect(loaded.occurrences, hasLength(1));
    });

    test('transitions to error on fetch failure', () async {
      repo.fetchError = Exception('Network error');
      final notifier = RoutineDetailNotifier(repo, 'rtn-1');

      await Future<void>.delayed(Duration.zero);

      expect(notifier.state, isA<RoutineDetailError>());
      expect(
        (notifier.state as RoutineDetailError).message,
        contains('Network error'),
      );
    });

    test('fetches both detail and occurrences', () async {
      RoutineDetailNotifier(repo, 'rtn-1');
      await Future<void>.delayed(Duration.zero);

      expect(repo.fetchDetailCount, 1);
      expect(repo.fetchOccurrencesCount, 1);
    });

    test('refresh reloads data', () async {
      final notifier = RoutineDetailNotifier(repo, 'rtn-1');
      await Future<void>.delayed(Duration.zero);

      repo.fetchDetailCount = 0;
      repo.fetchOccurrencesCount = 0;
      await notifier.refresh();

      expect(repo.fetchDetailCount, 1);
      expect(repo.fetchOccurrencesCount, 1);
    });

    test('activateRoutine returns true and reloads on success', () async {
      final notifier = RoutineDetailNotifier(repo, 'rtn-1');
      await Future<void>.delayed(Duration.zero);

      repo.fetchDetailCount = 0;
      final result = await notifier.activateRoutine();

      expect(result, isTrue);
      expect(repo.lastActivateId, 'rtn-1');
      expect(repo.fetchDetailCount, 1);
    });

    test('activateRoutine returns false on conflict', () async {
      final notifier = RoutineDetailNotifier(repo, 'rtn-1');
      await Future<void>.delayed(Duration.zero);

      repo.actionError = RoutineConflictException('Already active');
      final result = await notifier.activateRoutine();

      expect(result, isFalse);
      expect(notifier.lastActionError, 'Already active');
    });

    test('pauseRoutine returns true on success', () async {
      final notifier = RoutineDetailNotifier(repo, 'rtn-1');
      await Future<void>.delayed(Duration.zero);

      final result = await notifier.pauseRoutine();

      expect(result, isTrue);
      expect(repo.lastPauseId, 'rtn-1');
    });

    test('pauseRoutine returns false on failure', () async {
      final notifier = RoutineDetailNotifier(repo, 'rtn-1');
      await Future<void>.delayed(Duration.zero);

      repo.actionError = RoutinesGeneralException('Cannot pause');
      final result = await notifier.pauseRoutine();

      expect(result, isFalse);
      expect(notifier.lastActionError, 'Cannot pause');
    });

    test('archiveRoutine returns true on success', () async {
      final notifier = RoutineDetailNotifier(repo, 'rtn-1');
      await Future<void>.delayed(Duration.zero);

      final result = await notifier.archiveRoutine();

      expect(result, isTrue);
      expect(repo.lastArchiveId, 'rtn-1');
    });

    test('archiveRoutine returns false on conflict', () async {
      final notifier = RoutineDetailNotifier(repo, 'rtn-1');
      await Future<void>.delayed(Duration.zero);

      repo.actionError = RoutineConflictException('Already archived');
      final result = await notifier.archiveRoutine();

      expect(result, isFalse);
      expect(notifier.lastActionError, 'Already archived');
    });

    test('triggerRoutine returns true on success', () async {
      final notifier = RoutineDetailNotifier(repo, 'rtn-1');
      await Future<void>.delayed(Duration.zero);

      final result = await notifier.triggerRoutine('2026-04-19');

      expect(result, isTrue);
      expect(repo.lastTriggerId, 'rtn-1');
      expect(repo.lastTriggerDate, '2026-04-19');
    });

    test('triggerRoutine returns false on already triggered', () async {
      final notifier = RoutineDetailNotifier(repo, 'rtn-1');
      await Future<void>.delayed(Duration.zero);

      repo.actionError = RoutineAlreadyTriggedException();
      final result = await notifier.triggerRoutine('2026-04-19');

      expect(result, isFalse);
      expect(notifier.lastActionError, 'Already triggered for this date');
    });

    test('updateOccurrenceStatus returns true on success', () async {
      final notifier = RoutineDetailNotifier(repo, 'rtn-1');
      await Future<void>.delayed(Duration.zero);

      final result = await notifier.updateOccurrenceStatus(
          'occ-1', OccurrenceStatus.done);

      expect(result, isTrue);
      expect(repo.lastUpdateRoutineId, 'rtn-1');
      expect(repo.lastUpdateOccurrenceId, 'occ-1');
      expect(repo.lastUpdateStatus, OccurrenceStatus.done);
    });

    test('updateOccurrenceStatus returns false on failure', () async {
      final notifier = RoutineDetailNotifier(repo, 'rtn-1');
      await Future<void>.delayed(Duration.zero);

      repo.actionError = RoutinesGeneralException('Failed');
      final result = await notifier.updateOccurrenceStatus(
          'occ-1', OccurrenceStatus.skipped);

      expect(result, isFalse);
      expect(notifier.lastActionError, 'Failed');
    });

    test('lastActionError clears on new action', () async {
      final notifier = RoutineDetailNotifier(repo, 'rtn-1');
      await Future<void>.delayed(Duration.zero);

      repo.actionError = RoutinesGeneralException('Error');
      await notifier.pauseRoutine();
      expect(notifier.lastActionError, 'Error');

      repo.actionError = null;
      await notifier.activateRoutine();
      expect(notifier.lastActionError, isNull);
    });
  });
}
