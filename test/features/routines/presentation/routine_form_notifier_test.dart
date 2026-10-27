import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/models/routine.dart';
import 'package:voice_agent/features/routines/domain/routines_repository.dart';
import 'package:voice_agent/features/routines/presentation/routine_form_notifier.dart';

import '../fake_routines_repository.dart';

const _input = RoutineInput(
  name: 'Czynsz',
  rrule: 'FREQ=MONTHLY;BYMONTHDAY=10',
  missed: RoutineMissed.waits,
  items: ['przelew'],
);

RoutineOverdueException _owed(String day) => RoutineOverdueException(
      'owed',
      routineId: 'rtn-1',
      scheduledFor: day,
    );

void main() {
  late FakeRoutinesRepository repo;

  setUp(() {
    repo = FakeRoutinesRepository();
  });

  test('a new routine is created', () async {
    final notifier = RoutineFormNotifier(repo, null);
    expect(notifier.state.loading, isFalse);

    await notifier.save(_input);

    expect(repo.calls, ['create']);
    expect(notifier.state.saved?.id, 'rtn-new');
  });

  test('an edit loads the routine, then saves from the start day', () async {
    repo.detail = sampleRoutine(id: 'rtn-1', name: 'Czynsz');
    final notifier = RoutineFormNotifier(repo, 'rtn-1');
    expect(notifier.state.loading, isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(notifier.state.routine?.name, 'Czynsz');

    await notifier.save(_input, startsOn: '2026-10-28');

    expect(repo.calls, ['detail rtn-1', 'edit rtn-1']);
    expect(repo.lastStartsOn, '2026-10-28');
    expect(notifier.state.saved, isNotNull);
  });

  test('an owed day asks, then resolving retries the same edit', () async {
    final notifier = RoutineFormNotifier(repo, 'rtn-1');
    await Future<void>.delayed(Duration.zero);
    repo.saveAnswers
      ..add(_owed('2026-09-10'))
      ..add(_owed('2026-10-10'))
      ..add(sampleRoutine(id: 'rtn-2'));

    await notifier.save(_input, startsOn: '2026-10-28');
    expect(notifier.state.overdueDay, '2026-09-10');
    expect(notifier.state.saved, isNull);

    await notifier.resolveOverdue(OccurrenceStatus.done);
    expect(repo.lastResolve?.day, '2026-09-10');
    expect(notifier.state.overdueDay, '2026-10-10');

    await notifier.resolveOverdue(OccurrenceStatus.skipped);
    expect(repo.calls, [
      'detail rtn-1',
      'edit rtn-1',
      'resolve rtn-1 2026-09-10 done',
      'edit rtn-1',
      'resolve rtn-1 2026-10-10 skipped',
      'edit rtn-1',
    ]);
    expect(repo.lastInput, same(_input));
    expect(notifier.state.saved?.id, 'rtn-2');
    expect(notifier.state.overdueDay, isNull);
  });

  test('cancelling the owed day leaves the form open, unsaved', () async {
    final notifier = RoutineFormNotifier(repo, 'rtn-1');
    await Future<void>.delayed(Duration.zero);
    repo.saveAnswers.add(_owed('2026-09-10'));

    await notifier.save(_input, startsOn: '2026-10-28');
    notifier.dismissOverdue();

    expect(notifier.state.overdueDay, isNull);
    expect(notifier.state.saved, isNull);
    await notifier.resolveOverdue(OccurrenceStatus.done);
    expect(repo.lastResolve, isNull);
  });

  test('a failed resolve shows its error and does not retry', () async {
    final notifier = RoutineFormNotifier(repo, 'rtn-1');
    await Future<void>.delayed(Duration.zero);
    repo.saveAnswers.add(_owed('2026-09-10'));
    await notifier.save(_input, startsOn: '2026-10-28');
    repo.actionError = RoutinesGeneralException('resolve failed');

    await notifier.resolveOverdue(OccurrenceStatus.done);

    expect(notifier.state.error, 'resolve failed');
    expect(repo.calls.where((c) => c.startsWith('edit')), hasLength(1));
  });

  test('a save error is shown and the form stays open', () async {
    final notifier = RoutineFormNotifier(repo, null);
    repo.saveAnswers.add(RoutineConflictException('Nazwa zajęta'));

    await notifier.save(_input);

    expect(notifier.state.error, 'Nazwa zajęta');
    expect(notifier.state.saving, isFalse);
    expect(notifier.state.saved, isNull);
  });

  test('saving waits for the edited routine to load', () async {
    final notifier = RoutineFormNotifier(repo, 'rtn-1');

    await notifier.save(_input, startsOn: '2026-10-28');

    expect(repo.calls, ['detail rtn-1']);
  });
}
