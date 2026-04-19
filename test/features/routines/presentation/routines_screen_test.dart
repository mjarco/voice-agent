import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:voice_agent/core/models/routine.dart';
import 'package:voice_agent/features/routines/domain/routines_repository.dart';
import 'package:voice_agent/features/routines/presentation/routines_providers.dart';
import 'package:voice_agent/features/routines/presentation/routines_screen.dart';

class _StubRepository implements RoutinesRepository {
  List<Routine> routines;
  List<RoutineProposal> proposals;
  _StubRepository({
    this.routines = const [],
    this.proposals = const [],
  });

  @override
  Future<List<Routine>> fetchRoutines(RoutineStatus status) async => routines;

  @override
  Future<List<RoutineProposal>> fetchProposals() async => proposals;

  @override
  Future<Routine> fetchRoutineDetail(String id) async =>
      throw UnimplementedError();

  @override
  Future<List<RoutineOccurrence>> fetchOccurrences(String id) async =>
      throw UnimplementedError();

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
}

Routine _sampleRoutine({
  String id = 'rtn-1',
  String name = 'Morning routine',
  RoutineStatus status = RoutineStatus.active,
  String? cadence = 'daily',
  RoutineNextOccurrence? nextOccurrence,
}) =>
    Routine(
      id: id,
      sourceRecordId: 'src-1',
      name: name,
      rrule: 'FREQ=DAILY',
      cadence: cadence,
      status: status,
      nextOccurrence: nextOccurrence,
      createdAt: DateTime(2026, 4, 1),
      updatedAt: DateTime(2026, 4, 18),
    );

RoutineProposal _sampleProposal({String id = 'prop-1'}) => RoutineProposal(
      id: id,
      name: 'Weekly review',
      cadence: 'weekly',
      items: const [RoutineProposalItem(text: 'Review items', sortOrder: 1)],
      confidence: 0.85,
      conversationId: 'conv-1',
      createdAt: DateTime(2026, 4, 18),
    );

Future<void> _pumpScreen(
  WidgetTester tester, {
  RoutinesRepository? repository,
}) async {
  final repo = repository ?? _StubRepository();
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const RoutinesScreen(),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) =>
            const Scaffold(body: Text('Settings')),
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
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('RoutinesScreen', () {
    testWidgets('renders AppBar with title', (tester) async {
      await _pumpScreen(tester);

      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('Routines'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('renders gear icon that navigates to settings',
        (tester) async {
      await _pumpScreen(tester);

      expect(find.byKey(const Key('routines-settings-icon')), findsOneWidget);

      await tester.tap(find.byKey(const Key('routines-settings-icon')));
      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets('renders four tabs', (tester) async {
      await _pumpScreen(tester);

      expect(find.text('Active'), findsOneWidget);
      expect(find.text('Draft'), findsOneWidget);
      expect(find.text('Paused'), findsOneWidget);
      expect(find.text('Archived'), findsOneWidget);
    });

    testWidgets('shows empty state when no routines', (tester) async {
      await _pumpScreen(tester);

      expect(find.byKey(const Key('routines-empty-state')), findsOneWidget);
      expect(find.text('No active routines'), findsOneWidget);
    });

    testWidgets('renders routine cards', (tester) async {
      final repo = _StubRepository(
        routines: [_sampleRoutine()],
      );

      await _pumpScreen(tester, repository: repo);

      expect(find.text('Morning routine'), findsOneWidget);
      expect(find.byKey(const Key('routine-card-rtn-1')), findsOneWidget);
    });

    testWidgets('routine card shows cadence', (tester) async {
      final repo = _StubRepository(
        routines: [_sampleRoutine(cadence: 'daily')],
      );

      await _pumpScreen(tester, repository: repo);

      expect(find.text('daily'), findsOneWidget);
    });

    testWidgets('routine card shows next occurrence date', (tester) async {
      final repo = _StubRepository(
        routines: [
          _sampleRoutine(
            nextOccurrence: const RoutineNextOccurrence(
              date: '2026-04-20',
              timeWindow: TimeWindow.day,
            ),
          ),
        ],
      );

      await _pumpScreen(tester, repository: repo);

      expect(find.text('Next: 2026-04-20'), findsOneWidget);
    });

    testWidgets('active routine shows trigger and pause buttons',
        (tester) async {
      final repo = _StubRepository(
        routines: [_sampleRoutine(status: RoutineStatus.active)],
      );

      await _pumpScreen(tester, repository: repo);

      expect(
        find.byKey(const Key('routine-trigger-rtn-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('routine-pause-rtn-1')),
        findsOneWidget,
      );
    });

    testWidgets('tapping routine card navigates to detail', (tester) async {
      final repo = _StubRepository(
        routines: [_sampleRoutine()],
      );

      await _pumpScreen(tester, repository: repo);

      await tester.tap(find.text('Morning routine'));
      await tester.pumpAndSettle();

      expect(find.text('Detail rtn-1'), findsOneWidget);
    });

    testWidgets('renders proposal cards on active tab', (tester) async {
      final repo = _StubRepository(
        proposals: [_sampleProposal()],
      );

      await _pumpScreen(tester, repository: repo);

      expect(find.text('Proposals'), findsOneWidget);
      expect(find.text('Weekly review'), findsOneWidget);
      expect(find.byKey(const Key('proposal-card-prop-1')), findsOneWidget);
    });

    testWidgets('proposal card shows cadence chip', (tester) async {
      final repo = _StubRepository(
        proposals: [_sampleProposal()],
      );

      await _pumpScreen(tester, repository: repo);

      expect(find.text('weekly'), findsOneWidget);
    });

    testWidgets('proposal card shows items', (tester) async {
      final repo = _StubRepository(
        proposals: [_sampleProposal()],
      );

      await _pumpScreen(tester, repository: repo);

      expect(find.text('- Review items'), findsOneWidget);
    });

    testWidgets('proposal card has approve and reject buttons',
        (tester) async {
      final repo = _StubRepository(
        proposals: [_sampleProposal()],
      );

      await _pumpScreen(tester, repository: repo);

      expect(
        find.byKey(const Key('proposal-approve-prop-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('proposal-reject-prop-1')),
        findsOneWidget,
      );
    });

    testWidgets('reject shows confirmation dialog', (tester) async {
      final repo = _StubRepository(
        proposals: [_sampleProposal()],
      );

      await _pumpScreen(tester, repository: repo);

      await tester.tap(find.byKey(const Key('proposal-reject-prop-1')));
      await tester.pumpAndSettle();

      expect(find.text('Reject proposal?'), findsOneWidget);
      expect(
        find.text('This proposal will be permanently dismissed.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('reject-confirm-button')), findsOneWidget);
    });

    testWidgets('reject cancel dismisses dialog', (tester) async {
      final repo = _StubRepository(
        proposals: [_sampleProposal()],
      );

      await _pumpScreen(tester, repository: repo);

      await tester.tap(find.byKey(const Key('proposal-reject-prop-1')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Reject proposal?'), findsNothing);
    });

    testWidgets('error state shows retry button', (tester) async {
      await _pumpScreen(tester, repository: _FailingRepository());

      expect(find.byKey(const Key('routines-retry-button')), findsOneWidget);
      expect(find.text('Fetch failed'), findsOneWidget);
    });

    testWidgets('switching tabs changes empty state text', (tester) async {
      await _pumpScreen(tester);

      await tester.tap(find.text('Draft'));
      await tester.pumpAndSettle();

      expect(find.text('No draft routines'), findsOneWidget);
    });
  });
}

class _FailingRepository implements RoutinesRepository {
  @override
  Future<List<Routine>> fetchRoutines(RoutineStatus status) async =>
      throw RoutinesGeneralException('Fetch failed');

  @override
  Future<List<RoutineProposal>> fetchProposals() async =>
      throw RoutinesGeneralException('Fetch failed');

  @override
  Future<Routine> fetchRoutineDetail(String id) async =>
      throw UnimplementedError();

  @override
  Future<List<RoutineOccurrence>> fetchOccurrences(String id) async =>
      throw UnimplementedError();

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
}
