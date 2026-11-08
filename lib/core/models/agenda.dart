import 'package:voice_agent/core/models/routine.dart';

/// `GET /agenda` of personal-agent: the routines due in the window and the
/// window's meetings (ADR-CORE-116 there retired the action items).
class AgendaResponse {
  const AgendaResponse({
    required this.date,
    required this.granularity,
    required this.from,
    required this.to,
    required this.routineItems,
    this.calendarItems = const [],
  });

  final String date;
  final String granularity;
  final String from;
  final String to;
  final List<AgendaRoutineItem> routineItems;

  /// Meetings from personal-agent's calendar mirror (ADR-API-101 there);
  /// empty from a personal-agent that does not send them.
  final List<AgendaCalendarItem> calendarItems;

  factory AgendaResponse.fromMap(Map<String, dynamic> map) {
    return AgendaResponse(
      date: map['date'] as String,
      granularity: map['granularity'] as String,
      from: map['from'] as String,
      to: map['to'] as String,
      // A malformed row is dropped rather than losing the agenda with it.
      routineItems:
          (map['routine_items'] as List<dynamic>?)
              ?.map(AgendaRoutineItem.tryFromMap)
              .whereType<AgendaRoutineItem>()
              .toList() ??
          [],
      calendarItems:
          (map['calendar_items'] as List<dynamic>?)
              ?.map(AgendaCalendarItem.tryFromMap)
              .whereType<AgendaCalendarItem>()
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'date': date,
      'granularity': granularity,
      'from': from,
      'to': to,
      'routine_items': routineItems.map((i) => i.toMap()).toList(),
      'calendar_items': calendarItems.map((i) => i.toMap()).toList(),
    };
  }
}

/// A routine due in the agenda's window: a recurring routine's day or a
/// one-off during (and, overdue, after) its window. A row is never ticked
/// off yet: a tick takes it off the agenda.
class AgendaRoutineItem {
  const AgendaRoutineItem({
    required this.routineId,
    required this.routineName,
    required this.kind,
    required this.scheduledFor,
    this.dueWindow,
    this.startTime,
    required this.overdue,
    this.steps = const [],
  });

  final String routineId;
  final String routineName;

  /// Recurring or one-off; a someday routine is never on the agenda.
  final RoutineKind kind;

  /// The day the row is for: a recurring routine's day, a one-off's due day.
  final String scheduledFor;

  /// A one-off's window; null for a recurring routine.
  final TimeWindow? dueWindow;
  final String? startTime;
  final bool overdue;

  /// The routine's steps, sent as `templates`.
  final List<RoutineStep> steps;

  bool get isOneOff => kind == RoutineKind.oneOff;

  /// [fromMap], or null when the row lacks its routine, name or day.
  static AgendaRoutineItem? tryFromMap(dynamic e) {
    if (e is! Map<String, dynamic>) return null;
    if (e['routine_id'] is! String ||
        e['routine_name'] is! String ||
        e['scheduled_for'] is! String) {
      return null;
    }
    return AgendaRoutineItem.fromMap(e);
  }

  /// An unknown or missing `kind` reads from the fields: a row with a window
  /// is a one-off, any other recurring.
  factory AgendaRoutineItem.fromMap(Map<String, dynamic> map) {
    final window = TimeWindow.tryParse(map['due_window']);
    final kind = switch (RoutineKind.tryParse(map['kind'])) {
      RoutineKind.oneOff => RoutineKind.oneOff,
      RoutineKind.recurring => RoutineKind.recurring,
      _ => window != null ? RoutineKind.oneOff : RoutineKind.recurring,
    };
    final start = map['start_time'];
    return AgendaRoutineItem(
      routineId: map['routine_id'] as String,
      routineName: map['routine_name'] as String,
      kind: kind,
      scheduledFor: map['scheduled_for'] as String,
      dueWindow: kind == RoutineKind.oneOff ? window ?? TimeWindow.day : null,
      startTime: start is String && start.isNotEmpty ? start : null,
      overdue: map['overdue'] == true,
      steps: RoutineStep.listFrom(map['templates']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'routine_id': routineId,
      'routine_name': routineName,
      'kind': kind.toJson(),
      'scheduled_for': scheduledFor,
      'due_window': dueWindow?.toJson() ?? '',
      'start_time': startTime,
      'overdue': overdue,
      'templates': steps.map((t) => t.toMap()).toList(),
    };
  }
}

/// A meeting of the agenda: shown, never ticked off. A timed one has RFC 3339
/// [start]/[end] in the owner's zone; an all-day one has dates, [end] being
/// its last day.
class AgendaCalendarItem {
  const AgendaCalendarItem({
    required this.calendar,
    required this.uid,
    required this.title,
    required this.start,
    required this.end,
    required this.allDay,
  });

  /// The calendar's label: PRIV, CORP, FAMI.
  final String calendar;
  final String uid;
  final String title;
  final String start;
  final String end;
  final bool allDay;

  /// The line under the title on day [day] (YYYY-MM-DD): the hours, "all day",
  /// or the days a meeting spans when it does not start and end on [day].
  String when(String day) {
    final firstDay = start.substring(0, 10);
    final lastDay = end.substring(0, 10);
    if (allDay) {
      return firstDay == lastDay ? 'all day' : '$firstDay – $lastDay';
    }
    final from = start.substring(11, 16);
    final to = end.substring(11, 16);
    final ends = DateTime.parse(lastDay);
    final endsNextMidnight =
        to == '00:00' && ends.difference(DateTime.parse(firstDay)).inDays == 1;
    if (firstDay == day && (lastDay == day || endsNextMidnight)) {
      return '$from–$to';
    }
    return '$firstDay $from – $lastDay $to';
  }

  static final _date = RegExp(r'^\d{4}-\d{2}-\d{2}$');
  static final _instant = RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}');

  /// [fromMap] for an item of the response, or null when it lacks a field
  /// [when] reads or its times do not have the contract's shape.
  static AgendaCalendarItem? tryFromMap(dynamic e) {
    if (e is! Map<String, dynamic>) return null;
    final allDay = e['all_day'] ?? false;
    final shape = allDay == true ? _date : _instant;
    final start = e['start'], end = e['end'];
    if (e['calendar'] is! String ||
        e['uid'] is! String ||
        e['title'] is! String ||
        allDay is! bool ||
        start is! String ||
        end is! String ||
        !shape.hasMatch(start) ||
        !shape.hasMatch(end)) {
      return null;
    }
    return AgendaCalendarItem.fromMap(e);
  }

  factory AgendaCalendarItem.fromMap(Map<String, dynamic> map) {
    return AgendaCalendarItem(
      calendar: map['calendar'] as String,
      uid: map['uid'] as String,
      title: map['title'] as String,
      start: map['start'] as String,
      end: map['end'] as String,
      allDay: map['all_day'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'calendar': calendar,
      'uid': uid,
      'title': title,
      'start': start,
      'end': end,
      'all_day': allDay,
    };
  }
}
