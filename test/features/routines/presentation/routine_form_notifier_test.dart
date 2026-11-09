import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/models/routine.dart';
import 'package:voice_agent/features/routines/domain/routines_repository.dart';
import 'package:voice_agent/features/routines/presentation/routine_form_notifier.dart';

import '../fake_routines_repository.dart';

const _input = RoutineInput(
  name: 'Czynsz',
  term: RecurringTerm('FREQ=MONTHLY;BYMONTHDAY=10'),
  missed: RoutineMissed.waits,
  steps: ['przelew'],
);

/// The routine [_input] edits: same name and steps, a daily rule.
Routine _czynsz() => sampleRoutine(
      name: 'Czynsz',
      missed: RoutineMissed.waits,
      steps: const [RoutineStep(text: 'przelew', sortOrder: 0)],
    );

RoutineOverdueException _owed(String day) => RoutineOverdueException(
      'owed',
      routineId: 'rtn-1',
      scheduledFor: day,
    );

void main() {
  late FakeRoutinesRepository repo;

  setUp(() {
    repo = FakeRoutinesRepository()..detail = _czynsz();
  });

  Future<RoutineFormNotifier> editing() async {
    final notifier = RoutineFormNotifier(repo, 'rtn-1',
        clock: () => DateTime(2026, 10, 27, 23, 30));
    await Future<void>.delayed(Duration.zero);
    return notifier;
  }

  test('a new routine is created', () async {
    final notifier = RoutineFormNotifier(repo, null);
    expect(notifier.state.loading, isFalse);

    await notifier.save(_input);

    expect(repo.calls, ['create']);
    expect(repo.lastInput, same(_input));
    expect(notifier.state.saved?.id, 'rtn-new');
  });

  test('a live routine of that name is not saved again', () async {
    final notifier = RoutineFormNotifier(repo, null);
    repo.saveAnswers.add(sampleRoutine(name: 'Czynsz', existing: true));

    await notifier.save(_input);

    expect(notifier.state.saved, isNull);
    expect(notifier.state.errorField, RoutineFormField.name);
    expect(notifier.state.error, contains('“Czynsz” is already on the list'));
  });

  test('an edit loads the routine, then patches what changed', () async {
    final notifier = await editing();
    expect(notifier.state.routine?.name, 'Czynsz');

    await notifier.save(_input);

    expect(repo.calls, ['detail rtn-1', 'edit rtn-1']);
    expect(repo.lastPatch!.toMap(), {
      'term': {'rrule': 'FREQ=MONTHLY;BYMONTHDAY=10'},
    });
    expect(notifier.state.saved, isNotNull);
  });

  test('an edit that changes nothing is not sent', () async {
    final notifier = await editing();

    await notifier.save(const RoutineInput(
      name: 'Czynsz',
      term: RecurringTerm('FREQ=DAILY'),
      missed: RoutineMissed.waits,
      steps: ['przelew'],
    ));

    expect(repo.calls, ['detail rtn-1']);
    expect(notifier.state.error, 'Nothing changed.');
    expect(notifier.state.saved, isNull);
  });

  test('an owed day asks, then resolving retries the same patch', () async {
    final notifier = await editing();
    repo.saveAnswers
      ..add(_owed('2026-09-10'))
      ..add(_owed('2026-10-10'))
      ..add(sampleRoutine());

    await notifier.save(_input);
    expect(notifier.state.overdueDay, '2026-09-10');
    expect(notifier.state.saved, isNull);
    final patch = repo.lastPatch;

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
    expect(repo.lastPatch, same(patch));
    expect(notifier.state.saved, isNotNull);
    expect(notifier.state.overdueDay, isNull);
  });

  test('cancelling the owed day leaves the form open, unsaved', () async {
    final notifier = await editing();
    repo.saveAnswers.add(_owed('2026-09-10'));

    await notifier.save(_input);
    notifier.dismissOverdue();

    expect(notifier.state.overdueDay, isNull);
    expect(notifier.state.saved, isNull);
    await notifier.resolveOverdue(OccurrenceStatus.done);
    expect(repo.lastResolve, isNull);
  });

  test('a failed resolve shows its error and does not retry', () async {
    final notifier = await editing();
    repo.saveAnswers.add(_owed('2026-09-10'));
    await notifier.save(_input);
    repo.actionError = RoutinesGeneralException('resolve failed');

    await notifier.resolveOverdue(OccurrenceStatus.done);

    expect(notifier.state.error, 'resolve failed');
    expect(repo.calls.where((c) => c.startsWith('edit')), hasLength(1));
  });

  test('a day resolved elsewhere does not stop the edit', () async {
    final notifier = await editing();
    repo.saveAnswers
      ..add(_owed('2026-09-10'))
      ..add(sampleRoutine());
    await notifier.save(_input);
    repo.actionError = RoutineAlreadyResolvedException('resolved');

    await notifier.resolveOverdue(OccurrenceStatus.done);

    expect(repo.calls.where((c) => c.startsWith('edit')), hasLength(2));
    expect(notifier.state.error, isNull);
    expect(notifier.state.saved, isNotNull);
  });

  test('a save error is shown and the form stays open', () async {
    final notifier = RoutineFormNotifier(repo, null);
    repo.saveAnswers.add(RoutinesGeneralException('name too long'));

    await notifier.save(_input);

    expect(notifier.state.error, 'name too long');
    expect(notifier.state.saving, isFalse);
    expect(notifier.state.saved, isNull);
  });

  test('invalid_rrule marks the last day when there is one, else the '
      'schedule', () async {
    final notifier = RoutineFormNotifier(repo, null);
    repo.saveAnswers
      ..add(RoutineInvalidRRuleException('no day left'))
      ..add(RoutineInvalidRRuleException('does not parse'));

    await notifier.save(const RoutineInput(
      name: 'x',
      term: RecurringTerm('FREQ=DAILY'),
      lastDay: '2026-10-28',
    ));
    expect(notifier.state.errorField, RoutineFormField.lastDay);
    expect(notifier.state.error, 'no day left');

    notifier.clearErrorField();
    expect(notifier.state.errorField, isNull);

    await notifier.save(const RoutineInput(
        name: 'x', term: RecurringTerm('FREQ=DAILY')));
    expect(notifier.state.errorField, RoutineFormField.schedule);
  });

  test('a rename to a taken name marks the name', () async {
    final notifier = await editing();
    repo.saveAnswers.add(RoutineNameTakenException('name is taken'));

    await notifier.save(const RoutineInput(
      name: 'Gym',
      term: RecurringTerm('FREQ=DAILY'),
      missed: RoutineMissed.waits,
      steps: ['przelew'],
    ));

    expect(repo.lastPatch!.toMap(), {'name': 'Gym'});
    expect(notifier.state.error, 'name is taken');
    expect(notifier.state.errorField, RoutineFormField.name);
  });

  test('saving waits for the edited routine to load', () async {
    final notifier = RoutineFormNotifier(repo, 'rtn-1');

    await notifier.save(_input);

    expect(repo.calls, ['detail rtn-1']);
  });
}
