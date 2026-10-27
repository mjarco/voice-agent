import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/models/routine.dart';
import 'package:voice_agent/features/routines/domain/routines_repository.dart';
import 'package:voice_agent/features/routines/domain/routines_state.dart';
import 'package:voice_agent/features/routines/presentation/routines_notifier.dart';

import '../fake_routines_repository.dart';

void main() {
  late FakeRoutinesRepository repo;

  setUp(() {
    repo = FakeRoutinesRepository();
  });

  Future<RoutinesNotifier> loaded() async {
    final notifier = RoutinesNotifier(repo);
    await Future<void>.delayed(Duration.zero);
    return notifier;
  }

  List<String> ids(RoutinesNotifier n) =>
      (n.state as RoutinesLoaded).routines.map((r) => r.id).toList();

  group('RoutinesNotifier', () {
    test('Active lists active and draft routines that have not ended',
        () async {
      repo.byStatus[RoutineStatus.active] = [
        sampleRoutine(id: 'a1'),
        sampleRoutine(id: 'a-ended', ended: true),
      ];
      repo.byStatus[RoutineStatus.draft] = [
        sampleRoutine(id: 'd1', status: RoutineStatus.draft),
      ];

      final notifier = await loaded();

      expect(notifier.selectedTab, RoutinesTab.active);
      expect(ids(notifier), ['a1', 'd1']);
    });

    test('Active keeps a version an edit replaces until it ends', () async {
      repo.byStatus[RoutineStatus.active] = [
        sampleRoutine(id: 'old', nextRoutineId: 'new'),
        sampleRoutine(id: 'new', previousRoutineId: 'old'),
      ];

      final notifier = await loaded();

      expect(ids(notifier), ['old', 'new']);
    });

    test('Paused lists paused routines that have not ended', () async {
      repo.byStatus[RoutineStatus.paused] = [
        sampleRoutine(id: 'p1', status: RoutineStatus.paused),
        sampleRoutine(id: 'p-ended', status: RoutineStatus.paused, ended: true),
      ];
      final notifier = await loaded();

      await notifier.selectTab(RoutinesTab.paused);

      expect(ids(notifier), ['p1']);
    });

    test('Ended lists ended and archived routines, not replaced versions',
        () async {
      repo.byStatus[RoutineStatus.active] = [
        sampleRoutine(id: 'live'),
        sampleRoutine(id: 'ended', ended: true),
        sampleRoutine(id: 'replaced', ended: true, nextRoutineId: 'x'),
      ];
      repo.byStatus[RoutineStatus.paused] = [
        sampleRoutine(id: 'p-ended', status: RoutineStatus.paused, ended: true),
      ];
      repo.byStatus[RoutineStatus.archived] = [
        sampleRoutine(id: 'arch', status: RoutineStatus.archived),
      ];
      final notifier = await loaded();

      await notifier.selectTab(RoutinesTab.ended);

      expect(ids(notifier), ['ended', 'p-ended', 'arch']);
      expect(repo.fetchedStatuses, containsAll(RoutineStatus.values));
    });

    test('transitions to error on fetch failure', () async {
      repo.fetchError = RoutinesGeneralException('Network error');

      final notifier = await loaded();

      expect(notifier.state, isA<RoutinesError>());
      expect((notifier.state as RoutinesError).message, 'Network error');
    });

    test('pauseRoutine reloads on success', () async {
      final notifier = await loaded();

      expect(await notifier.pauseRoutine('a1'), isTrue);
      expect(repo.calls, ['pause a1']);
      expect(notifier.state, isA<RoutinesLoaded>());
    });

    test('activateRoutine returns false with the error on failure', () async {
      final notifier = await loaded();
      repo.actionError = RoutineConflictException('Invalid transition');

      expect(await notifier.activateRoutine('p1'), isFalse);
      expect(notifier.lastActionError, 'Invalid transition');
    });
  });
}
