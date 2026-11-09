import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:voice_agent/core/models/routine.dart';
import 'package:voice_agent/features/routines/domain/routines_repository.dart';
import 'package:voice_agent/features/routines/presentation/routine_detail_screen.dart';
import 'package:voice_agent/features/routines/presentation/routines_providers.dart';

import '../fake_routines_repository.dart';

Routine _morning() => sampleRoutine(
      startTime: '08:00',
      nextDue: '2026-10-28',
      steps: const [
        RoutineStep(text: 'Meditate', sortOrder: 1),
        RoutineStep(text: 'Exercise', sortOrder: 2),
      ],
    );

Future<void> _pumpScreen(
  WidgetTester tester,
  FakeRoutinesRepository repo, {
  String routineId = 'rtn-1',
  Widget Function(BuildContext, GoRouterState)? editBuilder,
}) async {
  final router = GoRouter(
    initialLocation: '/agenda/routines/$routineId',
    routes: [
      GoRoute(
        path: '/agenda/routines/:id',
        builder: (context, state) =>
            RoutineDetailScreen(routineId: state.pathParameters['id']!),
        routes: [
          GoRoute(
            path: 'edit',
            builder: editBuilder ??
                (context, state) =>
                    Text('Edit form ${state.pathParameters['id']}'),
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
}

void main() {
  late FakeRoutinesRepository repo;

  setUp(() {
    repo = FakeRoutinesRepository()..detail = _morning();
  });

  group('RoutineDetailScreen, recurring', () {
    testWidgets('shows name, status, kind, schedule, next day and steps',
        (tester) async {
      await _pumpScreen(tester, repo);

      expect(
        find.descendant(
            of: find.byType(AppBar), matching: find.text('Morning routine')),
        findsOneWidget,
      );
      expect(find.text('active'), findsOneWidget);
      expect(find.text('recurring'), findsOneWidget);
      expect(find.byKey(const Key('detail-missed-chip')), findsOneWidget);
      expect(find.text('every day · at 08:00'), findsOneWidget);
      expect(find.text('Next: 2026-10-28'), findsOneWidget);
      expect(find.text('- Meditate'), findsOneWidget);
      expect(find.text('- Exercise'), findsOneWidget);
    });

    testWidgets('lists the ticks, each with Undo; no Start, no versions',
        (tester) async {
      repo.occurrences = [
        sampleOccurrence(id: 'o1', scheduledFor: '2026-10-26'),
        sampleOccurrence(
            id: 'o2',
            scheduledFor: '2026-10-25',
            status: OccurrenceStatus.skipped),
      ];
      await _pumpScreen(tester, repo);

      expect(find.byKey(const Key('occurrence-o1')), findsOneWidget);
      expect(find.text('skipped'), findsOneWidget);
      expect(find.byKey(const Key('occurrence-undo-o2')), findsOneWidget);
      expect(find.byTooltip('Start'), findsNothing);
      expect(find.byKey(const Key('detail-previous-version')), findsNothing);
      expect(find.byKey(const Key('detail-next-version')), findsNothing);

      await tester.ensureVisible(find.byKey(const Key('occurrence-undo-o1')));
      await tester.tap(find.byKey(const Key('occurrence-undo-o1')));
      await tester.pumpAndSettle();

      expect(repo.calls, contains('unresolve rtn-1 2026-10-26'));
    });

    testWidgets('no ticks yet', (tester) async {
      await _pumpScreen(tester, repo);

      expect(find.byKey(const Key('detail-no-occurrences')), findsOneWidget);
      expect(find.byKey(const Key('detail-done-button')), findsNothing);
    });

    testWidgets('an active routine offers Edit, Pause, End after… and Archive',
        (tester) async {
      await _pumpScreen(tester, repo);

      for (final key in [
        'detail-edit-button',
        'detail-pause-button',
        'detail-end-button',
        'detail-archive-button',
      ]) {
        expect(find.byKey(Key(key)), findsOneWidget, reason: key);
      }
      expect(find.byKey(const Key('detail-activate-button')), findsNothing);
      final pause = tester.widget<OutlinedButton>(
          find.byKey(const Key('detail-pause-button')));
      expect(pause.onPressed, isNotNull);

      await tester.tap(find.byKey(const Key('detail-edit-button')));
      await tester.pumpAndSettle();
      expect(find.text('Edit form rtn-1'), findsOneWidget);
    });

    testWidgets('a paused routine can be edited and resumed', (tester) async {
      repo.detail = sampleRoutine(status: RoutineStatus.paused);
      await _pumpScreen(tester, repo);

      expect(find.byKey(const Key('detail-edit-button')), findsOneWidget);
      expect(find.byKey(const Key('detail-activate-button')), findsOneWidget);
      expect(find.byKey(const Key('detail-pause-button')), findsNothing);
    });

    testWidgets('an archived routine offers nothing', (tester) async {
      repo.detail = sampleRoutine(status: RoutineStatus.archived);
      await _pumpScreen(tester, repo);

      expect(find.text('archived'), findsOneWidget);
      for (final key in [
        'detail-edit-button',
        'detail-activate-button',
        'detail-pause-button',
        'detail-end-button',
        'detail-archive-button',
      ]) {
        expect(find.byKey(Key(key)), findsNothing, reason: key);
      }
    });

    testWidgets('End after… patches the picked last day', (tester) async {
      await _pumpScreen(tester, repo);

      await tester.ensureVisible(find.byKey(const Key('detail-end-button')));
      await tester.tap(find.byKey(const Key('detail-end-button')));
      await tester.pumpAndSettle();
      expect(find.text('Last day it occurs'), findsOneWidget);
      await tester.tap(find.text('End after'));
      await tester.pumpAndSettle();

      expect(repo.lastPatch!.toMap(), {'last_day': '2026-10-27'});
    });

    testWidgets('archive asks first', (tester) async {
      await _pumpScreen(tester, repo);

      await tester.ensureVisible(find.byKey(const Key('detail-archive-button')));
      await tester.tap(find.byKey(const Key('detail-archive-button')));
      await tester.pumpAndSettle();

      expect(find.text('Archive “Morning routine”?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('archive-confirm-button')));
      await tester.pumpAndSettle();
      expect(repo.calls, contains('archive rtn-1'));
    });

    testWidgets('a saved edit reloads the routine in place', (tester) async {
      await _pumpScreen(
        tester,
        repo,
        editBuilder: (context, state) => TextButton(
          onPressed: () => context.pop(sampleRoutine()),
          child: const Text('Save edit'),
        ),
      );

      await tester.tap(find.byKey(const Key('detail-edit-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save edit'));
      await tester.pumpAndSettle();

      // The list reloads when the page closes.
      expect(repo.calls, ['detail rtn-1', 'detail rtn-1']);
    });

    testWidgets('error state shows retry button', (tester) async {
      repo.fetchError = RoutinesGeneralException('Not found');
      await _pumpScreen(tester, repo);

      expect(find.byKey(const Key('detail-retry-button')), findsOneWidget);
      expect(find.text('Not found'), findsOneWidget);
    });
  });

  group('RoutineDetailScreen, one-off and some day', () {
    testWidgets('an open task is ticked off with Done', (tester) async {
      repo.detail = sampleRoutine(
          name: 'Call the plumber',
          dueOn: '2026-10-30',
          dueWindow: TimeWindow.week);
      await _pumpScreen(tester, repo);

      expect(find.text('one-off'), findsOneWidget);
      expect(find.text('within a week from 2026-10-30'), findsOneWidget);
      expect(find.byKey(const Key('detail-missed-chip')), findsNothing);
      expect(find.byKey(const Key('detail-end-button')), findsNothing);
      expect(find.byKey(const Key('detail-no-occurrences')), findsNothing);

      await tester.tap(find.byKey(const Key('detail-done-button')));
      await tester.pumpAndSettle();

      expect(repo.lastResolve,
          (routineId: 'rtn-1', day: null, status: OccurrenceStatus.done));
    });

    testWidgets('a some-day routine can be skipped', (tester) async {
      repo.detail = sampleRoutine(kind: RoutineKind.someday);
      await _pumpScreen(tester, repo);

      expect(find.text('some day'), findsWidgets);
      await tester.tap(find.byKey(const Key('detail-skip-button')));
      await tester.pumpAndSettle();

      expect(repo.lastResolve!.status, OccurrenceStatus.skipped);
    });

    testWidgets('a ticked task shows its tick and Undo', (tester) async {
      repo.detail = sampleRoutine(
          dueOn: '2026-10-30',
          ended: true,
          resolved: sampleOccurrence(scheduledFor: '2026-10-30'));
      await _pumpScreen(tester, repo);

      expect(find.text('done'), findsOneWidget);
      expect(find.byKey(const Key('detail-resolved')), findsOneWidget);
      expect(find.byKey(const Key('detail-done-button')), findsNothing);

      await tester.tap(find.byKey(const Key('detail-undo-button')));
      await tester.pumpAndSettle();

      expect(repo.lastUnresolve, (routineId: 'rtn-1', day: null));
    });

    testWidgets('a paused task is not ticked off', (tester) async {
      repo.detail = sampleRoutine(
          dueOn: '2026-10-30', status: RoutineStatus.paused);
      await _pumpScreen(tester, repo);

      expect(find.byKey(const Key('detail-not-tickable')), findsOneWidget);
      expect(find.byKey(const Key('detail-done-button')), findsNothing);
    });

    testWidgets('a refused tick shows the reason', (tester) async {
      repo.detail = sampleRoutine(kind: RoutineKind.someday);
      repo.actionError = RoutineAlreadyResolvedException('already resolved');
      await _pumpScreen(tester, repo);

      await tester.tap(find.byKey(const Key('detail-done-button')));
      await tester.pumpAndSettle();

      expect(find.text('already resolved'), findsOneWidget);
    });
  });

  test('a routine opened again loads afresh', () async {
    final repo = FakeRoutinesRepository();
    final container = ProviderContainer(overrides: [
      routinesRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(container.dispose);

    final first =
        container.listen(routineDetailNotifierProvider('rtn-1'), (_, _) {});
    await Future<void>.delayed(Duration.zero);
    first.close();
    await Future<void>.delayed(Duration.zero);
    container.listen(routineDetailNotifierProvider('rtn-1'), (_, _) {});
    await Future<void>.delayed(Duration.zero);

    expect(repo.calls, ['detail rtn-1', 'detail rtn-1']);
  });
}
