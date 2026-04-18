import 'package:voice_agent/core/models/conversation_record.dart';
import 'package:voice_agent/core/models/routine.dart';

class AgendaResponse {
  const AgendaResponse({
    required this.date,
    required this.granularity,
    required this.from,
    required this.to,
    required this.items,
    required this.routineItems,
  });

  final String date;
  final String granularity;
  final String from;
  final String to;
  final List<AgendaItem> items;
  final List<AgendaRoutineItem> routineItems;

  factory AgendaResponse.fromMap(Map<String, dynamic> map) {
    return AgendaResponse(
      date: map['date'] as String,
      granularity: map['granularity'] as String,
      from: map['from'] as String,
      to: map['to'] as String,
      items: (map['items'] as List<dynamic>)
          .map((e) => AgendaItem.fromMap(e as Map<String, dynamic>))
          .toList(),
      routineItems: (map['routine_items'] as List<dynamic>)
          .map((e) => AgendaRoutineItem.fromMap(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'date': date,
      'granularity': granularity,
      'from': from,
      'to': to,
      'items': items.map((i) => i.toMap()).toList(),
      'routine_items': routineItems.map((i) => i.toMap()).toList(),
    };
  }
}

class AgendaItem {
  const AgendaItem({
    required this.recordId,
    required this.text,
    this.topicRef,
    required this.scheduledFor,
    required this.timeWindow,
    required this.originRole,
    required this.status,
    required this.linkedConversationCount,
  });

  final String recordId;
  final String text;
  final String? topicRef;
  final String scheduledFor;
  final String timeWindow;
  final OriginRole originRole;
  final RecordStatus status;
  final int linkedConversationCount;

  factory AgendaItem.fromMap(Map<String, dynamic> map) {
    return AgendaItem(
      recordId: map['record_id'] as String,
      text: map['text'] as String,
      topicRef: map['topic_ref'] as String?,
      scheduledFor: map['scheduled_for'] as String,
      timeWindow: map['time_window'] as String,
      originRole: OriginRole.fromString(map['origin_role'] as String),
      status: RecordStatus.fromString(map['status'] as String),
      linkedConversationCount: map['linked_conversation_count'] as int,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'record_id': recordId,
      'text': text,
      'topic_ref': topicRef,
      'scheduled_for': scheduledFor,
      'time_window': timeWindow,
      'origin_role': originRole.name,
      'status': status.name,
      'linked_conversation_count': linkedConversationCount,
    };
  }
}

class AgendaRoutineItem {
  const AgendaRoutineItem({
    required this.routineId,
    required this.routineName,
    required this.scheduledFor,
    this.startTime,
    required this.overdue,
    required this.status,
    this.occurrenceId,
    required this.templates,
  });

  final String routineId;
  final String routineName;
  final String scheduledFor;
  final String? startTime;
  final bool overdue;
  final OccurrenceStatus status;
  final String? occurrenceId;
  final List<RoutineTemplate> templates;

  factory AgendaRoutineItem.fromMap(Map<String, dynamic> map) {
    return AgendaRoutineItem(
      routineId: map['routine_id'] as String,
      routineName: map['routine_name'] as String,
      scheduledFor: map['scheduled_for'] as String,
      startTime: map['start_time'] as String?,
      overdue: map['overdue'] as bool,
      status: OccurrenceStatus.fromString(map['status'] as String),
      occurrenceId: map['occurrence_id'] as String?,
      templates: (map['templates'] as List<dynamic>)
          .map((e) => RoutineTemplate.fromMap(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'routine_id': routineId,
      'routine_name': routineName,
      'scheduled_for': scheduledFor,
      'start_time': startTime,
      'overdue': overdue,
      'status': status.toJson(),
      'occurrence_id': occurrenceId,
      'templates': templates.map((t) => t.toMap()).toList(),
    };
  }
}
