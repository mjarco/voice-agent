/// The owner's day as personal-agent composes it (`GET /api/v1/today?v=1`,
/// ADR-API-124 of personal-agent). The words come composed, in Polish; the
/// app only draws them. In core because Dziś shows it and the home-screen
/// widget (V2 of the redesign) will count from it.
class TodayView {
  const TodayView({
    required this.day,
    required this.title,
    required this.food,
    required this.agenda,
    required this.matters,
    required this.shopping,
  });

  /// The view version this app reads.
  static const version = 1;

  final String day;
  final String title;
  final TodayFood food;
  final TodayAgenda agenda;
  final TodayMatters matters;
  final TodayShopping shopping;

  factory TodayView.fromMap(Map<String, dynamic> m) => TodayView(
        day: m['day'] as String? ?? '',
        title: m['title'] as String? ?? '',
        food: TodayFood.fromMap(_map(m['food'])),
        agenda: TodayAgenda.fromMap(_map(m['agenda'])),
        matters: TodayMatters.fromMap(_map(m['matters'])),
        shopping: TodayShopping.fromMap(_map(m['shopping'])),
      );

  /// The same day with the agenda item [key] taken off, as a swipe leaves it
  /// until the day is read again.
  TodayView withoutItem(String key) => TodayView(
        day: day,
        title: title,
        food: food,
        agenda: TodayAgenda(
          items: [for (final i in agenda.items) if (i.key != key) i],
          tasksOpen: agenda.tasksOpen,
          tasksOverdue: agenda.tasksOverdue,
          moreTasks: agenda.moreTasks,
          line: agenda.line,
        ),
        matters: matters,
        shopping: shopping,
      );
}

Map<String, dynamic> _map(Object? v) =>
    v is Map<String, dynamic> ? v : const <String, dynamic>{};

List<Map<String, dynamic>> _list(Object? v) => v is List
    ? [for (final e in v) if (e is Map<String, dynamic>) e]
    : const [];

/// What a day's calories warn of.
enum FoodWarning {
  none,

  /// Less than the target's reserve is left.
  low,

  /// The target's top is passed.
  over;

  static FoodWarning of(Object? v) => switch (v) {
        'low' => FoodWarning.low,
        'over' => FoodWarning.over,
        _ => FoodWarning.none,
      };
}

class TodayFood {
  const TodayFood({
    required this.hasTarget,
    required this.leftKcal,
    required this.reserveKcal,
    required this.warning,
    required this.line,
    required this.nextMeal,
    required this.menuToday,
    required this.menuTomorrow,
    required this.nudge,
    this.kcalMax,
  });

  final bool hasTarget;

  /// The target's top, for the bar under the number (off-roadmap S2).
  final int? kcalMax;
  final int? leftKcal;
  final int reserveKcal;
  final FoodWarning warning;

  /// The block's one sentence ("Zostało 540 kcal — mniej niż zapas").
  final String line;
  final TodayNextMeal? nextMeal;
  final bool menuToday;
  final bool menuTomorrow;
  final TodayNudge? nudge;

  factory TodayFood.fromMap(Map<String, dynamic> m) {
    final next = m['next_meal'];
    final nudge = m['nudge'];
    return TodayFood(
      hasTarget: m['has_target'] == true,
      leftKcal: (m['left_kcal'] as num?)?.toInt(),
      reserveKcal: (m['reserve_kcal'] as num?)?.toInt() ?? 0,
      warning: FoodWarning.of(m['warning']),
      line: m['line'] as String? ?? '',
      nextMeal: next is Map<String, dynamic> ? TodayNextMeal.fromMap(next) : null,
      menuToday: m['menu_today'] == true,
      menuTomorrow: m['menu_tomorrow'] == true,
      nudge: nudge is Map<String, dynamic> ? TodayNudge.fromMap(nudge) : null,
      kcalMax: (m['kcal_max'] as num?)?.toInt(),
    );
  }
}

class TodayNextMeal {
  const TodayNextMeal({
    required this.menuEntryId,
    required this.slotLabel,
    required this.name,
    required this.kcal,
  });

  final String menuEntryId;
  final String slotLabel;
  final String name;
  final int kcal;

  factory TodayNextMeal.fromMap(Map<String, dynamic> m) => TodayNextMeal(
        menuEntryId: m['menu_entry_id'] as String? ?? '',
        slotLabel: m['slot_label'] as String? ?? '',
        name: m['name'] as String? ?? '',
        kcal: (m['kcal'] as num?)?.toInt() ?? 0,
      );
}

/// A nudge to set the menu of [day].
class TodayNudge {
  const TodayNudge({required this.day, required this.text});

  final String day;
  final String text;

  factory TodayNudge.fromMap(Map<String, dynamic> m) => TodayNudge(
        day: m['day'] as String? ?? '',
        text: m['text'] as String? ?? '',
      );
}

class TodayAgenda {
  const TodayAgenda({
    required this.items,
    required this.tasksOpen,
    required this.tasksOverdue,
    required this.moreTasks,
    required this.line,
  });

  final List<TodayItem> items;
  final int tasksOpen;
  final int tasksOverdue;
  final int moreTasks;

  /// "Na dziś nic." when nothing is listed, else empty.
  final String line;

  factory TodayAgenda.fromMap(Map<String, dynamic> m) => TodayAgenda(
        items: [for (final e in _list(m['items'])) TodayItem.fromMap(e)],
        tasksOpen: (m['tasks_open'] as num?)?.toInt() ?? 0,
        tasksOverdue: (m['tasks_overdue'] as num?)?.toInt() ?? 0,
        moreTasks: (m['more_tasks'] as num?)?.toInt() ?? 0,
        line: m['line'] as String? ?? '',
      );
}

/// A meeting or a task due. A task carries its calls.
class TodayItem {
  const TodayItem({
    required this.isTask,
    required this.title,
    this.time = '',
    this.key = '',
    this.routineId = '',
    this.overdue = false,
    this.note = '',
    this.done,
    this.skip,
    this.undo,
  });

  final bool isTask;
  final String title;
  final String time;
  final String key;
  final String routineId;
  final bool overdue;
  final String note;
  final TodayAction? done;
  final TodayAction? skip;
  final TodayAction? undo;

  factory TodayItem.fromMap(Map<String, dynamic> m) => TodayItem(
        isTask: m['kind'] == 'task',
        title: m['title'] as String? ?? '',
        time: m['time'] as String? ?? '',
        key: m['key'] as String? ?? '',
        routineId: m['routine_id'] as String? ?? '',
        overdue: m['overdue'] == true,
        note: m['note'] as String? ?? '',
        done: TodayAction.maybe(m['done']),
        skip: TodayAction.maybe(m['skip']),
        undo: TodayAction.maybe(m['undo']),
      );
}

/// One call of personal-agent's API, its path from the server's root.
class TodayAction {
  const TodayAction({required this.method, required this.path, this.body});

  final String method;
  final String path;
  final Map<String, dynamic>? body;

  static TodayAction? maybe(Object? v) {
    if (v is! Map<String, dynamic>) return null;
    final method = v['method'];
    final path = v['path'];
    if (method is! String || path is! String) return null;
    final body = v['body'];
    return TodayAction(
      method: method,
      path: path,
      body: body is Map<String, dynamic> ? body : null,
    );
  }

  /// The path below the client's base URL (`…/api/v1`).
  String get apiPath =>
      path.startsWith('/api/v1/') ? path.substring('/api/v1'.length) : path;
}

class TodayMatters {
  const TodayMatters({
    required this.inProgress,
    required this.items,
    required this.more,
  });

  final int inProgress;
  final List<TodayMatter> items;
  final int more;

  factory TodayMatters.fromMap(Map<String, dynamic> m) => TodayMatters(
        inProgress: (m['in_progress'] as num?)?.toInt() ?? 0,
        items: [for (final e in _list(m['items'])) TodayMatter.fromMap(e)],
        more: (m['more'] as num?)?.toInt() ?? 0,
      );
}

class TodayMatter {
  const TodayMatter({required this.id, required this.title, required this.line});

  final String id;
  final String title;
  final String line;

  factory TodayMatter.fromMap(Map<String, dynamic> m) => TodayMatter(
        id: m['id'] as String? ?? '',
        title: m['title'] as String? ?? '',
        line: m['line'] as String? ?? '',
      );
}

class TodayShopping {
  const TodayShopping({required this.toBuy, required this.line, required this.storeIds});

  final int toBuy;
  final String line;

  /// The store types with something to buy, in the catalogue's order.
  final List<String> storeIds;

  factory TodayShopping.fromMap(Map<String, dynamic> m) => TodayShopping(
        toBuy: (m['to_buy'] as num?)?.toInt() ?? 0,
        line: m['line'] as String? ?? '',
        storeIds: [
          for (final s in _list(m['stores']))
            if (s['id'] is String) s['id'] as String,
        ],
      );
}
