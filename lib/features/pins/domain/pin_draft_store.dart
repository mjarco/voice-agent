/// What the pin form holds that was not saved yet.
class PinDraft {
  const PinDraft({
    required this.title,
    required this.text,
    required this.titleTyped,
  });

  factory PinDraft.fromMap(Map<String, dynamic> map) => PinDraft(
        title: map['title'] as String,
        text: map['text'] as String,
        titleTyped: map['title_typed'] as bool,
      );

  final String title;
  final String text;

  /// False when [title] is the server's proposal, which a new one may replace.
  final bool titleTyped;

  Map<String, dynamic> toMap() => {
        'title': title,
        'text': text,
        'title_typed': titleTyped,
      };
}

/// Drafts on this device: one for a new pin, one per edited pin. A null
/// [recordId] names the new pin's draft.
abstract class PinDraftStore {
  Future<PinDraft?> load(String? recordId);

  Future<void> save(String? recordId, PinDraft draft);

  Future<void> remove(String? recordId);
}
