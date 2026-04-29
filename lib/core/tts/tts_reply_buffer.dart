/// Holds the most recently spoken successful agent reply for client-side
/// replay (proposal 036).
///
/// The buffer is intentionally tiny: at v1 the buffer holds **one** entry —
/// the last successful reply, with the language code that was passed to TTS.
/// On replay we re-feed `(text, languageCode)` to the same `TtsService` that
/// originally spoke it, so the platform engine produces equivalent speech
/// without an LLM round-trip.
///
/// The buffer lives in `core/` (it has no platform deps) and is wired in
/// `core/tts/tts_provider.dart`. Only the agent-reply path
/// (`SyncWorker._handleReply`) writes to it via `BufferingTtsService`;
/// error/feedback `speak` calls deliberately bypass it.
class TtsReplyEntry {
  const TtsReplyEntry({required this.text, this.languageCode});

  final String text;
  final String? languageCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TtsReplyEntry &&
          other.text == text &&
          other.languageCode == languageCode;

  @override
  int get hashCode => Object.hash(text, languageCode);

  @override
  String toString() =>
      'TtsReplyEntry(text: $text, languageCode: $languageCode)';
}

/// Port for the TTS replay buffer. Implementations are responsible for
/// storage; the decorator (`BufferingTtsService`) and the consumer
/// (`SyncWorker`) only depend on this interface.
abstract class TtsReplyBuffer {
  /// Records `(text, languageCode)` as the most recent successful reply.
  void record(String text, {String? languageCode});

  /// Returns the most recent entry, or `null` if the buffer is empty.
  TtsReplyEntry? last();

  /// Empties the buffer.
  void clear();
}

/// Default in-memory implementation. Holds the single most recent entry.
///
/// Per proposal 036, v1 is `n = 1` — at most one entry. LRU semantics are
/// trivially satisfied: `record()` always replaces the previous entry.
class InMemoryTtsReplyBuffer implements TtsReplyBuffer {
  TtsReplyEntry? _entry;

  @override
  void record(String text, {String? languageCode}) {
    _entry = TtsReplyEntry(text: text, languageCode: languageCode);
  }

  @override
  TtsReplyEntry? last() => _entry;

  @override
  void clear() {
    _entry = null;
  }
}
