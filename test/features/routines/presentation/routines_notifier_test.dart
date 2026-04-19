import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/models/routine.dart';
import 'package:voice_agent/features/routines/domain/routines_repository.dart';
import 'package:voice_agent/features/routines/domain/routines_state.dart';
import 'package:voice_agent/features/routines/presentation/routines_notifier.dart';

class _MockRepository implements RoutinesRepository {
  List<Routine> nextRoutines = [];
  List<RoutineProposal> nextProposals = [];
  Exception? fetchRoutinesError;
  Exception? fetchProposalsError;
  Exception? actionError;

  int fetchRoutinesCount = 0;
  int fetchProposalsCount = 0;
  RoutineStatus? lastFetchStatus;
  String? lastTriggerId;
  String? lastTriggerDate;
  String? lastActivateId;
  String? lastPauseId;
  String? lastApproveId;
  String? lastRejectId;

  @override
  Future<List<Routine>> fetchRoutines(RoutineStatus status) async {
    fetchRoutinesCount++;
    lastFetchStatus = status;
    if (fetchRoutinesError != null) throw fetchRoutinesError!;
    return nextRoutines;
  }

  @override
  Future<List<RoutineProposal>> fetchProposals() async {
    fetchProposalsCount++;
    if (fetchProposalsError != null) throw fetchProposalsError!;
    return nextProposals;
  }

  @override
  Future<Routine> fetchRoutineDetail(String id) async =>
      throw UnimplementedError();

  @override
  Future<List<RoutineOccurrence>> fetchOccurrences(String id) async =>
      throw UnimplementedError();

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
  Future<void> archiveRoutine(String id) async =>
      throw UnimplementedError();

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
  ) async =>
      throw UnimplementedError();

  @override
  Future<void> approveProposal(String proposalId) async {
    lastApproveId = proposalId;
    if (actionError != null) throw actionError!;
  }

  @override
  Future<void> rejectProposal(String proposalId) async {
    lastRejectId = proposalId;
    if (actionError != null) throw actionError!;
  }
}

Routine _sampleRoutine({String id = 'rtn-1', String name = 'Morning routine'}) =>
    Routine(
      id: id,
      sourceRecordId: 'src-1',
      name: name,
      rrule: 'FREQ=DAILY',
      cadence: 'daily',
      status: RoutineStatus.active,
      createdAt: DateTime(2026, 4, 1),
      updatedAt: DateTime(2026, 4, 18),
    );

RoutineProposal _sampleProposal({String id = 'prop-1'}) => RoutineProposal(
      id: id,
      name: 'Weekly review',
      cadence: 'weekly',
      items: const [RoutineProposalItem(text: 'Review items', sortOrder: 1)],
      confidence: 0.85,
      conversationId: 'conv-1',
      createdAt: DateTime(2026, 4, 18),
    );

void main() {
  late _MockRepository repo;

  setUp(() {
    repo = _MockRepository();
  });

  group('RoutinesNotifier', () {
    test('constructor triggers loadRoutines and transitions to loaded',
        () async {
      repo.nextRoutines = [_sampleRoutine()];
      repo.nextProposals = [_sampleProposal()];
      final notifier = RoutinesNotifier(repo);

      await Future<void>.delayed(Duration.zero);

      expect(notifier.state, isA<RoutinesLoaded>());
      final loaded = notifier.state as RoutinesLoaded;
      expect(loaded.routines, hasLength(1));
      expect(loaded.proposals, hasLength(1));
    });

    test('defaults to active status', () async {
      final notifier = RoutinesNotifier(repo);
      await Future<void>.delayed(Duration.zero);

      expect(notifier.selectedStatus, RoutineStatus.active);
      expect(repo.lastFetchStatus, RoutineStatus.active);
    });

    test('transitions to error on fetch failure', () async {
      repo.fetchRoutinesError = Exception('Network error');
      final notifier = RoutinesNotifier(repo);

      await Future<void>.delayed(Duration.zero);

      expect(notifier.state, isA<RoutinesError>());
      expect(
        (notifier.state as RoutinesError).message,
        contains('Network error'),
      );
    });

    test('proposals failure does not block routines loading', () async {
      repo.nextRoutines = [_sampleRoutine()];
      repo.fetchProposalsError = Exception('Proposals failed');
      final notifier = RoutinesNotifier(repo);

      await Future<void>.delayed(Duration.zero);

      expect(notifier.state, isA<RoutinesLoaded>());
      final loaded = notifier.state as RoutinesLoaded;
      expect(loaded.routines, hasLength(1));
      expect(loaded.proposals, isEmpty);
    });

    test('selectStatus changes tab and reloads routines', () async {
      final notifier = RoutinesNotifier(repo);
      await Future<void>.delayed(Duration.zero);

      repo.fetchRoutinesCount = 0;
      await notifier.selectStatus(RoutineStatus.draft);

      expect(notifier.selectedStatus, RoutineStatus.draft);
      expect(repo.lastFetchStatus, RoutineStatus.draft);
      expect(repo.fetchRoutinesCount, 1);
    });

    test('selectStatus retains cached proposals', () async {
      repo.nextProposals = [_sampleProposal()];
      final notifier = RoutinesNotifier(repo);
      await Future<void>.delayed(Duration.zero);

      await notifier.selectStatus(RoutineStatus.paused);

      final loaded = notifier.state as RoutinesLoaded;
      expect(loaded.proposals, hasLength(1));
    });

    test('selectStatus transitions to error on failure', () async {
      final notifier = RoutinesNotifier(repo);
      await Future<void>.delayed(Duration.zero);

      repo.fetchRoutinesError = Exception('Offline');
      await notifier.selectStatus(RoutineStatus.archived);

      expect(notifier.state, isA<RoutinesError>());
    });

    test('refresh reloads data', () async {
      final notifier = RoutinesNotifier(repo);
      await Future<void>.delayed(Duration.zero);

      repo.fetchRoutinesCount = 0;
      repo.fetchProposalsCount = 0;
      await notifier.refresh();

      expect(repo.fetchRoutinesCount, 1);
      expect(repo.fetchProposalsCount, 1);
      expect(notifier.state, isA<RoutinesLoaded>());
    });

    test('triggerRoutine returns true on success', () async {
      final notifier = RoutinesNotifier(repo);
      await Future<void>.delayed(Duration.zero);

      final result = await notifier.triggerRoutine('rtn-1', '2026-04-19');

      expect(result, isTrue);
      expect(repo.lastTriggerId, 'rtn-1');
      expect(repo.lastTriggerDate, '2026-04-19');
      expect(notifier.lastActionError, isNull);
    });

    test('triggerRoutine returns false on RoutineAlreadyTriggered', () async {
      final notifier = RoutinesNotifier(repo);
      await Future<void>.delayed(Duration.zero);

      repo.actionError = RoutineAlreadyTriggedException();
      final result = await notifier.triggerRoutine('rtn-1', '2026-04-19');

      expect(result, isFalse);
      expect(notifier.lastActionError, 'Already triggered for this date');
    });

    test('triggerRoutine returns false on general exception', () async {
      final notifier = RoutinesNotifier(repo);
      await Future<void>.delayed(Duration.zero);

      repo.actionError = RoutinesGeneralException('Server error');
      final result = await notifier.triggerRoutine('rtn-1', '2026-04-19');

      expect(result, isFalse);
      expect(notifier.lastActionError, 'Server error');
    });

    test('pauseRoutine returns true on success', () async {
      final notifier = RoutinesNotifier(repo);
      await Future<void>.delayed(Duration.zero);

      final result = await notifier.pauseRoutine('rtn-1');

      expect(result, isTrue);
      expect(repo.lastPauseId, 'rtn-1');
    });

    test('pauseRoutine returns false on failure', () async {
      final notifier = RoutinesNotifier(repo);
      await Future<void>.delayed(Duration.zero);

      repo.actionError = RoutinesGeneralException('Cannot pause');
      final result = await notifier.pauseRoutine('rtn-1');

      expect(result, isFalse);
      expect(notifier.lastActionError, 'Cannot pause');
    });

    test('activateRoutine returns true on success', () async {
      final notifier = RoutinesNotifier(repo);
      await Future<void>.delayed(Duration.zero);

      final result = await notifier.activateRoutine('rtn-1');

      expect(result, isTrue);
      expect(repo.lastActivateId, 'rtn-1');
    });

    test('activateRoutine returns false on failure', () async {
      final notifier = RoutinesNotifier(repo);
      await Future<void>.delayed(Duration.zero);

      repo.actionError = RoutinesGeneralException('Cannot activate');
      final result = await notifier.activateRoutine('rtn-1');

      expect(result, isFalse);
      expect(notifier.lastActionError, 'Cannot activate');
    });

    test('approveProposal returns true and reloads on success', () async {
      final notifier = RoutinesNotifier(repo);
      await Future<void>.delayed(Duration.zero);

      repo.fetchRoutinesCount = 0;
      repo.fetchProposalsCount = 0;
      final result = await notifier.approveProposal('prop-1');

      expect(result, isTrue);
      expect(repo.lastApproveId, 'prop-1');
      expect(repo.fetchRoutinesCount, 1);
      expect(repo.fetchProposalsCount, 1);
    });

    test('approveProposal returns false on failure', () async {
      final notifier = RoutinesNotifier(repo);
      await Future<void>.delayed(Duration.zero);

      repo.actionError = RoutinesGeneralException('Approve failed');
      final result = await notifier.approveProposal('prop-1');

      expect(result, isFalse);
      expect(notifier.lastActionError, 'Approve failed');
    });

    test('rejectProposal returns true and reloads on success', () async {
      final notifier = RoutinesNotifier(repo);
      await Future<void>.delayed(Duration.zero);

      repo.fetchRoutinesCount = 0;
      final result = await notifier.rejectProposal('prop-1');

      expect(result, isTrue);
      expect(repo.lastRejectId, 'prop-1');
      expect(repo.fetchRoutinesCount, 1);
    });

    test('rejectProposal returns false on failure', () async {
      final notifier = RoutinesNotifier(repo);
      await Future<void>.delayed(Duration.zero);

      repo.actionError = RoutinesGeneralException('Reject failed');
      final result = await notifier.rejectProposal('prop-1');

      expect(result, isFalse);
      expect(notifier.lastActionError, 'Reject failed');
    });

    test('lastActionError clears on new action', () async {
      final notifier = RoutinesNotifier(repo);
      await Future<void>.delayed(Duration.zero);

      repo.actionError = RoutinesGeneralException('Error');
      await notifier.triggerRoutine('rtn-1', '2026-04-19');
      expect(notifier.lastActionError, 'Error');

      repo.actionError = null;
      await notifier.pauseRoutine('rtn-1');
      expect(notifier.lastActionError, isNull);
    });
  });
}
