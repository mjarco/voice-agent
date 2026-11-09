import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/models/routine.dart';
import 'package:voice_agent/features/routines/domain/routine_schedule.dart';
import 'package:voice_agent/features/routines/domain/routines_repository.dart';

import '../fake_routines_repository.dart';

const _today = '2026-11-08';

RoutineInput _same(Routine r) => RoutineInput(
      name: r.name,
      term: switch (r.kind) {
        RoutineKind.recurring => RecurringTerm(canonicalRRule(r.rrule)),
        RoutineKind.oneOff => OneOffTerm(r.dueOn!, r.dueWindow!),
        RoutineKind.someday => const SomedayTerm(),
      },
      startTime: r.startTime,
      lastDay: r.isRecurring ? r.lastDay : null,
      missed: r.missed,
      steps: r.steps.map((s) => s.text).toList(),
    );

void main() {
  final gym = sampleRoutine(
    name: 'Gym',
    rrule: 'BYDAY=MO,WE;FREQ=WEEKLY;UNTIL=20261231T235959Z',
    startTime: '07:00',
    lastDay: '2026-12-31',
    missed: RoutineMissed.waits,
    steps: const [
      RoutineStep(text: 'Shoes', sortOrder: 0),
      RoutineStep(text: 'Bottle', sortOrder: 1),
    ],
  );

  group('RoutinePatch.between', () {
    test('an unchanged form sends nothing, whatever order the rule has', () {
      final patch = RoutinePatch.between(gym, _same(gym), today: _today);
      expect(patch.isEmpty, isTrue);
      expect(patch.toMap(), isEmpty);
    });

    test('a new name sends only the name: no schedule, no overdue gate', () {
      final input = _same(gym);
      final patch = RoutinePatch.between(
          gym,
          RoutineInput(
            name: 'Gym twice',
            term: input.term,
            startTime: input.startTime,
            lastDay: input.lastDay,
            missed: input.missed,
            steps: input.steps,
          ),
          today: _today);
      expect(patch.toMap(), {'name': 'Gym twice'});
      expect(patch.changesSchedule, isFalse);
    });

    test('a cleared hour and reordered steps', () {
      final patch = RoutinePatch.between(
          gym,
          RoutineInput(
            name: 'Gym',
            term: const RecurringTerm('FREQ=WEEKLY;BYDAY=MO,WE'),
            lastDay: '2026-12-31',
            missed: RoutineMissed.waits,
            steps: const ['Bottle', 'Shoes'],
          ),
          today: _today);
      expect(patch.toMap(), {
        'start_time': null,
        'steps': ['Bottle', 'Shoes'],
      });
    });

    test('a new rule sends the term and the last day again', () {
      final patch = RoutinePatch.between(
          gym,
          RoutineInput(
            name: 'Gym',
            term: const RecurringTerm('FREQ=DAILY'),
            startTime: '07:00',
            lastDay: '2026-12-31',
            missed: RoutineMissed.waits,
            steps: const ['Shoes', 'Bottle'],
          ),
          today: _today);
      expect(patch.toMap(), {
        'term': {'rrule': 'FREQ=DAILY'},
        'last_day': '2026-12-31',
      });
      expect(patch.changesSchedule, isTrue);
    });

    test('a cleared last day and a new missed rule', () {
      final patch = RoutinePatch.between(
          gym,
          RoutineInput(
            name: 'Gym',
            term: const RecurringTerm('FREQ=WEEKLY;BYDAY=MO,WE'),
            startTime: '07:00',
            missed: RoutineMissed.lapses,
            steps: const ['Shoes', 'Bottle'],
          ),
          today: _today);
      expect(patch.toMap(), {'missed': 'lapses', 'last_day': null});
    });

    test('a last day already past is not sent as cleared', () {
      final ended = sampleRoutine(
          rrule: 'FREQ=DAILY;UNTIL=20261001T235959Z',
          lastDay: '2026-10-01',
          ended: true);
      final patch = RoutinePatch.between(
          ended,
          const RoutineInput(
              name: 'Morning routine', term: RecurringTerm('FREQ=DAILY')),
          today: _today);
      expect(patch.toMap(), isEmpty);
    });

    test('recurring into a one-off sends the term only', () {
      final patch = RoutinePatch.between(
          gym,
          const RoutineInput(
            name: 'Gym',
            term: OneOffTerm('2026-11-20', TimeWindow.week),
            startTime: '07:00',
            steps: ['Shoes', 'Bottle'],
          ),
          today: _today);
      expect(patch.toMap(), {
        'term': {'due_on': '2026-11-20', 'due_window': 'week'},
      });
    });

    test('a one-off into recurring sends its missed rule', () {
      final task = sampleRoutine(dueOn: '2026-11-10');
      final patch = RoutinePatch.between(
          task,
          const RoutineInput(
            name: 'Morning routine',
            term: RecurringTerm('FREQ=DAILY'),
            missed: RoutineMissed.waits,
          ),
          today: _today);
      expect(patch.toMap(), {
        'term': {'rrule': 'FREQ=DAILY'},
        'missed': 'waits',
      });
    });

    test('a one-off moved, and made someday', () {
      final task = sampleRoutine(dueOn: '2026-11-10');
      expect(
        RoutinePatch.between(
                task,
                const RoutineInput(
                    name: 'Morning routine',
                    term: OneOffTerm('2026-11-10', TimeWindow.month)),
                today: _today)
            .toMap(),
        {
          'term': {'due_on': '2026-11-10', 'due_window': 'month'},
        },
      );
      expect(
        RoutinePatch.between(
                task,
                const RoutineInput(
                    name: 'Morning routine', term: SomedayTerm()),
                today: _today)
            .toMap(),
        {'term': <String, dynamic>{}},
      );
    });
  });

  group('rules', () {
    test('withUntil and stripUntil', () {
      expect(withUntil('FREQ=DAILY', '2026-12-31'),
          'FREQ=DAILY;UNTIL=20261231T235959Z');
      expect(withUntil('FREQ=DAILY;UNTIL=20260101T235959Z', '2026-12-31'),
          'FREQ=DAILY;UNTIL=20261231T235959Z');
      expect(stripUntil('UNTIL=20261231T235959Z;FREQ=DAILY'), 'FREQ=DAILY');
    });
  });

  group('describeRoutine and routineEndBadge', () {
    test('say each kind', () {
      expect(describeRoutine(gym, today: _today),
          'Mon, Wed · at 07:00 · until 2026-12-31');
      expect(
          describeRoutine(
              sampleRoutine(dueOn: '2026-11-10', dueWindow: TimeWindow.week),
              today: _today),
          'within a week from 2026-11-10');
      expect(
          describeRoutine(sampleRoutine(kind: RoutineKind.someday),
              today: _today),
          'some day');
    });

    test('badges of what is no longer live', () {
      expect(routineEndBadge(gym), isNull);
      expect(routineEndBadge(sampleRoutine(ended: true)), 'ended');
      expect(
          routineEndBadge(sampleRoutine(
              kind: RoutineKind.someday,
              ended: true,
              resolved: sampleOccurrence(status: OccurrenceStatus.skipped))),
          'skipped');
      expect(
          routineEndBadge(sampleRoutine(
              dueOn: '2026-11-10', ended: true, resolved: sampleOccurrence())),
          'done');
      expect(routineEndBadge(sampleRoutine(status: RoutineStatus.archived)),
          'archived');
    });
  });
}
