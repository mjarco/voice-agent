import 'package:voice_agent/core/models/routine.dart';
import 'package:voice_agent/features/routines/domain/routine_schedule.dart';

/// The schedule of a routine, one per kind (ADR-CORE-116 of personal-agent).
sealed class RoutineTerm {
  const RoutineTerm();

  RoutineKind get kind;

  /// The `term` of a PATCH: `{rrule}`, `{due_on, due_window}` or `{}`.
  Map<String, dynamic> toMap();
}

class RecurringTerm extends RoutineTerm {
  const RecurringTerm(this.rrule);

  /// The rule without UNTIL: the last day travels apart.
  final String rrule;

  @override
  RoutineKind get kind => RoutineKind.recurring;

  @override
  Map<String, dynamic> toMap() => {'rrule': rrule};
}

class OneOffTerm extends RoutineTerm {
  const OneOffTerm(this.dueOn, this.window);

  /// `YYYY-MM-DD`.
  final String dueOn;
  final TimeWindow window;

  @override
  RoutineKind get kind => RoutineKind.oneOff;

  @override
  Map<String, dynamic> toMap() =>
      {'due_on': dueOn, 'due_window': window.toJson()};
}

class SomedayTerm extends RoutineTerm {
  const SomedayTerm();

  @override
  RoutineKind get kind => RoutineKind.someday;

  @override
  Map<String, dynamic> toMap() => const {};
}

/// What the routine form holds, for a create or (as a [RoutinePatch]) an
/// edit. [lastDay] and [missed] belong to a recurring routine only; a
/// one-off always waits.
class RoutineInput {
  const RoutineInput({
    required this.name,
    required this.term,
    this.startTime,
    this.lastDay,
    this.missed = RoutineMissed.lapses,
    this.steps = const [],
  });

  final String name;
  final RoutineTerm term;
  final String? startTime;

  /// `YYYY-MM-DD`.
  final String? lastDay;
  final RoutineMissed missed;
  final List<String> steps;

  /// The body of `POST /routines`. A recurring routine's last day goes into
  /// the rule as UNTIL, the way personal-agent stores it, since a create
  /// takes no `last_day`.
  Map<String, dynamic> toCreateMap() {
    final term = this.term;
    return {
      'name': name,
      'start_time': startTime,
      'steps': steps,
      'source': 'phone',
      ...switch (term) {
        RecurringTerm(rrule: final rrule) => {
            'rrule': lastDay == null ? rrule : withUntil(rrule, lastDay!),
            'missed': missed.name,
          },
        OneOffTerm() => term.toMap(),
        SomedayTerm() => const <String, dynamic>{},
      },
    };
  }
}

/// [rrule] ending after [lastDay] (`YYYY-MM-DD`): UNTIL at the day's last
/// second UTC, as personal-agent writes it.
String withUntil(String rrule, String lastDay) =>
    '${stripUntil(rrule)};UNTIL=${lastDay.replaceAll('-', '')}T235959Z';

/// [rrule] without its UNTIL.
String stripUntil(String rrule) => rrule
    .replaceAll(RegExp(r';?UNTIL=[^;]*', caseSensitive: false), '')
    .replaceFirst(RegExp(r'^;'), '');

/// [rrule] as the form would build it (without UNTIL), so an unchanged
/// schedule compares equal however the rule was written.
String canonicalRRule(String rrule) =>
    RoutineSchedule.parse(rrule)?.toRRule() ?? stripUntil(rrule);
