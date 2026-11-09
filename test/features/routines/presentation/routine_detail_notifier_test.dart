import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/models/routine.dart';
import 'package:voice_agent/features/routines/domain/routine_detail_state.dart';
import 'package:voice_agent/features/routines/domain/routines_repository.dart';
import 'package:voice_agent/features/routines/presentation/routine_detail_notifier.dart';

import '../fake_routines_repository.dart';

void main() {
  late FakeRoutinesRepository repo;

  setUp(() {
    repo = FakeRoutinesRepository();
  });

  Future<RoutineDetailNotifier> loaded([String id = 'rtn-1']) async {
    final notifier = RoutineDetailNotifier(repo, id);
    await Future<void>.delayed(Duration.zero);
    return notifier;
  }

  group('RoutineDetailNotifier', () {
    test('loads the routine and its ticks', () async {
      repo.occurrences = [sampleOccurrence()];

      final notifier = await loaded();

      final state = notifier.state as RoutineDetailLoaded;
      expect(state.routine.id, 'rtn-1');
      expect(state.occurrences.single.id, 'occ-1');
    });

    test('transitions to error on fetch failure', () async {
      repo.fetchError = RoutinesGeneralException('Network error');

      final notifier = await loaded();

      expect(notifier.state, isA<RoutineDetailError>());
      expect((notifier.state as RoutineDetailError).message, 'Network error');
    });

    test('endRoutine is a PATCH of the last day, then a reload', () async {
      final notifier = await loaded();
      repo.calls.clear();

      expect(await notifier.endRoutine('2026-05-01'), isTrue);

      expect(repo.lastPatch!.toMap(), {'last_day': '2026-05-01'});
      expect(repo.calls, ['edit rtn-1', 'detail rtn-1']);
    });

    test('status changes reload on success and keep the error otherwise',
        () async {
      final notifier = await loaded();

      expect(await notifier.activateRoutine(), isTrue);
      expect(await notifier.pauseRoutine(), isTrue);
      expect(await notifier.archiveRoutine(), isTrue);
      expect(repo.calls,
          containsAllInOrder(['activate rtn-1', 'pause rtn-1', 'archive rtn-1']));

      repo.actionError = RoutineConflictException('archived is final');
      expect(await notifier.activateRoutine(), isFalse);
      expect(notifier.lastActionError, 'archived is final');

      repo.actionError = null;
      expect(await notifier.pauseRoutine(), isTrue);
      expect(notifier.lastActionError, isNull);
    });

    test('resolve ticks a one-off off without a day', () async {
      repo.detail = sampleRoutine(dueOn: '2026-11-10');
      final notifier = await loaded();

      expect(await notifier.resolve(OccurrenceStatus.done), isTrue);

      expect(repo.lastResolve,
          (routineId: 'rtn-1', day: null, status: OccurrenceStatus.done));
    });

    test('resolve gives the refusal of a paused routine', () async {
      repo.detail = sampleRoutine(kind: RoutineKind.someday);
      final notifier = await loaded();
      repo.actionError = RoutineNotActiveException('routine is paused');

      expect(await notifier.resolve(OccurrenceStatus.skipped), isFalse);
      expect(notifier.lastActionError, 'routine is paused');
    });

    test('undo of a recurring tick names its day', () async {
      final notifier = await loaded();

      expect(
          await notifier
              .undo(sampleOccurrence(scheduledFor: '2026-04-19')),
          isTrue);

      expect(repo.lastUnresolve, (routineId: 'rtn-1', day: '2026-04-19'));
    });

    test('undo of a one-off tick names no day', () async {
      repo.detail = sampleRoutine(dueOn: '2026-11-10');
      final notifier = await loaded();

      expect(await notifier.undo(sampleOccurrence()), isTrue);

      expect(repo.lastUnresolve, (routineId: 'rtn-1', day: null));
    });
  });
}
