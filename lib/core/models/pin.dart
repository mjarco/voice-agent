// DTOs for the personal-agent pins API.
//
// Read contract (proposal 045): the lean list row (`PinSummary`) and the full
// reference (`PinDetail`).
//
// Write contract (proposal 046): pinning a chat message from the app —
// `PinSuggestion` (proposed name + topic from `POST /pins/suggest`),
// `PinCreateRequest` (the `POST /pins` body, the only `toMap` here), and
// `PinCreateResult` (the create response wrapper). The write path is reached
// through the `core` `PinWriter` port (`core/network/pin_writer.dart`), not by
// `features/chat` importing `features/pins`.

class PinSummary {
  const PinSummary({
    required this.recordId,
    required this.pinName,
    this.topicLabel,
    required this.createdAt,
  });

  final String recordId;
  final String pinName;
  final String? topicLabel;
  final DateTime createdAt;

  factory PinSummary.fromMap(Map<String, dynamic> map) {
    return PinSummary(
      recordId: map['record_id'] as String,
      pinName: map['pin_name'] as String,
      topicLabel: map['topic_label'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}

class PinDetail {
  const PinDetail({
    required this.recordId,
    required this.pinName,
    this.topicLabel,
    required this.text,
    this.aliases = const [],
    this.conversationId,
    this.sourceEventIds = const [],
    required this.createdAt,
  });

  final String recordId;
  final String pinName;
  final String? topicLabel;

  /// Verbatim markdown body of the saved reference.
  final String text;
  final List<String> aliases;

  /// Conversation the reference was pinned from. Null for legacy pins saved
  /// before the backend recorded the source (`conversation_id` omitempty).
  /// When present, the detail screen links back to that chat thread.
  final String? conversationId;
  final List<String> sourceEventIds;
  final DateTime createdAt;

  factory PinDetail.fromMap(Map<String, dynamic> map) {
    return PinDetail(
      recordId: map['record_id'] as String,
      pinName: map['pin_name'] as String,
      topicLabel: map['topic_label'] as String?,
      text: map['text'] as String,
      aliases: _stringList(map['aliases']),
      conversationId: map['conversation_id'] as String?,
      sourceEventIds: _stringList(map['source_event_ids']),
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}

List<String> _stringList(dynamic value) {
  if (value == null) return const [];
  return (value as List<dynamic>).map((e) => e as String).toList();
}

/// Proposed name + best-matching existing topic for a message, from
/// `POST /api/v1/pins/suggest`. Writes nothing on the backend.
///
/// `aliases` and `topic_ref` are intentionally ignored: the confirm dialog
/// edits only name + topic, and the client sends back `topic_label`, not the
/// ref (proposal 046 §Solution Design).
class PinSuggestion {
  const PinSuggestion({required this.name, this.topicLabel});

  final String name;

  /// Canonical name of a matching existing topic, or null/empty when the
  /// backend found none similar enough.
  final String? topicLabel;

  factory PinSuggestion.fromMap(Map<String, dynamic> map) {
    return PinSuggestion(
      name: map['name'] as String? ?? '',
      topicLabel: map['topic_label'] as String?,
    );
  }
}

/// Body for `POST /api/v1/pins` — pins a specific chat message by identity.
///
/// The client never sends pin content: the backend copies the verbatim body
/// server-side from `(conversation_id, event_id)`. `topic_label` is omitted
/// when null/empty to match the backend `omitempty`; `aliases` is out of scope
/// for V1 and never sent.
class PinCreateRequest {
  const PinCreateRequest({
    required this.conversationId,
    required this.eventId,
    required this.name,
    this.topicLabel,
  });

  final String conversationId;
  final String eventId;
  final String name;
  final String? topicLabel;

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'conversation_id': conversationId,
      'event_id': eventId,
      'name': name,
    };
    final topic = topicLabel;
    if (topic != null && topic.isNotEmpty) {
      map['topic_label'] = topic;
    }
    return map;
  }
}

/// Result of `POST /api/v1/pins`: the created (or re-pinned) [PinDetail] plus
/// idempotency metadata. `created` is false on an idempotent re-pin;
/// `supersededRecordId` names a prior same-name pin that was replaced, or "".
class PinCreateResult {
  const PinCreateResult({
    required this.pin,
    required this.created,
    this.supersededRecordId = '',
  });

  final PinDetail pin;
  final bool created;
  final String supersededRecordId;

  factory PinCreateResult.fromMap(Map<String, dynamic> map) {
    return PinCreateResult(
      pin: PinDetail.fromMap(map['pin'] as Map<String, dynamic>),
      created: map['created'] as bool? ?? false,
      supersededRecordId: map['superseded_record_id'] as String? ?? '',
    );
  }
}
