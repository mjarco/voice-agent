import 'package:voice_agent/core/models/routine.dart';

/// The four schedules of the routine form (#365, the web UI's form of
/// thought-agent#564). The client builds the RRULE; an rrule outside these
/// schedules parses to null and the form asks for a new schedule.
enum RoutineScheduleKind { daily, weekdays, weeks, monthly }

const routineWeekdays = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];

const routineWeekdayNames = {
  'MO': 'Mon',
  'TU': 'Tue',
  'WE': 'Wed',
  'TH': 'Thu',
  'FR': 'Fri',
  'SA': 'Sat',
  'SU': 'Sun',
};

class RoutineSchedule {
  const RoutineSchedule.daily()
      : kind = RoutineScheduleKind.daily,
        days = const [],
        interval = 1,
        monthday = null;

  const RoutineSchedule.weekdays(this.days)
      : kind = RoutineScheduleKind.weekdays,
        interval = 1,
        monthday = null;

  const RoutineSchedule.weeks(this.days, this.interval)
      : kind = RoutineScheduleKind.weeks,
        monthday = null;

  const RoutineSchedule.monthly(int this.monthday)
      : kind = RoutineScheduleKind.monthly,
        days = const [],
        interval = 1;

  final RoutineScheduleKind kind;

  /// Weekday codes (`MO`…`SU`) for [RoutineScheduleKind.weekdays] and
  /// [RoutineScheduleKind.weeks].
  final List<String> days;

  /// N of "every N weeks"; 1 otherwise.
  final int interval;

  /// The day of the month for [RoutineScheduleKind.monthly].
  final int? monthday;

  /// Parses [rrule] into one of the four schedules, or null when the form
  /// cannot show it. UNTIL is ignored: the form keeps the last day apart.
  /// WKST is not kept by the form, so an rrule with it asks for a new one.
  static RoutineSchedule? parse(String? rrule) {
    final opts = <String, String>{};
    final text = (rrule ?? '').replaceFirst(RegExp(r'^RRULE:', caseSensitive: false), '');
    for (final part in text.split(';')) {
      if (part.isEmpty) continue;
      final eq = part.indexOf('=');
      final key = (eq < 0 ? part : part.substring(0, eq)).toUpperCase();
      final value = eq < 0 ? '' : part.substring(eq + 1).toUpperCase();
      opts[key] = value;
    }
    const known = {'FREQ', 'INTERVAL', 'BYDAY', 'BYMONTHDAY', 'UNTIL'};
    if (opts.keys.any((k) => !known.contains(k))) return null;

    final interval =
        opts['INTERVAL'] == null ? 1 : int.tryParse(opts['INTERVAL']!);
    final days = (opts['BYDAY'] ?? '').isEmpty
        ? <String>[]
        : opts['BYDAY']!.split(',');
    if (interval == null || interval < 1) return null;
    if (days.any((d) => !routineWeekdays.contains(d))) return null;

    switch (opts['FREQ']) {
      case 'DAILY':
        return interval == 1 && days.isEmpty && opts['BYMONTHDAY'] == null
            ? const RoutineSchedule.daily()
            : null;
      case 'WEEKLY':
        if (days.isEmpty || opts['BYMONTHDAY'] != null) return null;
        return interval == 1
            ? RoutineSchedule.weekdays(days)
            : RoutineSchedule.weeks(days, interval);
      case 'MONTHLY':
        final raw = opts['BYMONTHDAY'] ?? '';
        final day = int.tryParse(raw);
        if (interval != 1 || days.isNotEmpty) return null;
        if (!RegExp(r'^\d+$').hasMatch(raw) || day == null) return null;
        return day >= 1 && day <= 31 ? RoutineSchedule.monthly(day) : null;
    }
    return null;
  }

  /// The RRULE of this schedule, without UNTIL (the server adds it from the
  /// form's last day).
  String toRRule() {
    String byday() =>
        'BYDAY=${routineWeekdays.where(days.contains).join(',')}';
    return switch (kind) {
      RoutineScheduleKind.daily => 'FREQ=DAILY',
      RoutineScheduleKind.weekdays => 'FREQ=WEEKLY;${byday()}',
      RoutineScheduleKind.weeks => 'FREQ=WEEKLY;INTERVAL=$interval;${byday()}',
      RoutineScheduleKind.monthly => 'FREQ=MONTHLY;BYMONTHDAY=$monthday',
    };
  }

  /// The schedule in words, e.g. "every 2 weeks: Mon, Fri".
  String describe() {
    final names = routineWeekdays
        .where(days.contains)
        .map((d) => routineWeekdayNames[d])
        .join(', ');
    return switch (kind) {
      RoutineScheduleKind.daily => 'every day',
      RoutineScheduleKind.weekdays => names,
      RoutineScheduleKind.weeks => 'every $interval weeks: $names',
      RoutineScheduleKind.monthly => 'day $monthday of the month',
    };
  }

  /// Whether a day of this schedule falls between [from] and [to], both
  /// included. The server refuses a version with none (it would never reach
  /// the agenda), so the form names the last day first. Every N weeks counts
  /// any of its weekdays: which weeks it falls on is the server's to say.
  bool occursBetween(DateTime from, DateTime to) {
    for (var d = DateTime(from.year, from.month, from.day);
        !d.isAfter(to);
        d = DateTime(d.year, d.month, d.day + 1)) {
      final matches = switch (kind) {
        RoutineScheduleKind.daily => true,
        RoutineScheduleKind.weekdays ||
        RoutineScheduleKind.weeks =>
          days.contains(routineWeekdays[d.weekday - 1]),
        RoutineScheduleKind.monthly => d.day == monthday,
      };
      if (matches) return true;
      // A month holds every day of a monthly schedule that exists.
      if (d.difference(from).inDays > 62) return false;
    }
    return false;
  }

  /// [rrule] in words, or the rrule itself when the form cannot show it.
  static String describeRRule(String? rrule) {
    final schedule = parse(rrule);
    if (schedule != null) return schedule.describe();
    return (rrule == null || rrule.isEmpty) ? 'no schedule' : rrule;
  }
}

/// [day] as the API's `YYYY-MM-DD`.
String formatRoutineDay(DateTime day) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${day.year.toString().padLeft(4, '0')}-${two(day.month)}-${two(day.day)}';
}

/// `YYYY-MM-DD` as a local date, or null when it does not parse.
DateTime? parseRoutineDay(String? day) {
  if (day == null) return null;
  final parsed = DateTime.tryParse(day);
  return parsed == null ? null : DateTime(parsed.year, parsed.month, parsed.day);
}

/// The routine's term in one line, as the web UI shows it: the schedule in
/// words (recurring), the due day and window (one-off) or "some day", the
/// hour, a start still ahead, and the last day. [today] is `YYYY-MM-DD`.
String describeRoutine(Routine r, {required String today}) {
  final parts = <String>[
    switch (r.kind) {
      RoutineKind.recurring => RoutineSchedule.describeRRule(r.rrule),
      RoutineKind.oneOff =>
        (r.dueWindow ?? TimeWindow.day).describeFrom(r.dueOn ?? '?'),
      RoutineKind.someday => 'some day',
    },
  ];
  if (r.startTime != null) parts.add('at ${r.startTime}');
  if (r.isRecurring &&
      r.activeSince != null &&
      r.activeSince!.compareTo(today) > 0) {
    parts.add('from ${r.activeSince}');
  }
  if (r.isRecurring && r.lastDay != null) {
    parts.add('${r.ended ? 'ended after' : 'until'} ${r.lastDay}');
  }
  return parts.join(' · ');
}

/// The badge of a routine that is no longer live: archived, a recurring one
/// ended, a one-off or someday one done or skipped; null for a live one.
String? routineEndBadge(Routine r) {
  if (r.status == RoutineStatus.archived) return 'archived';
  if (!r.ended) return null;
  if (r.isRecurring) return 'ended';
  return r.resolved?.status == OccurrenceStatus.skipped ? 'skipped' : 'done';
}
