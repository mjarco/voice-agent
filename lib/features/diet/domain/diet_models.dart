// The diet as personal-agent serves it (`/api/v1/diet/…`, ADR-CORE-123 and
// ADR-API-124 of personal-agent).

int _int(Object? v) => (v as num?)?.toInt() ?? 0;

List<Map<String, dynamic>> _list(Object? v) => v is List
    ? [for (final e in v) if (e is Map<String, dynamic>) e]
    : const [];

class DietEstimate {
  const DietEstimate({required this.kcal, required this.low, required this.high, this.proteinG});

  final int kcal;
  final int low;
  final int high;
  final double? proteinG;

  factory DietEstimate.fromMap(Map<String, dynamic>? m) => DietEstimate(
        kcal: _int(m?['kcal']),
        low: _int(m?['kcal_low']),
        high: _int(m?['kcal_high']),
        proteinG: (m?['protein_g'] as num?)?.toDouble(),
      );

  /// "750 (650–850)", or the value alone without a range.
  String get label => low > 0 && high > 0 && (low != kcal || high != kcal)
      ? '$kcal ($low–$high)'
      : '$kcal';
}

class DietMeal {
  const DietMeal({
    required this.id,
    required this.day,
    required this.time,
    required this.name,
    required this.estimate,
  });

  final String id;
  final String day;
  final String time;
  final String name;
  final DietEstimate estimate;

  factory DietMeal.fromMap(Map<String, dynamic> m) => DietMeal(
        id: m['id'] as String? ?? '',
        day: m['day'] as String? ?? '',
        time: m['time'] as String? ?? '',
        name: m['name'] as String? ?? '',
        estimate: DietEstimate.fromMap(m['estimate'] as Map<String, dynamic>?),
      );
}

/// The mealtimes, in the order of a day, with their Polish names.
const dietSlots = [
  ('breakfast', 'Śniadanie'),
  ('second_breakfast', 'Drugie śniadanie'),
  ('lunch', 'Obiad'),
  ('snack', 'Przekąska'),
  ('dinner', 'Kolacja'),
];

String slotLabel(String slot) =>
    dietSlots.firstWhere((s) => s.$1 == slot, orElse: () => (slot, slot)).$2;

int slotOrder(String slot) {
  final i = dietSlots.indexWhere((s) => s.$1 == slot);
  return i < 0 ? dietSlots.length : i;
}

class DietMenuEntry {
  const DietMenuEntry({
    required this.id,
    required this.day,
    required this.slot,
    required this.name,
    required this.estimate,
    required this.eaten,
  });

  final String id;
  final String day;
  final String slot;
  final String name;
  final DietEstimate estimate;
  final bool eaten;

  factory DietMenuEntry.fromMap(Map<String, dynamic> m) => DietMenuEntry(
        id: m['id'] as String? ?? '',
        day: m['day'] as String? ?? '',
        slot: m['slot'] as String? ?? '',
        name: m['name'] as String? ?? '',
        estimate: DietEstimate.fromMap(m['estimate'] as Map<String, dynamic>?),
        eaten: (m['eaten_meal_id'] as String? ?? '').isNotEmpty,
      );
}

class DietTarget {
  const DietTarget({
    required this.from,
    required this.kcalMin,
    required this.kcalMax,
    required this.reserveKcal,
    this.proteinMin,
    this.note = '',
  });

  final String from;
  final int kcalMin;
  final int kcalMax;
  final int reserveKcal;
  final int? proteinMin;
  final String note;

  factory DietTarget.fromMap(Map<String, dynamic> m) => DietTarget(
        from: m['from'] as String? ?? '',
        kcalMin: _int(m['kcal_min']),
        kcalMax: _int(m['kcal_max']),
        reserveKcal: _int(m['reserve_kcal']),
        proteinMin: (m['protein_min'] as num?)?.toInt(),
        note: m['note'] as String? ?? '',
      );

  String get range => kcalMin == kcalMax ? '$kcalMax kcal' : '$kcalMin–$kcalMax kcal';
}

class DietDay {
  const DietDay({
    required this.day,
    required this.target,
    required this.meals,
    required this.eaten,
    required this.leftKcal,
    required this.warning,
    required this.planned,
  });

  final String day;
  final DietTarget? target;
  final List<DietMeal> meals;
  final DietEstimate eaten;
  final int? leftKcal;

  /// `low`, `over` or empty (ADR-API-124).
  final String warning;
  final List<DietMenuEntry> planned;

  factory DietDay.fromMap(Map<String, dynamic> m) {
    final t = m['target'];
    return DietDay(
      day: m['day'] as String? ?? '',
      target: t is Map<String, dynamic> ? DietTarget.fromMap(t) : null,
      meals: [for (final e in _list(m['meals'])) DietMeal.fromMap(e)],
      eaten: DietEstimate.fromMap(m['eaten'] as Map<String, dynamic>?),
      leftKcal: (m['left_kcal'] as num?)?.toInt(),
      warning: m['warning'] as String? ?? '',
      planned: [for (final e in _list(m['planned'])) DietMenuEntry.fromMap(e)],
    );
  }

  /// The day's one line, in the words of Dziś.
  String get line {
    final left = leftKcal;
    if (target == null || left == null) return 'Ustaw cel, a pokażę, ile zostało';
    if (warning == 'over') return 'Ponad cel o ${-left} kcal';
    if (warning == 'low') return 'Zostało $left kcal — mniej niż zapas';
    return 'Zostało $left kcal';
  }
}

class DietIngredient {
  const DietIngredient({required this.item, this.amount = ''});

  final String item;
  final String amount;

  factory DietIngredient.fromMap(Map<String, dynamic> m) => DietIngredient(
        item: m['item'] as String? ?? '',
        amount: m['amount'] as String? ?? '',
      );

  String get label => amount.isEmpty ? item : '$item, $amount';
}

class DietOwnMeal {
  const DietOwnMeal({
    required this.id,
    required this.name,
    required this.portion,
    required this.ingredients,
    required this.estimate,
  });

  final String id;
  final String name;
  final String portion;
  final List<DietIngredient> ingredients;
  final DietEstimate estimate;

  factory DietOwnMeal.fromMap(Map<String, dynamic> m) => DietOwnMeal(
        id: m['id'] as String? ?? '',
        name: m['name'] as String? ?? '',
        portion: m['portion'] as String? ?? '',
        ingredients: [for (final e in _list(m['ingredients'])) DietIngredient.fromMap(e)],
        estimate: DietEstimate.fromMap(m['estimate'] as Map<String, dynamic>?),
      );
}

class DietException implements Exception {
  DietException(this.message);

  final String message;

  @override
  String toString() => message;
}
