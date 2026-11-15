import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The subject of an utterance (ADR-NET-008, ADR-NET-009; personal-agent's
/// ADR-API-126 and ADR-API-127): Dzień, the matter whose screen was in front
/// when it was said, or the diet (Jedzenie).
class UtteranceSubject {
  const UtteranceSubject._(this.matterId, {this.isDiet = false});

  /// Dzień: every tool, today's behaviour.
  static const day = UtteranceSubject._(null);

  /// Jedzenie: the diet's screens (ADR-NET-009).
  static const diet = UtteranceSubject._(null, isDiet: true);

  /// Sprawa: the matter [id].
  const UtteranceSubject.matter(String id) : matterId = id, isDiet = false;

  /// The matter's id, null for Dzień and Jedzenie.
  final String? matterId;

  /// Whether it is Jedzenie.
  final bool isDiet;

  bool get isDay => matterId == null && !isDiet;

  /// How a transcript keeps it: null for Dzień, `matter:<id>`, `diet`.
  String? get key => isDiet ? 'diet' : isDay ? null : 'matter:$matterId';

  /// What the voice and chat routes take; null for Dzień, which sends none.
  Map<String, dynamic>? toJson() => isDiet
      ? {'kind': 'diet'}
      : isDay
          ? null
          : {'kind': 'matter', 'matter_id': matterId};

  /// A kept key read back; anything unknown is Dzień.
  static UtteranceSubject ofKey(String? key) {
    const prefix = 'matter:';
    if (key == 'diet') return diet;
    if (key != null && key.startsWith(prefix) && key.length > prefix.length) {
      return UtteranceSubject.matter(key.substring(prefix.length));
    }
    return day;
  }

  /// The subject of the screen at [path]: a matter's screen in the Sprawy
  /// tab (`/matters/<id>`) or over Dziś (`/matter/<id>`); the diet's screens
  /// (`/diet` and its children); anything else is Dzień. The new-matter form
  /// is not a matter.
  static UtteranceSubject ofLocation(String path) {
    final parts = Uri.parse(path).pathSegments;
    if (parts.isNotEmpty && parts[0] == 'diet') return diet;
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
      other is UtteranceSubject && other.matterId == matterId && other.isDiet == isDiet;

  @override
  int get hashCode => Object.hash(matterId, isDiet);

  @override
  String toString() => key ?? 'day';
}

/// Reads the subject when an utterance ends (ADR-NET-008). The app sets it
/// once the router exists, to the router's location and the app's lifecycle;
/// unset, it is Dzień.
final utteranceSubjectReaderProvider =
    StateProvider<UtteranceSubject Function()>((ref) => () => UtteranceSubject.day);
