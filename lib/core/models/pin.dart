// DTOs for the personal-agent pins API.
//
// Read contract (proposal 045): the lean list row (`PinSummary`) and the full
// reference (`PinDetail`).
//
// Write contract (proposal 046): pinning a chat message from the app —
// `PinSuggestion` (proposed name from `POST /pins/suggest`),
// `PinCreateRequest` (the `POST /pins` body, the only `toMap` here), and
// `PinCreateResult` (the create response wrapper). The write path is reached
// through the `core` `PinWriter` port (`core/network/pin_writer.dart`), not by
// `features/chat` importing `features/pins`.
//
// Pins written by hand (ADR-CORE-111 of personal-agent): `PinTextCreateRequest`
// is the `POST /pins` body that carries the text, and an edit's response is a
// `PinCreateResult` too.
//
// Since personal-agent R2 (ADR-CORE-117) a pin has no topic and an edit keeps
// its `record_id`. Optional fields are read tolerantly: a missing or malformed
// one is empty, never an error.

class PinSummary {
  const PinSummary({
    required this.recordId,
    required this.pinName,
    required this.createdAt,
  });

  final String recordId;
  final String pinName;
  final DateTime createdAt;

  factory PinSummary.fromMap(Map<String, dynamic> map) {
    return PinSummary(
      recordId: map['record_id'] as String,
      pinName: map['pin_name'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}

class PinDetail {
  const PinDetail({
    required this.recordId,
    required this.pinName,
    required this.text,
    this.aliases = const [],
    this.conversationId,
    this.sourceEventIds = const [],
    required this.createdAt,
  });

  final String recordId;
  final String pinName;

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
      text: map['text'] as String,
      aliases: _stringList(map['aliases']),
      conversationId: _optString(map['conversation_id']),
      sourceEventIds: _stringList(map['source_event_ids']),
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}

/// A list of strings, or empty when the value is missing or not a list; items
/// that are not strings are dropped.
List<String> _stringList(dynamic value) {
  if (value is! List) return const [];
  return value.whereType<String>().toList();
}

/// A non-empty string, or null when the value is missing, empty or not a
/// string.
String? _optString(dynamic value) =>
    value is String && value.isNotEmpty ? value : null;

/// Proposed name for a message or a text, from `POST /api/v1/pins/suggest`.
/// Writes nothing on the backend. The chat's confirm dialog edits only the
/// name; the pin form sends [aliases] back with a hand-written pin.
class PinSuggestion {
  const PinSuggestion({
    required this.name,
    this.aliases = const [],
  });

  final String name;
  final List<String> aliases;

  factory PinSuggestion.fromMap(Map<String, dynamic> map) {
    final name = map['name'];
    return PinSuggestion(
      name: name is String ? name : '',
      aliases: _stringList(map['aliases']),
    );
  }
}

/// Body for `POST /api/v1/pins` — pins a specific chat message by identity.
///
/// The client never sends pin content: the backend copies the verbatim body
/// server-side from `(conversation_id, event_id)`; `aliases` is out of scope
/// for V1 and never sent.
class PinCreateRequest {
  const PinCreateRequest({
    required this.conversationId,
    required this.eventId,
    required this.name,
  });

  final String conversationId;
  final String eventId;
  final String name;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'conversation_id': conversationId,
      'event_id': eventId,
      'name': name,
    };
  }
}

/// Body for `POST /api/v1/pins` that saves [text] as a pin with no conversation.
/// Empty optional fields are left out, as the backend's `omitempty` expects.
class PinTextCreateRequest {
  const PinTextCreateRequest({
    required this.text,
    required this.name,
    this.aliases = const [],
  });

  final String text;
  final String name;
  final List<String> aliases;

  Map<String, dynamic> toMap() {
    return {
      'text': text,
      'name': name,
      if (aliases.isNotEmpty) 'aliases': aliases,
    };
  }
}

/// Result of `POST /api/v1/pins` and `PATCH /api/v1/pins/{id}`: the
/// [PinDetail] as saved plus idempotency metadata. `created` is false on an
/// idempotent re-pin; `supersededRecordId` names a prior same-name pin that was
/// replaced, or "".
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
      created: map['created'] is bool ? map['created'] as bool : false,
      supersededRecordId: _optString(map['superseded_record_id']) ?? '',
    );
  }
}
