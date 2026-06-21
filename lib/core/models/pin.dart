// Read-only DTOs for the personal-agent pins API (proposal 045).
//
// Two DTOs share this file — matching `agenda.dart`'s several-related-classes
// layout — because they are a single read contract: the lean list row
// (`PinSummary`) and the full reference (`PinDetail`). Pins are created only by
// voice in chat; the client never writes them, so there is no `toMap`.

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
    this.sourceEventIds = const [],
    required this.createdAt,
  });

  final String recordId;
  final String pinName;
  final String? topicLabel;

  /// Verbatim markdown body of the saved reference.
  final String text;
  final List<String> aliases;
  final List<String> sourceEventIds;
  final DateTime createdAt;

  factory PinDetail.fromMap(Map<String, dynamic> map) {
    return PinDetail(
      recordId: map['record_id'] as String,
      pinName: map['pin_name'] as String,
      topicLabel: map['topic_label'] as String?,
      text: map['text'] as String,
      aliases: _stringList(map['aliases']),
      sourceEventIds: _stringList(map['source_event_ids']),
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}

List<String> _stringList(dynamic value) {
  if (value == null) return const [];
  return (value as List<dynamic>).map((e) => e as String).toList();
}
