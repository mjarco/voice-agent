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

  List<String> ids(List<Routine> routines) =>
      routines.map((r) => r.id).toList();

  group('RoutinesNotifier', () {
    test('loads every routine once and groups them in sections', () async {
      repo.routines = [
        sampleRoutine(id: 'rec'),
        sampleRoutine(id: 'rec-ended', ended: true),
        sampleRoutine(id: 'task-late', dueOn: '2026-11-20'),
        sampleRoutine(id: 'task-soon', dueOn: '2026-11-10'),
        sampleRoutine(id: 'some', kind: RoutineKind.someday),
        sampleRoutine(
            id: 'some-done',
            kind: RoutineKind.someday,
            ended: true,
            updatedAt: DateTime(2026, 11, 1)),
        sampleRoutine(id: 'paused', status: RoutineStatus.paused),
        sampleRoutine(
            id: 'paused-task',
            dueOn: '2026-11-10',
            status: RoutineStatus.paused),
        sampleRoutine(id: 'arch', status: RoutineStatus.archived),
      ];

      final notifier = await loaded();

      expect(repo.fetchCount, 1);
      final sections = (notifier.state as RoutinesLoaded).sections;
      expect(ids(sections.recurring), ['rec']);
      expect(ids(sections.tasks), ['task-soon', 'task-late']);
      expect(ids(sections.someday), ['some']);
      expect(ids(sections.paused), ['paused', 'paused-task']);
      // The latest changed first.
      expect(ids(sections.finished), ['some-done', 'rec-ended', 'arch']);
      expect(sections.isEmpty, isFalse);
    });

    test('no routines: the sections are empty', () async {
      final notifier = await loaded();

      expect((notifier.state as RoutinesLoaded).sections.isEmpty, isTrue);
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
      expect(repo.fetchCount, 2);
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
