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
//
// Pins written by hand (ADR-CORE-111 of personal-agent): `PinTextCreateRequest`
// is the `POST /pins` body that carries the text, and an edit's response is a
// `PinCreateResult` too, under a new `record_id`.

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
/// `topic_ref` is intentionally ignored: the client sends back `topic_label`,
/// not the ref (proposal 046 §Solution Design). The chat's confirm dialog edits
/// only name + topic; the pin form sends [aliases] back with a hand-written pin.
class PinSuggestion {
  const PinSuggestion({
    required this.name,
    this.topicLabel,
    this.aliases = const [],
  });

  final String name;

  /// Canonical name of a matching existing topic, or null/empty when the
  /// backend found none similar enough.
  final String? topicLabel;
  final List<String> aliases;

  factory PinSuggestion.fromMap(Map<String, dynamic> map) {
    return PinSuggestion(
      name: map['name'] as String? ?? '',
      topicLabel: map['topic_label'] as String?,
      aliases: _stringList(map['aliases']),
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

/// Body for `POST /api/v1/pins` that saves [text] as a pin with no conversation.
/// Empty optional fields are left out, as the backend's `omitempty` expects.
class PinTextCreateRequest {
  const PinTextCreateRequest({
    required this.text,
    required this.name,
    this.topicLabel,
    this.aliases = const [],
  });

  final String text;
  final String name;
  final String? topicLabel;
  final List<String> aliases;

  Map<String, dynamic> toMap() {
    final topic = topicLabel;
    return {
      'text': text,
      'name': name,
      if (topic != null && topic.isNotEmpty) 'topic_label': topic,
      if (aliases.isNotEmpty) 'aliases': aliases,
    };
  }
}

/// Result of `POST /api/v1/pins` and `PATCH /api/v1/pins/{id}`: the
/// [PinDetail] as saved plus idempotency metadata. `created` is false on an
/// idempotent re-pin; `supersededRecordId` names a prior same-name pin that was
/// replaced, or "". An edit gives the pin a new `recordId`.
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
