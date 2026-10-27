import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:voice_agent/core/models/routine.dart';
import 'package:voice_agent/features/routines/domain/routines_repository.dart';
import 'package:voice_agent/features/routines/presentation/routines_providers.dart';
import 'package:voice_agent/features/routines/presentation/routines_screen.dart';

import '../fake_routines_repository.dart';

Future<void> _pumpScreen(WidgetTester tester, FakeRoutinesRepository repo) async {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const RoutinesScreen(),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const Scaffold(body: Text('Settings')),
      ),
      GoRoute(
        path: '/routines/new',
        builder: (context, state) => const Scaffold(body: Text('New form')),
      ),
      GoRoute(
        path: '/routines/:id',
        builder: (context, state) =>
            Scaffold(body: Text('Detail ${state.pathParameters['id']}')),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        routinesRepositoryProvider.overrideWithValue(repo),
        routinesClockProvider.overrideWithValue(() => DateTime(2026, 10, 27)),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  late FakeRoutinesRepository repo;

  setUp(() {
    repo = FakeRoutinesRepository();
  });

  group('RoutinesScreen', () {
    testWidgets('has the Active, Paused and Ended tabs', (tester) async {
      await _pumpScreen(tester, repo);

      expect(find.text('Active'), findsOneWidget);
      expect(find.text('Paused'), findsOneWidget);
      expect(find.text('Ended'), findsOneWidget);
      expect(find.text('Draft'), findsNothing);
      expect(find.text('Archived'), findsNothing);
      expect(find.text('Proposals'), findsNothing);
    });

    testWidgets('the gear icon opens settings', (tester) async {
      await _pumpScreen(tester, repo);

      await tester.tap(find.byKey(const Key('routines-settings-icon')));
      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets('shows the empty state', (tester) async {
      await _pumpScreen(tester, repo);

      expect(find.text('No active routines'), findsOneWidget);
    });

    testWidgets('a card shows the schedule in words and the next day',
        (tester) async {
      repo.byStatus[RoutineStatus.active] = [
        sampleRoutine(
            id: 'r1',
            name: 'Trening',
            rrule: 'FREQ=WEEKLY;BYDAY=MO,WE',
            startTime: '18:00',
            lastDay: '2026-12-31'),
      ];
      await _pumpScreen(tester, repo);

      expect(find.text('Trening'), findsOneWidget);
      expect(find.text('Mon, Wed · at 18:00 · until 2026-12-31'),
          findsOneWidget);
    });

    testWidgets('a draft under Active carries a badge', (tester) async {
      repo.byStatus[RoutineStatus.draft] = [
        sampleRoutine(id: 'd1', status: RoutineStatus.draft),
      ];
      await _pumpScreen(tester, repo);

      expect(find.byKey(const Key('routine-badge-d1')), findsOneWidget);
      expect(find.text('DRAFT'), findsOneWidget);
    });

    testWidgets('an active routine can be paused from its card',
        (tester) async {
      repo.byStatus[RoutineStatus.active] = [sampleRoutine(id: 'r1')];
      await _pumpScreen(tester, repo);

      await tester.tap(find.byKey(const Key('routine-pause-r1')));
      await tester.pumpAndSettle();

      expect(repo.calls, contains('pause r1'));
    });

    testWidgets('Ended shows ended and archived routines', (tester) async {
      repo.byStatus[RoutineStatus.active] = [
        sampleRoutine(id: 'live', name: 'Live'),
        sampleRoutine(
            id: 'done', name: 'Done', ended: true, lastDay: '2026-10-20'),
      ];
      repo.byStatus[RoutineStatus.archived] = [
        sampleRoutine(id: 'arch', name: 'Old', status: RoutineStatus.archived),
      ];
      await _pumpScreen(tester, repo);

      await tester.tap(find.text('Ended'));
      await tester.pumpAndSettle();

      expect(find.text('Live'), findsNothing);
      expect(find.text('Done'), findsOneWidget);
      expect(find.text('every day · ended after 2026-10-20'), findsOneWidget);
      expect(find.text('Old'), findsOneWidget);
      expect(find.text('ARCHIVED'), findsOneWidget);
      expect(find.byKey(const Key('routine-pause-done')), findsNothing);
    });

    testWidgets('tapping a card opens its detail', (tester) async {
      repo.byStatus[RoutineStatus.active] = [sampleRoutine(id: 'r1')];
      await _pumpScreen(tester, repo);

      await tester.tap(find.byKey(const Key('routine-card-r1')));
      await tester.pumpAndSettle();

      expect(find.text('Detail r1'), findsOneWidget);
    });

    testWidgets('New routine opens the form', (tester) async {
      await _pumpScreen(tester, repo);

      await tester.tap(find.byKey(const Key('routines-new-button')));
      await tester.pumpAndSettle();

      expect(find.text('New form'), findsOneWidget);
    });

    testWidgets('an error shows Retry', (tester) async {
      repo.fetchError = RoutinesGeneralException('Network error');
      await _pumpScreen(tester, repo);

      expect(find.text('Network error'), findsOneWidget);
      expect(find.byKey(const Key('routines-retry-button')), findsOneWidget);
    });
  });
}
