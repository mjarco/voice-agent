import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/features/diet/domain/diet_models.dart';
import 'package:voice_agent/features/diet/presentation/diet_days.dart';

void main() {
  DietDay day({int? left, String warning = '', bool target = true}) => DietDay.fromMap({
        'day': '2026-11-15',
        'target': target ? {'from': '2026-11-01', 'kcal_min': 1800, 'kcal_max': 2000, 'reserve_kcal': 600} : null,
        'meals': [
          {'id': 'x', 'time': '12:40', 'name': 'Pierogi', 'estimate': {'kcal': 750, 'kcal_low': 650, 'kcal_high': 850}},
        ],
        'eaten': {'kcal': 750},
        'left_kcal': left,
        'warning': warning,
        'planned': [],
      });

  test('the day says what Dziś says', () {
    expect(day(left: 1250).line, 'Zostało 1250 kcal');
    expect(day(left: 540, warning: 'low').line, 'Zostało 540 kcal — mniej niż zapas');
    expect(day(left: -150, warning: 'over').line, 'Ponad cel o 150 kcal');
    expect(day(target: false).line, 'Ustaw cel, a pokażę, ile zostało');
  });

  test('a meal shows its range', () {
    expect(day().meals.single.estimate.label, '750 (650–850)');
    expect(const DietEstimate(kcal: 220, low: 220, high: 220).label, '220');
  });

  test('days are named in Polish', () {
    final today = DateTime(2026, 11, 14);
    expect(dayLabel(DateTime(2026, 11, 14), today: today), 'Dziś, sob 14.11');
    expect(dayLabel(DateTime(2026, 11, 15), today: today), 'Jutro, ndz 15.11');
    expect(dayKey(DateTime(2026, 1, 5)), '2026-01-05');
    expect(slotLabel('second_breakfast'), 'Drugie śniadanie');
  });
}
