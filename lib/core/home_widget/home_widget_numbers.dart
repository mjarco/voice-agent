import 'package:voice_agent/core/models/today.dart';

/// What the home-screen widget shows (V2 of the redesign, workspace
/// discussion 2026-11-va-meals-dashboard, 06 §4): the owner's three numbers
/// with their words, composed from the today view. The native widget only
/// draws these strings; it keeps no logic but the day check (a widget showing
/// another day than today draws dashes, ADR-PLATFORM-015).
class HomeWidgetNumbers {
  const HomeWidgetNumbers({
    required this.day,
    required this.kcal,
    required this.kcalLabel,
    required this.kcalWarning,
    required this.tasks,
    required this.tasksLabel,
    required this.tasksOverdue,
    required this.matters,
    required this.updated,
  });

  /// The day the numbers are of, `yyyy-mm-dd`.
  final String day;

  /// "540 kcal", or "—" without a target.
  final String kcal;

  /// "zostało", "zostało · mniej niż zapas", "ponad cel", "bez celu".
  final String kcalLabel;
  final FoodWarning kcalWarning;

  /// "3 zadania".
  final String tasks;

  /// "1 zaległe", or "na dziś" with none overdue.
  final String tasksLabel;
  final bool tasksOverdue;

  /// "4 sprawy w toku".
  final String matters;

  /// When the numbers were read, `HH:mm`.
  final String updated;

  factory HomeWidgetNumbers.of(TodayView view, DateTime readAt) {
    final food = view.food;
    final left = food.leftKcal;
    final String kcal;
    final String kcalLabel;
    if (!food.hasTarget || left == null) {
      kcal = '—';
      kcalLabel = 'bez celu';
    } else if (food.warning == FoodWarning.over) {
      kcal = '${left.abs()} kcal';
      kcalLabel = 'ponad cel';
    } else {
      kcal = '$left kcal';
      kcalLabel =
          food.warning == FoodWarning.low ? 'zostało · mniej niż zapas' : 'zostało';
    }
    final open = view.agenda.tasksOpen;
    final overdue = view.agenda.tasksOverdue;
    final matters = view.matters.inProgress;
    return HomeWidgetNumbers(
      day: view.day,
      kcal: kcal,
      kcalLabel: kcalLabel,
      kcalWarning: food.hasTarget ? food.warning : FoodWarning.none,
      tasks: '$open ${polishPlural(open, 'zadanie', 'zadania', 'zadań')}',
      tasksLabel: overdue > 0
          ? '$overdue ${polishPlural(overdue, 'zaległe', 'zaległe', 'zaległych')}'
          : 'na dziś',
      tasksOverdue: overdue > 0,
      matters:
          '$matters ${polishPlural(matters, 'sprawa', 'sprawy', 'spraw')} w toku',
      updated: '${_two(readAt.hour)}:${_two(readAt.minute)}',
    );
  }

  /// The keys the native widget reads (`TodayWidgetProvider.kt`).
  Map<String, Object> toData() => {
        'day': day,
        'kcal': kcal,
        'kcal_label': kcalLabel,
        'kcal_warning': kcalWarning.name,
        'tasks': tasks,
        'tasks_label': tasksLabel,
        'tasks_overdue': tasksOverdue,
        'matters': matters,
        'updated': updated,
      };
}

String _two(int n) => n.toString().padLeft(2, '0');

/// The Polish form of a noun after [n]: 1 zadanie, 2–4 zadania (not 12–14),
/// otherwise zadań.
String polishPlural(int n, String one, String few, String many) {
  final a = n.abs();
  if (a == 1) return one;
  final tens = a % 100;
  final units = a % 10;
  if (units >= 2 && units <= 4 && (tens < 12 || tens > 14)) return few;
  return many;
}
