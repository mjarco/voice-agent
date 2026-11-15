import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/home_widget/home_widget_numbers.dart';
import 'package:voice_agent/core/models/today.dart';

TodayView _view({
  bool hasTarget = true,
  int? left = 540,
  String warning = '',
  int open = 3,
  int overdue = 1,
  int matters = 4,
}) =>
    TodayView.fromMap({
      'day': '2026-11-15',
      'food': {'has_target': hasTarget, 'left_kcal': left, 'warning': warning},
      'agenda': {'tasks_open': open, 'tasks_overdue': overdue},
      'matters': {'in_progress': matters},
    });

final _at = DateTime(2026, 11, 15, 9, 5);

void main() {
  group('polishPlural', () {
    String z(int n) => '$n ${polishPlural(n, 'zadanie', 'zadania', 'zadań')}';

    test('one, few and many, the teens many', () {
      expect(
        [0, 1, 2, 4, 5, 11, 12, 14, 21, 22, 25, 102, 112].map(z),
        [
          '0 zadań', '1 zadanie', '2 zadania', '4 zadania', '5 zadań',
          '11 zadań', '12 zadań', '14 zadań', '21 zadań', '22 zadania',
          '25 zadań', '102 zadania', '112 zadań',
        ],
      );
    });
  });

  group('HomeWidgetNumbers.of', () {
    test('the owner\'s three numbers, as 06 §4 draws them', () {
      final n = HomeWidgetNumbers.of(_view(warning: 'low'), _at);
      expect(n.day, '2026-11-15');
      expect(n.kcal, '540 kcal');
      expect(n.kcalLabel, 'zostało · mniej niż zapas');
      expect(n.kcalWarning, FoodWarning.low);
      expect(n.tasks, '3 zadania');
      expect(n.tasksLabel, '1 zaległe');
      expect(n.tasksOverdue, isTrue);
      expect(n.matters, '4 sprawy w toku');
      expect(n.updated, '09:05');
    });

    test('above the reserve it only says what is left', () {
      final n = HomeWidgetNumbers.of(_view(left: 920), _at);
      expect(n.kcal, '920 kcal');
      expect(n.kcalLabel, 'zostało');
      expect(n.kcalWarning, FoodWarning.none);
    });

    test('past the target the number is how much over', () {
      final n = HomeWidgetNumbers.of(_view(left: -120, warning: 'over'), _at);
      expect(n.kcal, '120 kcal');
      expect(n.kcalLabel, 'ponad cel');
      expect(n.kcalWarning, FoodWarning.over);
    });

    test('without a target there is no number and no warning', () {
      final n = HomeWidgetNumbers.of(
          _view(hasTarget: false, left: null, warning: 'low'), _at);
      expect(n.kcal, '—');
      expect(n.kcalLabel, 'bez celu');
      expect(n.kcalWarning, FoodWarning.none);
    });

    test('none overdue reads "na dziś"; the counts take their forms', () {
      final n = HomeWidgetNumbers.of(
          _view(open: 1, overdue: 0, matters: 5), _at);
      expect(n.tasks, '1 zadanie');
      expect(n.tasksLabel, 'na dziś');
      expect(n.tasksOverdue, isFalse);
      expect(n.matters, '5 spraw w toku');
      expect(HomeWidgetNumbers.of(_view(overdue: 5), _at).tasksLabel,
          '5 zaległych');
      expect(HomeWidgetNumbers.of(_view(matters: 1), _at).matters,
          '1 sprawa w toku');
    });

    test('the data carries every key TodayWidgetProvider.kt reads', () {
      final data = HomeWidgetNumbers.of(_view(warning: 'low'), _at).toData();
      expect(data.keys.toSet(), {
        'day', 'kcal', 'kcal_label', 'kcal_warning', 'tasks', 'tasks_label',
        'tasks_overdue', 'matters', 'updated',
      });
      expect(data['kcal_warning'], 'low');
      expect(data['tasks_overdue'], true);
    });
  });
}
