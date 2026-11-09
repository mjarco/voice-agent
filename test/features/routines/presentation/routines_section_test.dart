import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:voice_agent/core/models/routine.dart';
import 'package:voice_agent/features/routines/domain/routines_repository.dart';
import 'package:voice_agent/features/routines/presentation/routines_providers.dart';
import 'package:voice_agent/features/routines/presentation/routines_section.dart';

import '../fake_routines_repository.dart';

/// The section as the Agenda shows it, at the end of a list, opened unless
/// [open] is false.
Future<void> _pumpScreen(
  WidgetTester tester,
  FakeRoutinesRepository repo, {
  bool open = true,
}) async {
  final router = GoRouter(
    initialLocation: '/agenda',
    routes: [
      GoRoute(
        path: '/agenda',
        builder: (context, state) => Scaffold(
          body: ListView(children: const [RoutinesSection()]),
        ),
        routes: [
          GoRoute(
            path: 'routines/new',
            builder: (context, state) =>
                const Scaffold(body: Text('New form')),
          ),
          GoRoute(
            path: 'routines/:id',
            builder: (context, state) =>
                Scaffold(body: Text('Detail ${state.pathParameters['id']}')),
          ),
        ],
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
  if (open) {
    await tester.tap(find.byKey(const Key('agenda-routines-section')));
    await tester.pumpAndSettle();
  }
}

void main() {
  late FakeRoutinesRepository repo;

  setUp(() {
    repo = FakeRoutinesRepository();
  });

  group('RoutinesSection', () {
    testWidgets('is folded, with the count of live routines',
        (tester) async {
      repo.routines = [
        sampleRoutine(id: 'r1', name: 'Trening'),
        sampleRoutine(
            id: 'p1', name: 'Swim', status: RoutineStatus.paused),
        sampleRoutine(id: 'arch', name: 'Old', status: RoutineStatus.archived),
      ];
      await _pumpScreen(tester, repo, open: false);

      expect(find.text('Routines (2)'), findsOneWidget);
      expect(find.text('Trening'), findsNothing);
      expect(find.byKey(const Key('routines-new-button')), findsNothing);
    });

    testWidgets('opening it reads the routines again', (tester) async {
      await _pumpScreen(tester, repo, open: false);
      final reads = repo.fetchCount;
      repo.routines = [sampleRoutine(id: 'r1', name: 'Added elsewhere')];

      await tester.tap(find.byKey(const Key('agenda-routines-section')));
      await tester.pumpAndSettle();

      expect(repo.fetchCount, reads + 1);
      expect(find.text('Added elsewhere'), findsOneWidget);
    });

    testWidgets('shows the empty state', (tester) async {
      await _pumpScreen(tester, repo);

      expect(find.text('No routines or tasks yet'), findsOneWidget);
    });

    testWidgets('a recurring card shows the schedule in words',
        (tester) async {
      repo.routines = [
        sampleRoutine(
            id: 'r1',
            name: 'Trening',
            rrule: 'FREQ=WEEKLY;BYDAY=MO,WE',
            startTime: '18:00',
            lastDay: '2026-12-31',
            nextDue: '2026-10-28'),
      ];
      await _pumpScreen(tester, repo);

      expect(find.byKey(const Key('routines-section-recurring')),
          findsOneWidget);
      expect(find.text('Trening'), findsOneWidget);
      expect(find.text('Mon, Wed · at 18:00 · until 2026-12-31'),
          findsOneWidget);
      expect(find.text('Next: 2026-10-28'), findsOneWidget);
    });

    testWidgets('tasks and some-day routines have their own sections',
        (tester) async {
      repo.routines = [
        sampleRoutine(
            id: 't1',
            name: 'Call the plumber',
            dueOn: '2026-10-30',
            dueWindow: TimeWindow.week),
        sampleRoutine(
            id: 's1', name: 'Paint the fence', kind: RoutineKind.someday),
        sampleRoutine(
            id: 'p1', name: 'Swim', status: RoutineStatus.paused),
      ];
      await _pumpScreen(tester, repo);

      expect(find.byKey(const Key('routines-section-tasks')), findsOneWidget);
      expect(find.text('within a week from 2026-10-30'), findsOneWidget);
      expect(
          find.byKey(const Key('routines-section-someday')), findsOneWidget);
      expect(find.text('some day'), findsOneWidget);
      expect(find.byKey(const Key('routines-section-paused')), findsOneWidget);
      expect(find.byKey(const Key('routine-resume-p1')), findsOneWidget);
      expect(find.byKey(const Key('routines-section-recurring')),
          findsNothing);
    });

    testWidgets('an active routine can be paused from its card',
        (tester) async {
      repo.routines = [sampleRoutine(id: 'r1')];
      await _pumpScreen(tester, repo);

      await tester.tap(find.byKey(const Key('routine-pause-r1')));
      await tester.pumpAndSettle();

      expect(repo.calls, contains('pause r1'));
    });

    testWidgets('done and ended routines fold under one section',
        (tester) async {
      repo.routines = [
        sampleRoutine(id: 'live', name: 'Live'),
        sampleRoutine(
            id: 'done', name: 'Done', ended: true, lastDay: '2026-10-20'),
        sampleRoutine(
            id: 'task',
            name: 'Ticked task',
            dueOn: '2026-10-20',
            ended: true,
            resolved: sampleOccurrence(routineId: 'task')),
        sampleRoutine(id: 'arch', name: 'Old', status: RoutineStatus.archived),
      ];
      await _pumpScreen(tester, repo);

      expect(find.text('Done and ended (3)'), findsOneWidget);
      expect(find.text('Old'), findsNothing);

      await tester.tap(find.text('Done and ended (3)'));
      await tester.pumpAndSettle();

      expect(find.text('Live'), findsOneWidget);
      expect(find.text('every day · ended after 2026-10-20'), findsOneWidget);
      expect(find.text('ENDED'), findsOneWidget);
      expect(find.text('DONE'), findsOneWidget);
      expect(find.text('ARCHIVED'), findsOneWidget);
      expect(find.byKey(const Key('routine-pause-done')), findsNothing);
    });

    testWidgets('tapping a card opens its detail', (tester) async {
      repo.routines = [sampleRoutine(id: 'r1')];
      await _pumpScreen(tester, repo);

      await tester.tap(find.byKey(const Key('routine-card-r1')));
      await tester.pumpAndSettle();

      expect(find.text('Detail r1'), findsOneWidget);
    });

    testWidgets('New opens the form', (tester) async {
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
