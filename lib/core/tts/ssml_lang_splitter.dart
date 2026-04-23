/// A single segment of text with an optional language override.
///
/// [languageCode] is null for default-language text (uses the caller's
/// resolved language). When non-null it is a BCP-47 tag like `"en-US"`.
class TtsSegment {
  const TtsSegment(this.text, {this.languageCode});

  final String text;
  final String? languageCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TtsSegment &&
          text == other.text &&
          languageCode == other.languageCode;

  @override
  int get hashCode => Object.hash(text, languageCode);

  @override
  String toString() => 'TtsSegment("$text", lang: $languageCode)';
}

/// Splits a string that may contain `<lang xml:lang="xx-YY">...</lang>` tags
/// into an ordered list of [TtsSegment]s.
///
/// Only the canonical shape emitted by backend P054 is recognized:
/// lowercase `lang` element, lowercase `xml:lang` attribute, double-quoted
/// BCP-47 value formatted as `xx-YY`. Anything else is treated as plain text.
///
/// The splitter never throws. On any malformed input it falls back to a single
/// default-language segment containing the original string.
class SsmlLangSplitter {
  SsmlLangSplitter._();

  static final RegExp _bcp47 = RegExp(r'^[a-z]{2,3}-[A-Z]{2,3}$');

  /// Parse [text] and return ordered segments. Empty or whitespace-only input
  /// returns an empty list.
  static List<TtsSegment> split(String text) {
    if (text.isEmpty) return const [];

    // Strip <speak> envelope if present.
    final stripped = _stripSpeakEnvelope(text);
    if (stripped.trim().isEmpty) return const [];

    try {
      return _parse(stripped);
    } catch (_) {
      // Fallback: single default segment with original text.
      return [TtsSegment(text)];
    }
  }

  static String _stripSpeakEnvelope(String input) {
    final trimmed = input.trim();
    if (trimmed.startsWith('<speak>') && trimmed.endsWith('</speak>')) {
      return trimmed.substring(7, trimmed.length - 8);
    }
    return input;
  }

  static List<TtsSegment> _parse(String input) {
    final segments = <TtsSegment>[];
    // Stack for nested lang tags: each entry is the language code.
    final langStack = <String>[];
    final buf = StringBuffer();
    var i = 0;

    while (i < input.length) {
      if (input[i] == '<') {
        // Try to match a closing </lang> tag.
        final closeMatch = _tryCloseTag(input, i);
        if (closeMatch != null) {
          if (langStack.isEmpty) {
            // Unmatched </lang> — treat entire input as malformed.
            return [TtsSegment(input)];
          }
          // Emit current buffer as a segment with the current language.
          _emitBuffer(buf, segments, lang: langStack.last);
          langStack.removeLast();
          i = closeMatch;
          continue;
        }

        // Try to match an opening <lang xml:lang="xx-YY"> tag.
        final openMatch = _tryOpenTag(input, i);
        if (openMatch != null) {
          // Emit accumulated plain text before this tag.
          _emitBuffer(
            buf,
            segments,
            lang: langStack.isNotEmpty ? langStack.last : null,
          );
          langStack.add(openMatch.lang);
          i = openMatch.endIndex;
          continue;
        }

        // Not a recognized tag — accumulate the '<' as plain text.
        buf.write(input[i]);
        i++;
      } else {
        buf.write(input[i]);
        i++;
      }
    }

    // If the lang stack is not empty, we have unclosed tags — malformed input.
    if (langStack.isNotEmpty) {
      return [TtsSegment(input)];
    }

    // Emit any remaining text.
    _emitBuffer(buf, segments, lang: null);

    return segments;
  }

  /// Try to match `</lang>` at position [i]. Returns the index after the tag
  /// on success, null otherwise.
  static int? _tryCloseTag(String input, int i) {
    const tag = '</lang>';
    if (i + tag.length <= input.length &&
        input.substring(i, i + tag.length) == tag) {
      return i + tag.length;
    }
    return null;
  }

  /// Try to match `<lang xml:lang="xx-YY">` at position [i].
  static _OpenTagResult? _tryOpenTag(String input, int i) {
    const prefix = '<lang xml:lang="';
    if (i + prefix.length >= input.length) return null;
    if (input.substring(i, i + prefix.length) != prefix) return null;

    // Find the closing quote.
    final quoteEnd = input.indexOf('"', i + prefix.length);
    if (quoteEnd < 0) return null;

    // The character after the closing quote must be '>'.
    if (quoteEnd + 1 >= input.length || input[quoteEnd + 1] != '>') {
      return null;
    }

    final langValue = input.substring(i + prefix.length, quoteEnd);

    // Validate BCP-47 shape: xx-YY (lowercase primary, uppercase region).
    if (!_bcp47.hasMatch(langValue)) return null;

    return _OpenTagResult(lang: langValue, endIndex: quoteEnd + 2);
  }

  /// Flush [buf] into [segments] as a segment with the given [lang], then
  /// clear the buffer. Empty buffers are elided.
  static void _emitBuffer(
    StringBuffer buf,
    List<TtsSegment> segments, {
    required String? lang,
  }) {
    if (buf.isEmpty) return;
    segments.add(TtsSegment(buf.toString(), languageCode: lang));
    buf.clear();
  }
}

class _OpenTagResult {
  const _OpenTagResult({required this.lang, required this.endIndex});
  final String lang;
  final int endIndex;
}
