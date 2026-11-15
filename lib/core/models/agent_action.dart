/// One thing a turn did, carried by personal-agent's reply for the card
/// under it (personal-agent ADR-API-127, C10; ADR-NET-009). Only the kinds the
/// app knows are read; any other is skipped.
class AgentAction {
  const AgentAction.mealLogged({
    required this.mealId,
    required this.name,
    required this.day,
    required this.time,
    required this.kcal,
    required this.kcalLow,
    required this.kcalHigh,
    this.proteinG,
    this.leftKcal,
    this.warning = '',
  });

  final String mealId;
  final String name;

  /// YYYY-MM-DD and HH:MM, in the owner's zone.
  final String day;
  final String time;
  final int kcal;
  final int kcalLow;
  final int kcalHigh;
  final double? proteinG;

  /// What is left of the day's target after the turn; null without a target.
  final int? leftKcal;

  /// The day's warning against the reserve: '', 'low' or 'over'.
  final String warning;

  /// The actions of a reply's `actions` field; [] when absent or unknown.
  static List<AgentAction> listFrom(Object? json) {
    if (json is! List) return const [];
    final out = <AgentAction>[];
    for (final a in json) {
      if (a is! Map || a['kind'] != 'meal_logged') continue;
      final meal = a['meal'];
      if (meal is! Map || meal['id'] is! String) continue;
      final day = a['day'] is Map ? a['day'] as Map : const {};
      out.add(AgentAction.mealLogged(
        mealId: meal['id'] as String,
        name: (meal['name'] as String?) ?? '',
        day: (meal['day'] as String?) ?? '',
        time: (meal['time'] as String?) ?? '',
        kcal: (meal['kcal'] as num?)?.round() ?? 0,
        kcalLow: (meal['kcal_low'] as num?)?.round() ?? 0,
        kcalHigh: (meal['kcal_high'] as num?)?.round() ?? 0,
        proteinG: (meal['protein_g'] as num?)?.toDouble(),
        leftKcal: (day['left_kcal'] as num?)?.round(),
        warning: (day['warning'] as String?) ?? '',
      ));
    }
    return out;
  }
}
