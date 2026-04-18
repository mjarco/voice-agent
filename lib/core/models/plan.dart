class PlanResponse {
  const PlanResponse({
    required this.topics,
    required this.uncategorized,
    required this.rules,
    required this.rulesUncategorized,
    required this.completed,
    required this.completedUncategorized,
    required this.totalCount,
    required this.observedAt,
  });

  final List<PlanTopicGroup> topics;
  final List<PlanEntry> uncategorized;
  final List<PlanTopicGroup> rules;
  final List<PlanEntry> rulesUncategorized;
  final List<PlanTopicGroup> completed;
  final List<PlanEntry> completedUncategorized;
  final int totalCount;
  final DateTime observedAt;

  factory PlanResponse.fromMap(Map<String, dynamic> map) {
    return PlanResponse(
      topics: _parseTopicGroups(map['topics']),
      uncategorized: _parsePlanEntries(map['uncategorized']),
      rules: _parseTopicGroups(map['rules']),
      rulesUncategorized: _parsePlanEntries(map['rules_uncategorized']),
      completed: _parseTopicGroups(map['completed']),
      completedUncategorized:
          _parsePlanEntries(map['completed_uncategorized']),
      totalCount: map['total_count'] as int,
      observedAt: DateTime.parse(map['observed_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'topics': topics.map((t) => t.toMap()).toList(),
      'uncategorized': uncategorized.map((e) => e.toMap()).toList(),
      'rules': rules.map((t) => t.toMap()).toList(),
      'rules_uncategorized':
          rulesUncategorized.map((e) => e.toMap()).toList(),
      'completed': completed.map((t) => t.toMap()).toList(),
      'completed_uncategorized':
          completedUncategorized.map((e) => e.toMap()).toList(),
      'total_count': totalCount,
      'observed_at': observedAt.toIso8601String(),
    };
  }

  static List<PlanTopicGroup> _parseTopicGroups(dynamic value) {
    if (value == null) return [];
    return (value as List<dynamic>)
        .map((e) => PlanTopicGroup.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  static List<PlanEntry> _parsePlanEntries(dynamic value) {
    if (value == null) return [];
    return (value as List<dynamic>)
        .map((e) => PlanEntry.fromMap(e as Map<String, dynamic>))
        .toList();
  }
}

class PlanTopicGroup {
  const PlanTopicGroup({
    required this.topicRef,
    required this.canonicalName,
    required this.items,
  });

  final String topicRef;
  final String canonicalName;
  final List<PlanEntry> items;

  factory PlanTopicGroup.fromMap(Map<String, dynamic> map) {
    return PlanTopicGroup(
      topicRef: map['topic_ref'] as String,
      canonicalName: map['canonical_name'] as String,
      items: (map['items'] as List<dynamic>)
          .map((e) => PlanEntry.fromMap(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'topic_ref': topicRef,
      'canonical_name': canonicalName,
      'items': items.map((i) => i.toMap()).toList(),
    };
  }
}

class PlanEntry {
  const PlanEntry({
    required this.entryId,
    required this.displayText,
    this.planBucket,
    required this.confidence,
    required this.conversationId,
    required this.createdAt,
    this.closedAt,
    this.recordType,
  });

  final String entryId;
  final String displayText;
  final String? planBucket;
  final double confidence;
  final String conversationId;
  final DateTime createdAt;
  final DateTime? closedAt;
  final String? recordType;

  factory PlanEntry.fromMap(Map<String, dynamic> map) {
    return PlanEntry(
      entryId: map['entry_id'] as String,
      displayText: map['display_text'] as String,
      planBucket: map['plan_bucket'] as String?,
      confidence: (map['confidence'] as num).toDouble(),
      conversationId: map['conversation_id'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      closedAt: map['closed_at'] != null
          ? DateTime.parse(map['closed_at'] as String)
          : null,
      recordType: map['record_type'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'entry_id': entryId,
      'display_text': displayText,
      'plan_bucket': planBucket,
      'confidence': confidence,
      'conversation_id': conversationId,
      'created_at': createdAt.toIso8601String(),
      'closed_at': closedAt?.toIso8601String(),
      'record_type': recordType,
    };
  }
}
