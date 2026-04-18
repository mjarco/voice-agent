enum RecordType {
  topic,
  question,
  decision,
  actionItem,
  constraint,
  preference,
  summaryNote,
  suggestion,
  journalNote,
  routineProposal;

  static RecordType fromString(String value) {
    return switch (value) {
      'topic' => RecordType.topic,
      'question' => RecordType.question,
      'decision' => RecordType.decision,
      'action_item' => RecordType.actionItem,
      'constraint' => RecordType.constraint,
      'preference' => RecordType.preference,
      'summary_note' => RecordType.summaryNote,
      'suggestion' => RecordType.suggestion,
      'journal_note' => RecordType.journalNote,
      'routine_proposal' => RecordType.routineProposal,
      _ => throw ArgumentError('Unknown RecordType: $value'),
    };
  }

  String toJson() {
    return switch (this) {
      RecordType.topic => 'topic',
      RecordType.question => 'question',
      RecordType.decision => 'decision',
      RecordType.actionItem => 'action_item',
      RecordType.constraint => 'constraint',
      RecordType.preference => 'preference',
      RecordType.summaryNote => 'summary_note',
      RecordType.suggestion => 'suggestion',
      RecordType.journalNote => 'journal_note',
      RecordType.routineProposal => 'routine_proposal',
    };
  }
}

enum RecordStatus {
  active,
  superseded,
  promoted,
  done;

  static RecordStatus fromString(String value) {
    return RecordStatus.values.firstWhere((e) => e.name == value);
  }
}

enum OriginRole {
  user,
  agent,
  system;

  static OriginRole fromString(String value) {
    return OriginRole.values.firstWhere((e) => e.name == value);
  }
}

class ConversationRecord {
  const ConversationRecord({
    required this.recordId,
    required this.conversationId,
    required this.recordType,
    required this.subjectRef,
    required this.payload,
    required this.confidence,
    required this.originRole,
    required this.assertionMode,
    required this.userEndorsed,
    required this.sourceEventRefs,
  });

  final String recordId;
  final String conversationId;
  final RecordType recordType;
  final String subjectRef;
  final Map<String, dynamic> payload;
  final double confidence;
  final OriginRole originRole;
  final String assertionMode;
  final bool userEndorsed;
  final List<String> sourceEventRefs;

  factory ConversationRecord.fromMap(Map<String, dynamic> map) {
    return ConversationRecord(
      recordId: map['record_id'] as String,
      conversationId: map['conversation_id'] as String,
      recordType: RecordType.fromString(map['record_type'] as String),
      subjectRef: map['subject_ref'] as String,
      payload: Map<String, dynamic>.from(map['payload'] as Map),
      confidence: (map['confidence'] as num).toDouble(),
      originRole: OriginRole.fromString(map['origin_role'] as String),
      assertionMode: map['assertion_mode'] as String,
      userEndorsed: map['user_endorsed'] as bool,
      sourceEventRefs: (map['source_event_refs'] as List<dynamic>)
          .cast<String>(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'record_id': recordId,
      'conversation_id': conversationId,
      'record_type': recordType.toJson(),
      'subject_ref': subjectRef,
      'payload': payload,
      'confidence': confidence,
      'origin_role': originRole.name,
      'assertion_mode': assertionMode,
      'user_endorsed': userEndorsed,
      'source_event_refs': sourceEventRefs,
    };
  }
}
