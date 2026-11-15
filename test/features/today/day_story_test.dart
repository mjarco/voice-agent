import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:voice_agent/core/models/day_story.dart';
import 'package:voice_agent/core/models/today.dart';
import 'package:voice_agent/core/providers/agent_turns_provider.dart';
import 'package:voice_agent/features/today/domain/today_repository.dart';
import 'package:voice_agent/features/today/presentation/day_story_view.dart';
import 'package:voice_agent/features/today/presentation/today_providers.dart';
import 'package:voice_agent/features/today/presentation/today_screen.dart';

import 'fake_day_story_repository.dart';

class _TodayRepo implements TodayRepository {
  @override
  Future<TodayView> fetchToday() async => TodayView.fromMap({
        'day': '2026-11-15',
        'title': 'Niedziela, 15 listopada',
        'food': {'has_target': true, 'left_kcal': 540, 'warning': '', 'line': 'Zostało 540 kcal'},
        'agenda': {'items': [], 'tasks_open': 0},
        'matters': {'in_progress': 0, 'items': []},
        'shopping': {'to_buy': 0, 'line': ''},
      });

  @override
  Future<void> run(TodayAction action) async {}
}

DayStory _story({bool passed = true}) => DayStory.fromMap({
      'day': '2026-11-15',
      'narration': {'text': 'Zrobiłeś cały trening i kupiłeś cebulę.', 'check': {'passed': passed, 'unmatched': []}},
      'pending': [
        {
          'id': 'p1', 'said': 'G-Shot.', 'day': '2026-11-15', 'at': '11:40', 'conversation_id': 'c1',
          'guesses': [
            {'kind': 'shopping', 'text': 'G-Shot', 'label': 'Do zakupów: G-Shot'},
            {'kind': 'task', 'text': 'Kupić G-Shot', 'label': 'Zadanie: Kupić G-Shot'},
          ],
        },
        {'id': 'p0', 'said': 'chyba za dużo chleba', 'day': '2026-11-14', 'at': '20:15', 'guesses': []},
      ],
      'timeline': [
        {'at': '08:10', 'kind': 'meal', 'text': 'Owsianka', 'kcal': 455, 'ref': 'm1'},
        {'at': '11:05', 'kind': 'conversation', 'text': 'Remont: wycena', 'ref': 'c9'},
      ],
    });

Future<FakeDayStoryRepository> _pump(WidgetTester tester, DateTime now, DayStory story) async {
  final repo = FakeDayStoryRepository(story);
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, _) => TodayScreen(clock: () => now)),
    GoRoute(path: '/day/:date', builder: (_, s) => DayStoryScreen(day: s.pathParameters['date']!)),
    GoRoute(path: '/diet', builder: (_, _) => const Text('DIET')),
    GoRoute(path: '/conversation/:id', builder: (_, s) => Text('CONV ${s.pathParameters['id']}')),
  ]);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      todayRepositoryProvider.overrideWithValue(_TodayRepo()),
      dayStoryRepositoryProvider.overrideWithValue(repo),
    ],
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
  return repo;
}

void main() {
  group('DayStory.fromMap', () {
    test('a narration whose check failed is not shown', () {
      expect(_story(passed: false).narration, isNull);
      expect(_story().narration, startsWith('Zrobiłeś'));
      expect(_story().pending.first.guesses, ['Do zakupów: G-Shot', 'Zadanie: Kupić G-Shot']);
      expect(_story().timeline.last.route, '/conversation/c9');
    });
  });

  testWidgets('in the evening Dziś shows the narration and what waits, and a guess settles it', (tester) async {
    final repo = await _pump(tester, DateTime(2026, 11, 15, 20, 30), _story());
    expect(repo.fetches, ['2026-11-15 narrate=true']);
    expect(find.byKey(const Key('story-narration')), findsOneWidget);
    expect(find.text('DO ROZSTRZYGNIĘCIA · 2'), findsOneWidget);
    expect(find.textContaining('niedziela, 14 listopada 20:15'), findsNothing); // 14 Nov is a Saturday
    expect(find.textContaining('sobota, 14 listopada 20:15'), findsOneWidget);

    await tester.tap(find.byKey(const Key('story-guess-p1-1')));
    await tester.pumpAndSettle();
    expect(repo.settled, ['p1 1']);
    expect(find.byKey(const Key('story-pending-p1')), findsNothing);

    await tester.tap(find.byKey(const Key('story-none-p0')));
    await tester.pumpAndSettle();
    expect(repo.settled, ['p1 1', 'p0 none']);
  });

  testWidgets('before the evening only a count, with no narration asked for', (tester) async {
    final repo = await _pump(tester, DateTime(2026, 11, 15, 10, 0), _story());
    expect(repo.fetches, ['2026-11-15 narrate=false']);
    expect(find.byKey(const Key('story-block')), findsNothing);
    expect(find.text('Do rozstrzygnięcia: 2'), findsOneWidget);

    await tester.tap(find.byKey(const Key('story-pending-count')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('story-day-title')), findsOneWidget);
    expect(find.text('niedziela, 15 listopada'), findsOneWidget);
    expect(find.text('Owsianka'), findsOneWidget);
    await tester.tap(find.text('Remont: wycena'));
    await tester.pumpAndSettle();
    expect(find.text('CONV c9'), findsOneWidget);
  });

  testWidgets('a failed settle brings the line back', (tester) async {
    final repo = await _pump(tester, DateTime(2026, 11, 15, 20, 0), _story());
    repo.failSettle = true;
    await tester.tap(find.byKey(const Key('story-guess-p1-0')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('story-pending-p1')), findsOneWidget);
    expect(find.text('Nie udało się. Spróbuj jeszcze raz.'), findsOneWidget);
  });

  test('a guess that ran tells the app a turn changed the day', () async {
    final c = ProviderContainer(overrides: [dayStoryRepositoryProvider.overrideWithValue(FakeDayStoryRepository(_story()))]);
    addTearDown(c.dispose);
    final key = (day: '2026-11-15', narrate: false);
    final sub = c.listen(dayStoryProvider(key), (_, _) {});
    addTearDown(sub.close);
    await Future<void>.delayed(Duration.zero);
    final before = c.read(agentTurnsProvider);
    await c.read(dayStoryProvider(key).notifier).settle('p1', 0);
    expect(c.read(agentTurnsProvider), before + 1);
    await c.read(dayStoryProvider(key).notifier).settle('p0', null);
    expect(c.read(agentTurnsProvider), before + 1);
  });
}
