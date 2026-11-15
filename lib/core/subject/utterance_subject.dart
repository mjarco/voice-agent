import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The subject of an utterance (ADR-NET-008; personal-agent's ADR-API-126):
/// Dzień, or the matter whose screen was in front when it was said.
class UtteranceSubject {
  const UtteranceSubject._(this.matterId);

  /// Dzień: every tool, today's behaviour.
  static const day = UtteranceSubject._(null);

  /// Sprawa: the matter [id].
  const UtteranceSubject.matter(String id) : matterId = id;

  /// The matter's id, null for Dzień.
  final String? matterId;

  bool get isDay => matterId == null;

  /// How a transcript keeps it: null for Dzień, `matter:<id>`.
  String? get key => isDay ? null : 'matter:$matterId';

  /// What the voice and chat routes take; null for Dzień, which sends none.
  Map<String, dynamic>? toJson() =>
      isDay ? null : {'kind': 'matter', 'matter_id': matterId};

  /// A kept key read back; anything unknown is Dzień.
  static UtteranceSubject ofKey(String? key) {
    const prefix = 'matter:';
    if (key != null && key.startsWith(prefix) && key.length > prefix.length) {
      return UtteranceSubject.matter(key.substring(prefix.length));
    }
    return day;
  }

  /// The subject of the screen at [path]: a matter's screen in the Sprawy
  /// tab (`/matters/<id>`) or over Dziś (`/matter/<id>`); anything else is
  /// Dzień. The new-matter form is not a matter.
  static UtteranceSubject ofLocation(String path) {
    final parts = Uri.parse(path).pathSegments;
    if (parts.length == 2 &&
        (parts[0] == 'matters' || parts[0] == 'matter') &&
        parts[1].isNotEmpty &&
        parts[1] != 'new') {
      return UtteranceSubject.matter(parts[1]);
    }
    return day;
  }

  @override
  bool operator ==(Object other) =>
      other is UtteranceSubject && other.matterId == matterId;

  @override
  int get hashCode => matterId.hashCode;

  @override
  String toString() => key ?? 'day';
}

/// Reads the subject when an utterance ends (ADR-NET-008). The app sets it
/// once the router exists, to the router's location and the app's lifecycle;
/// unset, it is Dzień.
final utteranceSubjectReaderProvider =
    StateProvider<UtteranceSubject Function()>((ref) => () => UtteranceSubject.day);
