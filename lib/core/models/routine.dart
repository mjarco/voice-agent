enum RoutineStatus {
  draft,
  active,
  paused,
  archived;

  static RoutineStatus fromString(String value) {
    return RoutineStatus.values.firstWhere((e) => e.name == value);
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

class RoutineProposal {
  const RoutineProposal({
    required this.id,
    this.topicRef,
    required this.name,
    this.cadence,
    this.startTime,
    required this.items,
    required this.confidence,
    required this.conversationId,
    required this.createdAt,
  });

  final String id;
  final String? topicRef;
  final String name;
  final String? cadence;
  final String? startTime;
  final List<RoutineProposalItem> items;
  final double confidence;
  final String conversationId;
  final DateTime createdAt;

  factory RoutineProposal.fromMap(Map<String, dynamic> map) {
    return RoutineProposal(
      id: map['id'] as String,
      topicRef: map['topic_ref'] as String?,
      name: map['name'] as String,
      cadence: map['cadence'] as String?,
      startTime: map['start_time'] as String?,
      items: (map['items'] as List<dynamic>)
          .map((e) => RoutineProposalItem.fromMap(e as Map<String, dynamic>))
          .toList(),
      confidence: (map['confidence'] as num).toDouble(),
      conversationId: map['conversation_id'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'topic_ref': topicRef,
      'name': name,
      'cadence': cadence,
      'start_time': startTime,
      'items': items.map((i) => i.toMap()).toList(),
      'confidence': confidence,
      'conversation_id': conversationId,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

class RoutineProposalItem {
  const RoutineProposalItem({
    required this.text,
    required this.sortOrder,
  });

  final String text;
  final int sortOrder;

  factory RoutineProposalItem.fromMap(Map<String, dynamic> map) {
    return RoutineProposalItem(
      text: map['text'] as String,
      sortOrder: map['sort_order'] as int,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'text': text,
      'sort_order': sortOrder,
    };
  }
}
