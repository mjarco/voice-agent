import 'package:voice_agent/core/models/routine.dart';
import 'package:voice_agent/features/routines/domain/routine_input.dart';

/// `PATCH /routines/{id}`: only the fields set change. A record field
/// `(value: null)` clears it; a null field is left as it is.
class RoutinePatch {
  const RoutinePatch({
    this.name,
    this.term,
    this.startTime,
    this.steps,
    this.missed,
    this.lastDay,
  });

  /// End after [day] (`YYYY-MM-DD`): the last day a recurring routine occurs.
  const RoutinePatch.endAfter(String day)
      : name = null,
        term = null,
        startTime = null,
        steps = null,
        missed = null,
        lastDay = (value: day);

  final String? name;
  final RoutineTerm? term;
  final ({String? value})? startTime;
  final List<String>? steps;
  final RoutineMissed? missed;
  final ({String? value})? lastDay;

  bool get isEmpty =>
      name == null &&
      term == null &&
      startTime == null &&
      steps == null &&
      missed == null &&
      lastDay == null;

  /// Whether personal-agent counts this as a change of the schedule: such an
  /// edit of a recurring waits routine that owes a day is refused until the
  /// day is resolved.
  bool get changesSchedule => term != null || lastDay != null;

  Map<String, dynamic> toMap() => {
        if (name != null) 'name': name,
        if (term != null) 'term': term!.toMap(),
        if (startTime != null) 'start_time': startTime!.value,
        if (steps != null) 'steps': steps,
        if (missed != null) 'missed': missed!.name,
        if (lastDay != null) 'last_day': lastDay!.value,
      };

  /// What [input] changes in [old]; [today] is `YYYY-MM-DD`. An unchanged
  /// schedule is not sent, so it never meets the overdue gate. A new rule
  /// comes without UNTIL, so a last day is sent again with it; a recurring
  /// routine made from another kind sends its missed rule, else the server
  /// would give it the default.
  factory RoutinePatch.between(
    Routine old,
    RoutineInput input, {
    required String today,
  }) {
    final term = input.term;
    final termChanged = switch (term) {
      RecurringTerm(rrule: final rrule) =>
        !old.isRecurring || canonicalRRule(old.rrule) != canonicalRRule(rrule),
      OneOffTerm(dueOn: final dueOn, window: final window) =>
        old.kind != RoutineKind.oneOff ||
            old.dueOn != dueOn ||
            (old.dueWindow ?? TimeWindow.day) != window,
      SomedayTerm() => old.kind != RoutineKind.someday,
    };
    final oldSteps = [...old.steps]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final stepsChanged = !_sameList(
        oldSteps.map((s) => s.text).toList(), input.steps);

    RoutineMissed? missed;
    ({String? value})? lastDay;
    if (term is RecurringTerm) {
      if (!old.isRecurring || input.missed != old.missed) {
        missed = input.missed;
      }
      final oldLast = old.isRecurring &&
              old.lastDay != null &&
              old.lastDay!.compareTo(today) >= 0
          ? old.lastDay
          : null;
      if (termChanged ? input.lastDay != null : input.lastDay != oldLast) {
        lastDay = (value: input.lastDay);
      }
    }

    return RoutinePatch(
      name: input.name != old.name ? input.name : null,
      term: termChanged ? term : null,
      startTime:
          input.startTime != old.startTime ? (value: input.startTime) : null,
      steps: stepsChanged ? input.steps : null,
      missed: missed,
      lastDay: lastDay,
    );
  }

  static bool _sameList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
