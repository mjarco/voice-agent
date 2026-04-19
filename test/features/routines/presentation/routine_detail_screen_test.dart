import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:voice_agent/core/models/routine.dart';
import 'package:voice_agent/features/routines/domain/routines_repository.dart';
import 'package:voice_agent/features/routines/presentation/routine_detail_screen.dart';
import 'package:voice_agent/features/routines/presentation/routines_providers.dart';

class _StubRepository implements RoutinesRepository {
  Routine? routine;
  List<RoutineOccurrence> occurrences;
  Exception? fetchError;

  _StubRepository({
    this.routine,
    this.occurrences = const [],
    this.fetchError,
  });

  @override
  Future<Routine> fetchRoutineDetail(String id) async {
    if (fetchError != null) throw fetchError!;
    return routine ?? _defaultRoutine(id);
  }

  @override
  Future<List<RoutineOccurrence>> fetchOccurrences(String id) async {
    if (fetchError != null) throw fetchError!;
    return occurrences;
  }

  @override
  Future<List<Routine>> fetchRoutines(RoutineStatus status) async => [];

  @override
  Future<List<RoutineProposal>> fetchProposals() async => [];

  @override
  Future<void> activateRoutine(String id) async {}

  @override
  Future<void> pauseRoutine(String id) async {}

  @override
  Future<void> archiveRoutine(String id) async {}

  @override
  Future<void> triggerRoutine(String id, String scheduledFor) async {}

  @override
  Future<void> updateOccurrenceStatus(
    String routineId,
    String occurrenceId,
    OccurrenceStatus status,
  ) async {}

  @override
  Future<void> approveProposal(String proposalId) async {}

  @override
  Future<void> rejectProposal(String proposalId) async {}

  Routine _defaultRoutine(String id) => Routine(
        id: id,
        sourceRecordId: 'src-1',
        name: 'Morning routine',
        rrule: 'FREQ=DAILY',
        cadence: 'daily',
        status: RoutineStatus.active,
        templates: const [
          RoutineTemplate(text: 'Meditate', sortOrder: 1),
          RoutineTemplate(text: 'Exercise', sortOrder: 2),
        ],
        nextOccurrence: const RoutineNextOccurrence(
          date: '2026-04-20',
          timeWindow: TimeWindow.day,
        ),
        createdAt: DateTime(2026, 4, 1),
        updatedAt: DateTime(2026, 4, 18),
      );
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  RoutinesRepository? repository,
  String routineId = 'rtn-1',
}) async {
  final repo = repository ?? _StubRepository();
  final router = GoRouter(
    initialLocation: '/routines/$routineId',
    routes: [
      GoRoute(
        path: '/routines/:id',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return RoutineDetailScreen(routineId: id);
        },
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        routinesRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('RoutineDetailScreen', () {
    testWidgets('renders routine name in AppBar', (tester) async {
      await _pumpScreen(tester);

      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('Morning routine'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('shows status chip', (tester) async {
      await _pumpScreen(tester);

      expect(find.byKey(const Key('detail-status-chip')), findsOneWidget);
      expect(find.text('active'), findsOneWidget);
    });

    testWidgets('shows cadence chip', (tester) async {
      await _pumpScreen(tester);

      expect(find.text('daily'), findsOneWidget);
    });

    testWidgets('shows next occurrence', (tester) async {
      await _pumpScreen(tester);

      expect(find.byKey(const Key('detail-next-occurrence')), findsOneWidget);
      expect(find.text('Next: 2026-04-20'), findsOneWidget);
    });

    testWidgets('shows templates', (tester) async {
      await _pumpScreen(tester);

      expect(find.text('Templates'), findsOneWidget);
      expect(find.text('- Meditate'), findsOneWidget);
      expect(find.text('- Exercise'), findsOneWidget);
    });

    testWidgets('shows no occurrences message when empty', (tester) async {
      await _pumpScreen(tester);

      expect(
        find.byKey(const Key('detail-no-occurrences')),
        findsOneWidget,
      );
    });

    testWidgets('renders occurrence cards', (tester) async {
      final repo = _StubRepository(
        occurrences: [
          RoutineOccurrence(
            id: 'occ-1',
            routineId: 'rtn-1',
            scheduledFor: '2026-04-19',
            timeWindow: TimeWindow.day,
            status: OccurrenceStatus.pending,
            createdAt: DateTime(2026, 4, 19),
            updatedAt: DateTime(2026, 4, 19),
          ),
        ],
      );

      await _pumpScreen(tester, repository: repo);

      expect(find.byKey(const Key('occurrence-occ-1')), findsOneWidget);
      expect(find.text('2026-04-19'), findsOneWidget);
    });

    testWidgets('pending occurrence shows start, done, skip buttons',
        (tester) async {
      final repo = _StubRepository(
        occurrences: [
          RoutineOccurrence(
            id: 'occ-1',
            routineId: 'rtn-1',
            scheduledFor: '2026-04-19',
            timeWindow: TimeWindow.day,
            status: OccurrenceStatus.pending,
            createdAt: DateTime(2026, 4, 19),
            updatedAt: DateTime(2026, 4, 19),
          ),
        ],
      );

      await _pumpScreen(tester, repository: repo);

      expect(
          find.byKey(const Key('occurrence-start-occ-1')), findsOneWidget);
      expect(
          find.byKey(const Key('occurrence-done-occ-1')), findsOneWidget);
      expect(
          find.byKey(const Key('occurrence-skip-occ-1')), findsOneWidget);
    });

    testWidgets('done occurrence shows no action buttons', (tester) async {
      final repo = _StubRepository(
        occurrences: [
          RoutineOccurrence(
            id: 'occ-1',
            routineId: 'rtn-1',
            scheduledFor: '2026-04-19',
            timeWindow: TimeWindow.day,
            status: OccurrenceStatus.done,
            createdAt: DateTime(2026, 4, 19),
            updatedAt: DateTime(2026, 4, 19),
          ),
        ],
      );

      await _pumpScreen(tester, repository: repo);

      expect(
          find.byKey(const Key('occurrence-start-occ-1')), findsNothing);
      expect(
          find.byKey(const Key('occurrence-done-occ-1')), findsNothing);
      expect(
          find.byKey(const Key('occurrence-skip-occ-1')), findsNothing);
    });

    testWidgets('active routine shows pause, trigger, archive buttons',
        (tester) async {
      await _pumpScreen(tester);

      expect(
        find.byKey(const Key('detail-pause-button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('detail-trigger-button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('detail-archive-button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('detail-activate-button')),
        findsNothing,
      );
    });

    testWidgets('draft routine shows activate and archive buttons',
        (tester) async {
      final repo = _StubRepository(
        routine: Routine(
          id: 'rtn-1',
          sourceRecordId: 'src-1',
          name: 'Draft routine',
          rrule: 'FREQ=DAILY',
          status: RoutineStatus.draft,
          createdAt: DateTime(2026, 4, 1),
          updatedAt: DateTime(2026, 4, 18),
        ),
      );

      await _pumpScreen(tester, repository: repo);

      expect(
        find.byKey(const Key('detail-activate-button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('detail-archive-button')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('detail-pause-button')), findsNothing);
      expect(find.byKey(const Key('detail-trigger-button')), findsNothing);
    });

    testWidgets('archived routine shows no action buttons', (tester) async {
      final repo = _StubRepository(
        routine: Routine(
          id: 'rtn-1',
          sourceRecordId: 'src-1',
          name: 'Archived routine',
          rrule: 'FREQ=DAILY',
          status: RoutineStatus.archived,
          createdAt: DateTime(2026, 4, 1),
          updatedAt: DateTime(2026, 4, 18),
        ),
      );

      await _pumpScreen(tester, repository: repo);

      expect(find.byKey(const Key('detail-activate-button')), findsNothing);
      expect(find.byKey(const Key('detail-pause-button')), findsNothing);
      expect(find.byKey(const Key('detail-trigger-button')), findsNothing);
      expect(find.byKey(const Key('detail-archive-button')), findsNothing);
    });

    testWidgets('archive shows confirmation dialog', (tester) async {
      await _pumpScreen(tester);

      await tester.tap(find.byKey(const Key('detail-archive-button')));
      await tester.pumpAndSettle();

      expect(find.text('Archive routine?'), findsOneWidget);
      expect(find.byKey(const Key('archive-confirm-button')),
          findsOneWidget);
    });

    testWidgets('error state shows retry button', (tester) async {
      final repo = _StubRepository(
        fetchError: RoutinesGeneralException('Not found'),
      );

      await _pumpScreen(tester, repository: repo);

      expect(find.byKey(const Key('detail-retry-button')), findsOneWidget);
      expect(find.text('Not found'), findsOneWidget);
    });
  });
}
