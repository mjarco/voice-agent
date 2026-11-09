// DTOs for the personal-agent matters API (ADR-CORE-118 of personal-agent).
//
// A matter is something in the owner's life that runs over days or months
// and has a state. The list row is [MatterSummary]; [MatterDetail] adds the
// timeline (entries and ticks of joined routines, newest first) and the
// links (conversations, routines, pins).
//
// Fields are read tolerantly: a missing or malformed optional one is empty,
// never a TypeError. Only `id` is required.

enum MatterStatus {
  proposed,
  active,
  waiting,
  paused,
  closed,

  /// A status this app does not know yet (a newer server).
  unknown;

  static MatterStatus fromJson(dynamic value) => switch (value) {
        'proposed' => proposed,
        'active' => active,
        'waiting' => waiting,
        'paused' => paused,
        'closed' => closed,
        _ => unknown,
      };

  String toJson() => name;

  /// The status as the owner reads it.
  String get label => switch (this) {
        proposed => 'do przejrzenia',
        active => 'aktywna',
        waiting => 'czeka',
        paused => 'wstrzymana',
        closed => 'zamknięta',
        unknown => 'nieznany',
      };
}

class MatterSummary {
  const MatterSummary({
    required this.id,
    required this.title,
    this.keywords = '',
    this.status = MatterStatus.unknown,
    this.nextStep = '',
    this.waitingFor = '',
    this.fromMatterId,
    this.source = '',
    this.lastEntry = '',
    this.lastActivity,
    this.standingStill = false,
    this.linkCount = 0,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String title;

  /// Free text the owner and the agent find the matter by.
  final String keywords;
  final MatterStatus status;
  final String nextStep;
  final String waitingFor;

  /// The matter this one was split from, if any.
  final String? fromMatterId;

  /// Where the matter was opened: chat, web, phone, review.
  final String source;
  final String lastEntry;
  final DateTime? lastActivity;

  /// Nothing has happened on an open matter for a while (the server decides).
  final bool standingStill;
  final int linkCount;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory MatterSummary.fromMap(Map<String, dynamic> map) => MatterSummary(
        id: map['id'] as String,
        title: _string(map['title']),
        keywords: _string(map['keywords']),
        status: MatterStatus.fromJson(map['status']),
        nextStep: _string(map['next_step']),
        waitingFor: _string(map['waiting_for']),
        fromMatterId: _optString(map['from_matter_id']),
        source: _string(map['source']),
        lastEntry: _string(map['last_entry']),
        lastActivity: _time(map['last_activity']),
        standingStill: map['standing_still'] == true,
        linkCount: map['link_count'] is int ? map['link_count'] as int : 0,
        createdAt: _time(map['created_at']),
        updatedAt: _time(map['updated_at']),
      );

  /// Whole days since the last activity (or the last change) up to [now];
  /// null when the server sent neither.
  int? daysStill(DateTime now) {
    final since = lastActivity ?? updatedAt;
    if (since == null) return null;
    final days = now.difference(since).inDays;
    return days < 0 ? 0 : days;
  }
}

enum MatterEntryKind {
  opened,
  note,
  status,
  nextStep,
  waitingFor,
  joined,
  left,
  tick,
  unknown;

  static MatterEntryKind fromJson(dynamic value) => switch (value) {
        'opened' => opened,
        'note' => note,
        'status' => status,
        'next_step' => nextStep,
        'waiting_for' => waitingFor,
        'joined' => joined,
        'left' => left,
        'tick' => tick,
        _ => unknown,
      };

  /// What the entry records, as the owner reads it; empty for a note.
  String get label => switch (this) {
        opened => 'otwarta',
        note => '',
        status => 'status',
        nextStep => 'następny krok',
        waitingFor => 'czeka na',
        joined => 'dołączono',
        left => 'odłączono',
        tick => 'odhaczono',
        unknown => '',
      };
}

/// One line of a matter's timeline.
class MatterEntry {
  const MatterEntry({
    this.id,
    required this.kind,
    required this.text,
    this.source,
    this.conversationId,
    this.eventId,
    this.day = '',
    this.createdAt,
  });

  /// Null for a tick of a joined routine: it is undone on the routine, not
  /// removed here.
  final String? id;
  final MatterEntryKind kind;
  final String text;
  final String? source;
  final String? conversationId;
  final String? eventId;

  /// `YYYY-MM-DD` in the owner's zone.
  final String day;
  final DateTime? createdAt;

  bool get removable => id != null;

  factory MatterEntry.fromMap(Map<String, dynamic> map) => MatterEntry(
        id: _optString(map['id']),
        kind: MatterEntryKind.fromJson(map['kind']),
        text: _string(map['text']),
        source: _optString(map['source']),
        conversationId: _optString(map['conversation_id']),
        eventId: _optString(map['event_id']),
        day: _string(map['day']),
        createdAt: _time(map['created_at']),
      );
}

enum MatterLinkKind {
  conversation,
  routine,
  pin,
  unknown;

  static MatterLinkKind fromJson(dynamic value) => switch (value) {
        'conversation' => conversation,
        'routine' => routine,
        'pin' => pin,
        _ => unknown,
      };
}

/// Something joined to a matter: a conversation (or a span of it), a
/// routine, a pin.
class MatterLink {
  const MatterLink({
    required this.id,
    required this.kind,
    required this.targetId,
    this.fromEventId,
    this.toEventId,
    this.label = '',
    this.day,
    this.turns = 0,
    this.missing = false,
    this.createdAt,
  });

  final String id;
  final MatterLinkKind kind;
  final String targetId;
  final String? fromEventId;
  final String? toEventId;
  final String label;
  final String? day;
  final int turns;

  /// The target is gone (a deleted conversation, routine or pin).
  final bool missing;
  final DateTime? createdAt;

  factory MatterLink.fromMap(Map<String, dynamic> map) => MatterLink(
        id: map['id'] as String,
        kind: MatterLinkKind.fromJson(map['kind']),
        targetId: _string(map['target_id']),
        fromEventId: _optString(map['from_event_id']),
        toEventId: _optString(map['to_event_id']),
        label: _string(map['label']),
        day: _optString(map['day']),
        turns: map['turns'] is int ? map['turns'] as int : 0,
        missing: map['missing'] == true,
        createdAt: _time(map['created_at']),
      );
}

class MatterDetail {
  const MatterDetail({
    required this.matter,
    this.timeline = const [],
    this.links = const [],
  });

  final MatterSummary matter;
  final List<MatterEntry> timeline;
  final List<MatterLink> links;

  String get id => matter.id;

  factory MatterDetail.fromMap(Map<String, dynamic> map) => MatterDetail(
        matter: MatterSummary.fromMap(map),
        timeline: _maps(map['timeline']).map(MatterEntry.fromMap).toList(),
        links: _maps(map['links']).map(MatterLink.fromMap).toList(),
      );
}

String _string(dynamic value) => value is String ? value : '';

String? _optString(dynamic value) =>
    value is String && value.isNotEmpty ? value : null;

DateTime? _time(dynamic value) =>
    value is String ? DateTime.tryParse(value) : null;

Iterable<Map<String, dynamic>> _maps(dynamic value) =>
    value is List ? value.whereType<Map<String, dynamic>>() : const [];
