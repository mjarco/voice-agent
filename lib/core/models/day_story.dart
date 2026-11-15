/// The day's story as personal-agent tells it (ADR-API-128, ADR-NET-010): a
/// narration written from the day's facts, the utterances waiting to be
/// settled, and the day's timeline. The phone only draws it.
class DayStory {
  const DayStory({
    required this.day,
    this.narration,
    this.pending = const [],
    this.timeline = const [],
  });

  /// YYYY-MM-DD.
  final String day;

  /// The narration, shown only when its numbers matched the facts; null
  /// without one (the role off, the call failed, the check failed, or not
  /// asked for).
  final String? narration;

  /// Every utterance waiting, the day's and older ones, oldest first.
  final List<PendingUtterance> pending;

  final List<StoryLine> timeline;

  factory DayStory.fromMap(Map<String, dynamic> map) {
    String? narration;
    final n = map['narration'];
    if (n is Map && n['check'] is Map && (n['check'] as Map)['passed'] == true) {
      final text = n['text'];
      if (text is String && text.trim().isNotEmpty) narration = text.trim();
    }
    return DayStory(
      day: (map['day'] as String?) ?? '',
      narration: narration,
      pending: [
        for (final p in (map['pending'] as List?) ?? const [])
          if (p is Map<String, dynamic>) PendingUtterance.fromMap(p),
      ],
      timeline: [
        for (final l in (map['timeline'] as List?) ?? const [])
          if (l is Map<String, dynamic>) StoryLine.fromMap(l),
      ],
    );
  }

  DayStory withoutPending(String id) => DayStory(
        day: day,
        narration: narration,
        pending: [for (final p in pending) if (p.id != id) p],
        timeline: timeline,
      );
}

/// Words the agent could not act on, with the buttons of its guesses.
class PendingUtterance {
  const PendingUtterance({
    required this.id,
    required this.said,
    required this.day,
    required this.at,
    required this.guesses,
    this.conversationId = '',
  });

  final String id;
  final String said;

  /// When it was said: YYYY-MM-DD and HH:MM.
  final String day;
  final String at;

  /// The buttons' words, in order: index i settles with guess i.
  final List<String> guesses;
  final String conversationId;

  factory PendingUtterance.fromMap(Map<String, dynamic> map) => PendingUtterance(
        id: map['id'] as String,
        said: (map['said'] as String?) ?? '',
        day: (map['day'] as String?) ?? '',
        at: (map['at'] as String?) ?? '',
        guesses: [
          for (final g in (map['guesses'] as List?) ?? const [])
            if (g is Map) (g['label'] as String?) ?? (g['text'] as String?) ?? '',
        ],
        conversationId: (map['conversation_id'] as String?) ?? '',
      );
}

/// A line of the day's timeline.
class StoryLine {
  const StoryLine({required this.at, required this.kind, required this.text, this.kcal, this.ref = ''});

  final String at;

  /// meal, task, meeting, matter, conversation, bought.
  final String kind;
  final String text;
  final int? kcal;

  /// The id of what the line opens.
  final String ref;

  factory StoryLine.fromMap(Map<String, dynamic> map) => StoryLine(
        at: (map['at'] as String?) ?? '',
        kind: (map['kind'] as String?) ?? '',
        text: (map['text'] as String?) ?? '',
        kcal: (map['kcal'] as num?)?.round(),
        ref: (map['ref'] as String?) ?? '',
      );

  /// The route the line opens, or null.
  String? get route => switch (kind) {
        'meal' => '/diet',
        'matter' when ref.isNotEmpty => '/matter/$ref',
        'conversation' when ref.isNotEmpty => '/conversation/$ref',
        'task' when ref.isNotEmpty => '/routine/$ref',
        _ => null,
      };
}
