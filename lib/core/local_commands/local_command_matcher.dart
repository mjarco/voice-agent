/// Decision returned by [LocalCommandMatcher.match].
///
/// `passthrough` — utterance is not a recognised local command; the
///   transcript should flow to the backend unchanged.
/// `replayLast` — utterance matches a replay-last whitelist entry; the
///   caller should re-speak the last buffered reply and skip the backend.
sealed class LocalCommandDecision {
  const LocalCommandDecision();
}

class LocalCommandPassthrough extends LocalCommandDecision {
  const LocalCommandPassthrough();
}

class LocalCommandReplayLast extends LocalCommandDecision {
  const LocalCommandReplayLast();
}

/// Whole-utterance whitelist matcher for replay-last commands (P036).
///
/// Deliberately conservative: the normalized utterance must be **exactly**
/// equal to one of the whitelist entries. Any extra content words (e.g.
/// "powtórz, że X", "Powtórz, żeby coś przerwało.") fall through to the
/// backend. We prefer false negatives (one extra LLM call) over false
/// positives (silently swallowing a real chat turn).
class LocalCommandMatcher {
  const LocalCommandMatcher();

  /// Whitelist — kept lower-case, normalized form. Add entries only after
  /// production telemetry justifies them.
  static const Set<String> _replayLastWhitelist = {
    'powtórz',
    'powtórz proszę',
    'powtórz to',
    'powtórz jeszcze raz',
    'jeszcze raz',
    'repeat',
    'say again',
    'say it again',
  };

  /// Returns the decision for [utterance].
  LocalCommandDecision match(String utterance) {
    final normalized = _normalize(utterance);
    if (normalized.isEmpty) return const LocalCommandPassthrough();
    if (_replayLastWhitelist.contains(normalized)) {
      return const LocalCommandReplayLast();
    }
    return const LocalCommandPassthrough();
  }

  /// Normalization (proposal 036, "Local-command matcher"):
  /// 1. lowercase,
  /// 2. trim leading/trailing whitespace,
  /// 3. strip trailing `. , ! ? ; :` punctuation runs,
  /// 4. collapse internal whitespace runs to a single space.
  static String _normalize(String input) {
    var s = input.toLowerCase().trim();
    // Strip a trailing run of punctuation characters.
    s = s.replaceAll(RegExp(r'[\.,!\?;:]+$'), '').trim();
    // Collapse internal whitespace runs.
    s = s.replaceAll(RegExp(r'\s+'), ' ');
    return s;
  }
}
