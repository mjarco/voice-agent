import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/models/today.dart';

void main() {
  test('reads the view of ADR-API-124 with its calls', () {
    final v = TodayView.fromMap({
      'day': '2026-11-15',
      'title': 'Niedziela, 15 listopada',
      'food': {
        'has_target': true,
        'left_kcal': 540,
        'reserve_kcal': 600,
        'warning': 'low',
        'line': 'Zostało 540 kcal — mniej niż zapas',
        'next_meal': {'menu_entry_id': 'm1', 'slot_label': 'Kolacja', 'name': 'Sałatka', 'kcal': 450},
        'nudge': null,
      },
      'agenda': {
        'items': [
          {'kind': 'meeting', 'time': '16:00', 'title': 'Dentysta'},
          {
            'kind': 'task',
            'key': 'r:a:2026-11-12',
            'routine_id': 'a',
            'title': 'Czynsz',
            'overdue': true,
            'note': 'od 12.11',
            'done': {'method': 'POST', 'path': '/api/v1/routines/a/resolve', 'body': {'status': 'done'}},
            'undo': {'method': 'DELETE', 'path': '/api/v1/routines/a/resolve?scheduled_for=2026-11-12'},
          },
        ],
        'tasks_open': 1,
        'tasks_overdue': 1,
      },
      'matters': {'in_progress': 0, 'items': []},
      'shopping': {'to_buy': 2, 'line': 'Spożywczy 2', 'stores': [{'id': 'grocery', 'label': 'Spożywczy', 'count': 2}]},
    });
    expect(v.food.warning, FoodWarning.low);
    expect(v.food.nextMeal!.slotLabel, 'Kolacja');
    expect(v.agenda.items.first.isTask, isFalse);
    final task = v.agenda.items[1];
    expect(task.isTask, isTrue);
    expect(task.done!.apiPath, '/routines/a/resolve');
    expect(task.undo!.apiPath, '/routines/a/resolve?scheduled_for=2026-11-12');
    expect(task.skip, isNull);
    expect(v.shopping.storeIds, ['grocery']);
  });

  test('a missing block reads as empty, not as a crash', () {
    final v = TodayView.fromMap({'day': '2026-11-15'});
    expect(v.food.hasTarget, isFalse);
    expect(v.agenda.items, isEmpty);
    expect(v.food.warning, FoodWarning.none);
  });
}
