enum RoutineStatus {
  draft,
  active,
  paused,
  archived;

  static RoutineStatus fromString(String value) {
    return RoutineStatus.values.firstWhere((e) => e.name == value,
        orElse: () => throw ArgumentError('Unknown RoutineStatus: $value'));
  }
}

enum OccurrenceStatus {
  pending,
  inProgress,
  done,
  skipped;

  static OccurrenceStatus fromString(String value) {
    return switch (value) {
      'pending' => OccurrenceStatus.pending,
      'in_progress' => OccurrenceStatus.inProgress,
      'done' => OccurrenceStatus.done,
      'skipped' => OccurrenceStatus.skipped,
      _ => throw ArgumentError('Unknown OccurrenceStatus: $value'),
    };
  }

  String toJson() {
    return switch (this) {
      OccurrenceStatus.pending => 'pending',
      OccurrenceStatus.inProgress => 'in_progress',
      OccurrenceStatus.done => 'done',
      OccurrenceStatus.skipped => 'skipped',
    };
  }
}

enum TimeWindow {
  day,
  week,
  month,
  adHoc;

  static TimeWindow fromString(String value) {
    return switch (value) {
      'day' => TimeWindow.day,
      'week' => TimeWindow.week,
      'month' => TimeWindow.month,
      'ad_hoc' => TimeWindow.adHoc,
      _ => throw ArgumentError('Unknown TimeWindow: $value'),
    };
  }

  String toJson() {
    return switch (this) {
      TimeWindow.day => 'day',
      TimeWindow.week => 'week',
      TimeWindow.month => 'month',
      TimeWindow.adHoc => 'ad_hoc',
    };
  }
}

/// What happens to an occurrence nobody resolved on its day (ADR-CORE-092 of
/// personal-agent): it lapses, or it waits on the agenda until resolved.
enum RoutineMissed {
  lapses,
  waits;

  static RoutineMissed fromString(String value) {
    return RoutineMissed.values.firstWhere((e) => e.name == value,
        orElse: () => throw ArgumentError('Unknown RoutineMissed: $value'));
  }
}

class Routine {
  const Routine({
    required this.id,
    required this.sourceRecordId,
    required this.name,
    required this.rrule,
    this.cadence,
    this.startTime,
    required this.status,
    this.templates = const [],
    this.nextOccurrence,
    this.missed = RoutineMissed.lapses,
    this.activeSince,
    this.lastDay,
    this.ended = false,
    this.previousRoutineId,
    this.nextRoutineId,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String sourceRecordId;
  final String name;
  final String rrule;
  final String? cadence;
  final String? startTime;
  final RoutineStatus status;
  final List<RoutineTemplate> templates;
  final RoutineNextOccurrence? nextOccurrence;
  final RoutineMissed missed;

  /// The owner's day (`YYYY-MM-DD`) the routine last became active; null for
  /// a draft. A version made by an edit starts on this day.
  final String? activeSince;

  /// The last day the routine occurs (`YYYY-MM-DD`, from the rrule's UNTIL).
  final String? lastDay;

  /// True when no occurrence is left from the owner's today.
  final bool ended;

  /// The version this routine replaced by an edit, and the one that
  /// replaced it (ADR-DATA-095 of personal-agent).
  final String? previousRoutineId;
  final String? nextRoutineId;

  final DateTime createdAt;
  final DateTime updatedAt;

  factory Routine.fromMap(Map<String, dynamic> map) {
    return Routine(
      id: map['id'] as String,
      sourceRecordId: map['source_record_id'] as String,
      name: map['name'] as String,
      rrule: map['rrule'] as String,
      cadence: map['cadence'] as String?,
      startTime: map['start_time'] as String?,
      status: RoutineStatus.fromString(map['status'] as String),
      templates: (map['templates'] as List<dynamic>?)
              ?.map((e) =>
                  RoutineTemplate.fromMap(e as Map<String, dynamic>))
              .toList() ??
          [],
      nextOccurrence: map['next_occurrence'] != null
          ? RoutineNextOccurrence.fromMap(
              map['next_occurrence'] as Map<String, dynamic>)
          : null,
      missed: map['missed'] != null
          ? RoutineMissed.fromString(map['missed'] as String)
          : RoutineMissed.lapses,
      activeSince: map['active_since'] as String?,
      lastDay: map['last_day'] as String?,
      ended: map['ended'] as bool? ?? false,
      previousRoutineId: map['previous_routine_id'] as String?,
      nextRoutineId: map['next_routine_id'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'source_record_id': sourceRecordId,
      'name': name,
      'rrule': rrule,
      'cadence': cadence,
      'start_time': startTime,
      'status': status.name,
      'templates': templates.map((t) => t.toMap()).toList(),
      'next_occurrence': nextOccurrence?.toMap(),
      'missed': missed.name,
      'active_since': activeSince,
      'last_day': lastDay,
      'ended': ended,
      'previous_routine_id': previousRoutineId,
      'next_routine_id': nextRoutineId,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}

class RoutineTemplate {
  const RoutineTemplate({
    this.id,
    required this.text,
    required this.sortOrder,
  });

  final String? id;
  final String text;
  final int sortOrder;

  factory RoutineTemplate.fromMap(Map<String, dynamic> map) {
    return RoutineTemplate(
      id: map['id'] as String?,
      text: map['text'] as String,
      sortOrder: map['sort_order'] as int,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'text': text,
      'sort_order': sortOrder,
    };
  }
}

class RoutineOccurrence {
  const RoutineOccurrence({
    required this.id,
    required this.routineId,
    required this.scheduledFor,
    required this.timeWindow,
    required this.status,
    this.conversationId,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String routineId;
  final String scheduledFor;
  final TimeWindow timeWindow;
  final OccurrenceStatus status;
  final String? conversationId;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory RoutineOccurrence.fromMap(Map<String, dynamic> map) {
    return RoutineOccurrence(
      id: map['id'] as String,
      routineId: map['routine_id'] as String,
      scheduledFor: map['scheduled_for'] as String,
      timeWindow: TimeWindow.fromString(map['time_window'] as String),
      status: OccurrenceStatus.fromString(map['status'] as String),
      conversationId: map['conversation_id'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'routine_id': routineId,
      'scheduled_for': scheduledFor,
      'time_window': timeWindow.toJson(),
      'status': status.toJson(),
      'conversation_id': conversationId,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}

class RoutineNextOccurrence {
  const RoutineNextOccurrence({
    required this.date,
    required this.timeWindow,
  });

  final String date;
  final TimeWindow timeWindow;

  factory RoutineNextOccurrence.fromMap(Map<String, dynamic> map) {
    return RoutineNextOccurrence(
      date: map['date'] as String,
      timeWindow: TimeWindow.fromString(map['time_window'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'date': date,
      'time_window': timeWindow.toJson(),
    };
  }
}
