import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:voice_agent/core/models/today.dart';
import 'package:voice_agent/features/today/domain/today_repository.dart';
import 'package:voice_agent/features/today/presentation/today_providers.dart';
import 'package:voice_agent/features/today/presentation/today_screen.dart';

class _FakeRepo implements TodayRepository {
  _FakeRepo(this.view);

  TodayView view;
  final runs = <String>[];

  @override
  Future<TodayView> fetchToday() async => view;

  @override
  Future<void> run(TodayAction action) async => runs.add('${action.method} ${action.apiPath} ${action.body?['status'] ?? ''}');
}

TodayView _view({String warning = ''}) => TodayView.fromMap({
      'day': '2026-11-15',
      'title': 'Niedziela, 15 listopada',
      'food': {'has_target': true, 'left_kcal': 540, 'warning': warning, 'line': 'Zostało 540 kcal'},
      'agenda': {
        'items': [
          {
            'kind': 'task',
            'key': 'r:a:2026-11-15',
            'routine_id': 'a',
            'title': 'Podlać kwiaty',
            'done': {'method': 'POST', 'path': '/api/v1/routines/a/resolve', 'body': {'status': 'done'}},
            'skip': {'method': 'POST', 'path': '/api/v1/routines/a/resolve', 'body': {'status': 'skipped'}},
            'undo': {'method': 'DELETE', 'path': '/api/v1/routines/a/resolve?scheduled_for=2026-11-15'},
          },
        ],
        'tasks_open': 1,
      },
      'matters': {'in_progress': 1, 'items': [{'id': 'm', 'title': 'Remont', 'line': 'czeka na Kasię'}]},
      'shopping': {'to_buy': 0, 'line': ''},
    });

Future<_FakeRepo> _pump(WidgetTester tester, TodayView view) async {
  final repo = _FakeRepo(view);
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, _) => const TodayScreen(field: Text('FIELD'))),
    GoRoute(path: '/agenda', builder: (_, _) => const Text('AGENDA')),
    GoRoute(path: '/routine/:id', builder: (_, s) => Text('ROUTINE ${s.pathParameters['id']}')),
    GoRoute(path: '/matter/:id', builder: (_, s) => Text('MATTER ${s.pathParameters['id']}')),
    GoRoute(path: '/diet', builder: (_, _) => const Text('DIET')),
  ]);
  await tester.pumpWidget(ProviderScope(
    overrides: [todayRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
  return repo;
}

void main() {
  testWidgets('shows the day composed by personal-agent, with the field', (tester) async {
    await _pump(tester, _view());
    expect(find.text('Niedziela, 15 listopada'), findsOneWidget);
    expect(find.text('Zostało 540 kcal'), findsOneWidget);
    expect(find.text('Podlać kwiaty'), findsOneWidget);
    expect(find.text('SPRAWY W TOKU · 1'), findsOneWidget);
    expect(find.text('czeka na Kasię'), findsOneWidget);
    expect(find.text('FIELD'), findsOneWidget);
    expect(find.text('ZAKUPY'), findsNothing, reason: 'nothing to buy, no line');
  });

  testWidgets('a swipe right runs done, left runs skip, and Cofnij undoes', (tester) async {
    final repo = await _pump(tester, _view());
    await tester.drag(find.text('Podlać kwiaty'), const Offset(500, 0));
    await tester.pumpAndSettle();
    expect(repo.runs, ['POST /routines/a/resolve done']);
    expect(find.text('Zrobione: Podlać kwiaty'), findsOneWidget);
    await tester.tap(find.text('Cofnij'));
    await tester.pumpAndSettle();
    expect(repo.runs.last, 'DELETE /routines/a/resolve?scheduled_for=2026-11-15 ');

    await tester.drag(find.text('Podlać kwiaty'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(repo.runs.last, 'POST /routines/a/resolve skipped');
  });

  testWidgets('a tap opens the task and the matter over Dziś', (tester) async {
    await _pump(tester, _view());
    await tester.tap(find.text('Podlać kwiaty'));
    await tester.pumpAndSettle();
    expect(find.text('ROUTINE a'), findsOneWidget);
  });
}
