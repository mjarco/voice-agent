enum ConversationStatus {
  open,
  closed;

  static ConversationStatus fromString(String value) {
    return ConversationStatus.values.firstWhere((e) => e.name == value);
  }
}

enum EventRole {
  user,
  agent;

  static EventRole fromString(String value) {
    return EventRole.values.firstWhere((e) => e.name == value);
  }
}

class Conversation {
  const Conversation({
    required this.conversationId,
    required this.sessionId,
    required this.status,
    required this.createdAt,
    required this.eventCount,
    this.lastEventAt,
    this.firstMessagePreview,
    this.subjectRecordId,
    this.subjectRecordText,
    this.subjectRecordStatus,
  });

  final String conversationId;
  final String sessionId;
  final ConversationStatus status;
  final DateTime createdAt;
  final int eventCount;
  final DateTime? lastEventAt;
  final String? firstMessagePreview;
  final String? subjectRecordId;
  final String? subjectRecordText;
  final String? subjectRecordStatus;

  factory Conversation.fromMap(Map<String, dynamic> map) {
    return Conversation(
      conversationId: map['conversation_id'] as String,
      sessionId: map['session_id'] as String,
      status: ConversationStatus.fromString(map['status'] as String),
      createdAt: DateTime.parse(map['created_at'] as String),
      eventCount: map['event_count'] as int,
      lastEventAt: map['last_event_at'] != null
          ? DateTime.parse(map['last_event_at'] as String)
          : null,
      firstMessagePreview: map['first_message_preview'] as String?,
      subjectRecordId: map['subject_record_id'] as String?,
      subjectRecordText: map['subject_record_text'] as String?,
      subjectRecordStatus: map['subject_record_status'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'conversation_id': conversationId,
      'session_id': sessionId,
      'status': status.name,
      'created_at': createdAt.toIso8601String(),
      'event_count': eventCount,
      'last_event_at': lastEventAt?.toIso8601String(),
      'first_message_preview': firstMessagePreview,
      'subject_record_id': subjectRecordId,
      'subject_record_text': subjectRecordText,
      'subject_record_status': subjectRecordStatus,
    };
  }
}

class ConversationEvent {
  const ConversationEvent({
    required this.eventId,
    required this.conversationId,
    required this.sequence,
    required this.role,
    required this.content,
    this.occurredAt,
    required this.receivedAt,
  });

  final String eventId;
  final String conversationId;
  final int sequence;
  final EventRole role;
  final String content;
  final DateTime? occurredAt;
  final DateTime receivedAt;

  factory ConversationEvent.fromMap(Map<String, dynamic> map) {
    return ConversationEvent(
      eventId: map['event_id'] as String,
      conversationId: map['conversation_id'] as String,
      sequence: map['sequence'] as int,
      role: EventRole.fromString(map['role'] as String),
      content: map['content'] as String,
      occurredAt: map['occurred_at'] != null
          ? DateTime.parse(map['occurred_at'] as String)
          : null,
      receivedAt: DateTime.parse(map['received_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'event_id': eventId,
      'conversation_id': conversationId,
      'sequence': sequence,
      'role': role.name,
      'content': content,
      'occurred_at': occurredAt?.toIso8601String(),
      'received_at': receivedAt.toIso8601String(),
    };
  }
}
