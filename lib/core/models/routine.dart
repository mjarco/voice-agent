/// The three kinds of routine (ADR-CORE-116 of personal-agent): a recurring
/// one has an rrule, a one-off a due day with a window, a someday one
/// neither.
enum RoutineKind {
  recurring,
  oneOff,
  someday;

  /// The kind of the API's `kind`, or null for a value this app does not
  /// know (the caller derives it from the fields then).
  static RoutineKind? tryParse(Object? value) => switch (value) {
        'recurring' => RoutineKind.recurring,
        'one_off' => RoutineKind.oneOff,
        'someday' => RoutineKind.someday,
        _ => null,
      };

  String toJson() => switch (this) {
        RoutineKind.recurring => 'recurring',
        RoutineKind.oneOff => 'one_off',
        RoutineKind.someday => 'someday',
      };
}

enum RoutineStatus {
  active,
  paused,
  archived;

  /// An unknown status reads as paused: the routine stays listed, nothing is
  /// ticked off on it, and the server judges a resume.
  static RoutineStatus fromString(Object? value) =>
      RoutineStatus.values.firstWhere((e) => e.name == value,
          orElse: () => RoutineStatus.paused);
}

/// The state of a tick: an agenda row is `pending` (not ticked off yet), a
/// stored occurrence is `done` or `skipped`.
enum OccurrenceStatus {
  pending,
  done,
  skipped;

  /// An unknown status reads as pending: nothing claims it was ticked off.
  static OccurrenceStatus fromString(Object? value) =>
      OccurrenceStatus.values.firstWhere((e) => e.name == value,
          orElse: () => OccurrenceStatus.pending);

  String toJson() => name;
}

/// A one-off's window from its due day: the day itself, seven days, or a
/// month (ADR-CORE-092 of personal-agent).
enum TimeWindow {
  day,
  week,
  month;

  /// The window of [value], or null when there is none (`""`, null) or this
  /// app does not know it.
  static TimeWindow? tryParse(Object? value) =>
      TimeWindow.values.where((e) => e.name == value).firstOrNull;

  String toJson() => name;

  /// The term in words from [dueOn], as the web UI says it: "on 2026-11-10",
  /// "within a week from 2026-11-10".
  String describeFrom(String dueOn) =>
      this == TimeWindow.day ? 'on $dueOn' : 'within a $name from $dueOn';
}

/// What happens to an occurrence nobody resolved on its day (ADR-CORE-092 of
/// personal-agent): it lapses, or it waits on the agenda until resolved. A
/// one-off always waits.
enum RoutineMissed {
  lapses,
  waits;

  /// An unknown value reads as lapses, the server's default for most rules.
  static RoutineMissed fromString(Object? value) =>
      RoutineMissed.values.firstWhere((e) => e.name == value,
          orElse: () => RoutineMissed.lapses);
}

/// Everything the owner has to do (ADR-CORE-116 of personal-agent).
class Routine {
  const Routine({
    required this.id,
    required this.name,
    required this.kind,
    this.rrule = '',
    this.dueOn,
    this.dueWindow,
    this.startTime,
    required this.status,
    this.missed = RoutineMissed.lapses,
    this.activeSince,
    this.steps = const [],
    this.ended = false,
    this.lastDay,
    this.nextDue,
    this.resolved,
    this.source = 'web',
    this.conversationId,
    this.eventId,
    required this.createdAt,
    required this.updatedAt,
    this.existing = false,
  });

  final String id;
  final String name;
  final RoutineKind kind;

  /// The rule of a recurring routine; empty for the other kinds.
  final String rrule;

  /// A one-off's due day (`YYYY-MM-DD`) and window.
  final String? dueOn;
  final TimeWindow? dueWindow;

  final String? startTime;
  final RoutineStatus status;
  final RoutineMissed missed;

  /// The owner's day (`YYYY-MM-DD`) the routine last became active.
  final String? activeSince;

  final List<RoutineStep> steps;

  /// A recurring routine after its last day, a one-off or someday one once
  /// ticked off ([resolved] holds the tick).
  final bool ended;

  /// A recurring routine's last day (`YYYY-MM-DD`, from the rrule's UNTIL).
  final String? lastDay;

  /// The next day the routine is due, null when none is left.
  final String? nextDue;

  /// The tick of a one-off or someday routine; null otherwise.
  final RoutineOccurrence? resolved;

  /// Where it was born: web, phone, chat or migration.
  final String source;

  /// The chat turn the routine was born in, null otherwise.
  final String? conversationId;
  final String? eventId;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// Set on a create that found a live routine of that name: nothing was
  /// written and this is the one that exists.
  final bool existing;

  bool get isRecurring => kind == RoutineKind.recurring;

  /// Parses the API's routine. Only `id` and `name` are required; an unknown
  /// enum value gets a safe default rather than losing the routine.
  factory Routine.fromMap(Map<String, dynamic> map) {
    final rrule = map['rrule'] is String ? map['rrule'] as String : '';
    final dueOn = _string(map['due_on']);
    final kind = RoutineKind.tryParse(map['kind']) ??
        (rrule.isNotEmpty
            ? RoutineKind.recurring
            : dueOn != null
                ? RoutineKind.oneOff
                : RoutineKind.someday);
    final resolved = map['resolved'];
    return Routine(
      id: map['id'] as String,
      name: map['name'] as String,
      kind: kind,
      rrule: rrule,
      dueOn: dueOn,
      dueWindow: TimeWindow.tryParse(map['due_window']) ??
          (dueOn != null ? TimeWindow.day : null),
      startTime: _string(map['start_time']),
      status: RoutineStatus.fromString(map['status']),
      missed: RoutineMissed.fromString(map['missed']),
      activeSince: _string(map['active_since']),
      steps: RoutineStep.listFrom(map['steps']),
      ended: map['ended'] == true,
      lastDay: _string(map['last_day']),
      nextDue: _string(map['next_due']),
      resolved: resolved is Map<String, dynamic>
          ? RoutineOccurrence.tryFromMap(resolved)
          : null,
      source: _string(map['source']) ?? 'web',
      conversationId: _string(map['conversation_id']),
      eventId: _string(map['event_id']),
      createdAt: _instant(map['created_at']),
      updatedAt: _instant(map['updated_at']),
      existing: map['existing'] == true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'kind': kind.toJson(),
      'rrule': rrule,
      'due_on': dueOn,
      'due_window': dueWindow?.toJson(),
      'start_time': startTime,
      'status': status.name,
      'missed': missed.name,
      'active_since': activeSince,
      'steps': steps.map((s) => s.toMap()).toList(),
      'ended': ended,
      'last_day': lastDay,
      'next_due': nextDue,
      'resolved': resolved?.toMap(),
      'source': source,
      'conversation_id': conversationId,
      'event_id': eventId,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      if (existing) 'existing': true,
    };
  }
}

/// A step of a routine, in order. The agenda sends them as `templates`.
class RoutineStep {
  const RoutineStep({required this.text, required this.sortOrder});

  final String text;
  final int sortOrder;

  factory RoutineStep.fromMap(Map<String, dynamic> map) {
    final order = map['sort_order'];
    return RoutineStep(
      text: map['text'] as String,
      sortOrder: order is int ? order : 0,
    );
  }

  /// The steps of [value], in order; a malformed step is dropped.
  static List<RoutineStep> listFrom(Object? value) {
    if (value is! List) return const [];
    final steps = value
        .whereType<Map<String, dynamic>>()
        .where((m) => m['text'] is String)
        .map(RoutineStep.fromMap)
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return steps;
  }

  Map<String, dynamic> toMap() => {'text': text, 'sort_order': sortOrder};
}

/// A tick of a routine: its day done or skipped.
class RoutineOccurrence {
  const RoutineOccurrence({
    required this.id,
    required this.routineId,
    required this.scheduledFor,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String routineId;
  final String scheduledFor;
  final OccurrenceStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory RoutineOccurrence.fromMap(Map<String, dynamic> map) {
    return RoutineOccurrence(
      id: map['id'] as String,
      routineId: map['routine_id'] as String,
      scheduledFor: map['scheduled_for'] as String,
      status: OccurrenceStatus.fromString(map['status']),
      createdAt: _instant(map['created_at']),
      updatedAt: _instant(map['updated_at']),
    );
  }

  /// [fromMap], or null when a required field is missing.
  static RoutineOccurrence? tryFromMap(Map<String, dynamic> map) {
    if (map['id'] is! String ||
        map['routine_id'] is! String ||
        map['scheduled_for'] is! String) {
      return null;
    }
    return RoutineOccurrence.fromMap(map);
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'routine_id': routineId,
      'scheduled_for': scheduledFor,
      'status': status.toJson(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}

String? _string(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

DateTime _instant(Object? value) =>
    (value is String ? DateTime.tryParse(value) : null) ??
    DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
