import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/features/routines/domain/routine_schedule.dart';

void main() {
  group('RoutineSchedule.parse', () {
    test('every day', () {
      final s = RoutineSchedule.parse('FREQ=DAILY')!;
      expect(s.kind, RoutineScheduleKind.daily);
    });

    test('chosen weekdays, UNTIL ignored', () {
      final s = RoutineSchedule.parse(
          'FREQ=WEEKLY;BYDAY=MO,FR;UNTIL=20261231T235959Z')!;
      expect(s.kind, RoutineScheduleKind.weekdays);
      expect(s.days, ['MO', 'FR']);
    });

    test('every N weeks', () {
      final s = RoutineSchedule.parse('FREQ=WEEKLY;INTERVAL=2;BYDAY=SA')!;
      expect(s.kind, RoutineScheduleKind.weeks);
      expect(s.interval, 2);
      expect(s.days, ['SA']);
    });

    test('day of the month', () {
      final s = RoutineSchedule.parse('FREQ=MONTHLY;BYMONTHDAY=10')!;
      expect(s.kind, RoutineScheduleKind.monthly);
      expect(s.monthday, 10);
    });

    test('lower case and an RRULE: prefix parse', () {
      final s = RoutineSchedule.parse('RRULE:freq=weekly;byday=tu')!;
      expect(s.kind, RoutineScheduleKind.weekdays);
      expect(s.days, ['TU']);
    });

    for (final rrule in [
      null,
      '',
      'FREQ=MONTHLY',
      'FREQ=WEEKLY',
      'FREQ=WEEKLY;BYDAY=MO;WKST=MO',
      'FREQ=DAILY;INTERVAL=2',
      'FREQ=DAILY;COUNT=5',
      'FREQ=YEARLY',
      'FREQ=MONTHLY;BYMONTHDAY=-1',
      'FREQ=MONTHLY;BYMONTHDAY=32',
      'FREQ=MONTHLY;BYDAY=1MO',
      'FREQ=WEEKLY;BYDAY=XX',
      'FREQ=WEEKLY;INTERVAL=0;BYDAY=MO',
    ]) {
      test('cannot show $rrule', () {
        expect(RoutineSchedule.parse(rrule), isNull);
      });
    }
  });

  group('RoutineSchedule.toRRule', () {
    test('orders the days Monday first', () {
      expect(const RoutineSchedule.weekdays(['FR', 'MO']).toRRule(),
          'FREQ=WEEKLY;BYDAY=MO,FR');
    });

    for (final rrule in [
      'FREQ=DAILY',
      'FREQ=WEEKLY;BYDAY=MO,WE,FR',
      'FREQ=WEEKLY;INTERVAL=2;BYDAY=SA',
      'FREQ=MONTHLY;BYMONTHDAY=1',
    ]) {
      test('round-trips $rrule', () {
        expect(RoutineSchedule.parse(rrule)!.toRRule(), rrule);
      });
    }
  });

  group('RoutineSchedule.occursBetween', () {
    // 2026-10-27 is a Tuesday.
    final tue = DateTime(2026, 10, 27);

    test('a schedule with no day in the range does not occur', () {
      expect(const RoutineSchedule.weekdays(['MO', 'FR']).occursBetween(tue, tue),
          isFalse);
      expect(const RoutineSchedule.monthly(10).occursBetween(tue, tue), isFalse);
      expect(
          const RoutineSchedule.weeks(['WE'], 2)
              .occursBetween(tue, DateTime(2026, 10, 27)),
          isFalse);
    });

    test('a schedule with a day in the range occurs', () {
      expect(const RoutineSchedule.daily().occursBetween(tue, tue), isTrue);
      expect(const RoutineSchedule.weekdays(['TU']).occursBetween(tue, tue),
          isTrue);
      expect(
          const RoutineSchedule.weekdays(['FR'])
              .occursBetween(tue, DateTime(2026, 10, 30)),
          isTrue);
      expect(
          const RoutineSchedule.monthly(10)
              .occursBetween(tue, DateTime(2026, 11, 10)),
          isTrue);
    });

    test('day 31 skips the months without it', () {
      expect(
          const RoutineSchedule.monthly(31).occursBetween(
              DateTime(2026, 11, 1), DateTime(2026, 11, 30)),
          isFalse);
    });

    test('an open-ended range is not walked to its end', () {
      expect(
          const RoutineSchedule.monthly(31)
              .occursBetween(DateTime(2026, 11, 1), DateTime(2036, 1, 1)),
          isTrue);
    });
  });

  group('RoutineSchedule.describeRRule', () {
    test('in words', () {
      expect(RoutineSchedule.describeRRule('FREQ=DAILY'), 'every day');
      expect(RoutineSchedule.describeRRule('FREQ=WEEKLY;BYDAY=FR,MO'),
          'Mon, Fri');
      expect(RoutineSchedule.describeRRule('FREQ=WEEKLY;INTERVAL=3;BYDAY=SU'),
          'every 3 weeks: Sun');
      expect(RoutineSchedule.describeRRule('FREQ=MONTHLY;BYMONTHDAY=15'),
          'day 15 of the month');
    });

    test('falls back to the rrule', () {
      expect(RoutineSchedule.describeRRule('FREQ=YEARLY'), 'FREQ=YEARLY');
      expect(RoutineSchedule.describeRRule(''), 'no schedule');
    });
  });
}
