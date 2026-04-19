import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:voice_agent/core/models/plan.dart';
import 'package:voice_agent/features/plan/domain/plan_repository.dart';
import 'package:voice_agent/features/plan/presentation/plan_providers.dart';
import 'package:voice_agent/features/plan/presentation/plan_screen.dart';

class _StubRepository implements PlanRepository {
  PlanResponse plan;
  Exception? actionError;

  _StubRepository({PlanResponse? plan}) : plan = plan ?? _emptyPlan();

  @override
  Future<PlanResponse> fetchPlan() async => plan;

  @override
  Future<void> markDone(String id) async {
    if (actionError != null) throw actionError!;
  }

  @override
  Future<void> dismiss(String id) async {
    if (actionError != null) throw actionError!;
  }

  @override
  Future<void> confirm(String id) async {
    if (actionError != null) throw actionError!;
  }

  @override
  Future<void> toggleEndorse(String id) async {
    if (actionError != null) throw actionError!;
  }
}

class _FailingRepository implements PlanRepository {
  @override
  Future<PlanResponse> fetchPlan() async => throw Exception('Network error');

  @override
  Future<void> markDone(String id) async {}

  @override
  Future<void> dismiss(String id) async {}

  @override
  Future<void> confirm(String id) async {}

  @override
  Future<void> toggleEndorse(String id) async {}
}

PlanResponse _emptyPlan() => PlanResponse(
      topics: const [],
      uncategorized: const [],
      rules: const [],
      rulesUncategorized: const [],
      completed: const [],
      completedUncategorized: const [],
      totalCount: 0,
      observedAt: DateTime(2026, 4, 18),
    );

PlanEntry _entry({
  String id = 'e-1',
  String text = 'Do thing',
  PlanBucket? bucket = PlanBucket.committed,
  RecordType? recordType,
}) =>
    PlanEntry(
      entryId: id,
      displayText: text,
      planBucket: bucket,
      recordType: recordType,
      confidence: 0.9,
      conversationId: 'conv-1',
      createdAt: DateTime(2026, 4, 18),
    );

PlanResponse _planWithActiveEntries() => PlanResponse(
      topics: [
        PlanTopicGroup(
          topicRef: 'topic:health',
          canonicalName: 'Health',
          items: [_entry(id: 'e-1', text: 'Exercise', bucket: PlanBucket.committed)],
        ),
      ],
      uncategorized: [
        _entry(id: 'e-2', text: 'Read books', bucket: PlanBucket.candidate),
        _entry(id: 'e-3', text: 'Proposed task', bucket: PlanBucket.proposed),
      ],
      rules: [
        PlanTopicGroup(
          topicRef: 'topic:work',
          canonicalName: 'Work',
          items: [
            _entry(
              id: 'r-1',
              text: 'No meetings before 10am',
              bucket: null,
              recordType: RecordType.constraint,
            ),
            _entry(
              id: 'r-2',
              text: 'Prefer async',
              bucket: null,
              recordType: RecordType.preference,
            ),
            _entry(
              id: 'r-3',
              text: 'No Jira for small tasks',
              bucket: null,
              recordType: RecordType.decision,
            ),
          ],
        ),
      ],
      rulesUncategorized: const [],
      completed: [
        PlanTopicGroup(
          topicRef: 'topic:old',
          canonicalName: 'Old',
          items: [_entry(id: 'c-1', text: 'Done item', bucket: null)],
        ),
      ],
      completedUncategorized: const [],
      totalCount: 3,
      observedAt: DateTime(2026, 4, 18),
    );

Future<void> _pumpScreen(
  WidgetTester tester, {
  PlanRepository? repository,
}) async {
  final repo = repository ?? _StubRepository();
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const PlanScreen(),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const Scaffold(body: Text('Settings')),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        planRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('PlanScreen', () {
    testWidgets('renders AppBar with Plan title', (tester) async {
      await _pumpScreen(tester);

      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('Plan'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('settings icon navigates to /settings', (tester) async {
      await _pumpScreen(tester);

      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets('renders active and rules section headers', (tester) async {
      await _pumpScreen(tester, repository: _StubRepository(plan: _planWithActiveEntries()));

      expect(find.byKey(const Key('plan-active-section')), findsOneWidget);

      await tester.scrollUntilVisible(
        find.byKey(const Key('plan-rules-section')),
        200.0,
      );
      expect(find.byKey(const Key('plan-rules-section')), findsOneWidget);
    });

    testWidgets('renders completed section header', (tester) async {
      await _pumpScreen(tester, repository: _StubRepository(plan: _planWithActiveEntries()));

      await tester.scrollUntilVisible(
        find.byKey(const Key('plan-completed-section')),
        200.0,
      );
      expect(find.byKey(const Key('plan-completed-section')), findsOneWidget);
    });

    testWidgets('renders entry cards', (tester) async {
      await _pumpScreen(tester, repository: _StubRepository(plan: _planWithActiveEntries()));

      expect(find.byKey(const Key('plan-entry-e-1')), findsOneWidget);
      expect(find.byKey(const Key('plan-entry-e-2')), findsOneWidget);
    });

    testWidgets('committed entry shows Done and Dismiss but not Confirm',
        (tester) async {
      await _pumpScreen(tester, repository: _StubRepository(plan: _planWithActiveEntries()));

      expect(find.byKey(const Key('plan-done-e-1')), findsOneWidget);
      expect(find.byKey(const Key('plan-dismiss-e-1')), findsOneWidget);
      expect(find.byKey(const Key('plan-confirm-e-1')), findsNothing);
    });

    testWidgets('candidate entry shows Confirm, Done, and Dismiss',
        (tester) async {
      await _pumpScreen(tester, repository: _StubRepository(plan: _planWithActiveEntries()));

      expect(find.byKey(const Key('plan-confirm-e-2')), findsOneWidget);
      expect(find.byKey(const Key('plan-done-e-2')), findsOneWidget);
      expect(find.byKey(const Key('plan-dismiss-e-2')), findsOneWidget);
    });

    testWidgets('proposed entry shows Done and Dismiss but not Confirm',
        (tester) async {
      await _pumpScreen(tester, repository: _StubRepository(plan: _planWithActiveEntries()));

      expect(find.byKey(const Key('plan-done-e-3')), findsOneWidget);
      expect(find.byKey(const Key('plan-dismiss-e-3')), findsOneWidget);
      expect(find.byKey(const Key('plan-confirm-e-3')), findsNothing);
    });

    testWidgets('constraint rule shows only Endorse (no Dismiss)', (tester) async {
      await _pumpScreen(tester, repository: _StubRepository(plan: _planWithActiveEntries()));

      expect(find.byKey(const Key('plan-endorse-r-1')), findsOneWidget);
      expect(find.byKey(const Key('plan-dismiss-r-1')), findsNothing);
    });

    testWidgets('preference rule shows only Endorse (no Dismiss)', (tester) async {
      await _pumpScreen(tester, repository: _StubRepository(plan: _planWithActiveEntries()));

      expect(find.byKey(const Key('plan-endorse-r-2')), findsOneWidget);
      expect(find.byKey(const Key('plan-dismiss-r-2')), findsNothing);
    });

    testWidgets('decision rule shows Dismiss and Endorse', (tester) async {
      await _pumpScreen(tester, repository: _StubRepository(plan: _planWithActiveEntries()));

      expect(find.byKey(const Key('plan-dismiss-r-3')), findsOneWidget);
      expect(find.byKey(const Key('plan-endorse-r-3')), findsOneWidget);
    });

    testWidgets('completed section is collapsed by default', (tester) async {
      await _pumpScreen(tester, repository: _StubRepository(plan: _planWithActiveEntries()));

      expect(find.byKey(const Key('plan-entry-c-1')), findsNothing);
    });

    testWidgets('tapping completed section expands it', (tester) async {
      await _pumpScreen(tester, repository: _StubRepository(plan: _planWithActiveEntries()));

      await tester.scrollUntilVisible(
        find.byKey(const Key('plan-completed-section')),
        200.0,
      );
      await tester.tap(find.byKey(const Key('plan-completed-section')));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.byKey(const Key('plan-entry-c-1')),
        200.0,
      );
      expect(find.byKey(const Key('plan-entry-c-1')), findsOneWidget);
    });

    testWidgets('tapping active section header collapses it', (tester) async {
      await _pumpScreen(tester, repository: _StubRepository(plan: _planWithActiveEntries()));

      expect(find.byKey(const Key('plan-entry-e-1')), findsOneWidget);

      await tester.tap(find.byKey(const Key('plan-active-section')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('plan-entry-e-1')), findsNothing);
    });

    testWidgets('shows empty state when plan has no active entries',
        (tester) async {
      await _pumpScreen(tester);

      expect(find.byKey(const Key('plan-empty-active')), findsOneWidget);
    });

    testWidgets('shows error state with retry button on failure', (tester) async {
      await _pumpScreen(tester, repository: _FailingRepository());

      expect(find.byKey(const Key('plan-retry-button')), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('retry button is tappable in error state', (tester) async {
      await _pumpScreen(tester, repository: _FailingRepository());

      expect(find.byKey(const Key('plan-retry-button')), findsOneWidget);
      // Tapping retry re-issues load; screen stays in error with same failing repo
      await tester.tap(find.byKey(const Key('plan-retry-button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('plan-retry-button')), findsOneWidget);
    });

    testWidgets('section counts show array lengths', (tester) async {
      await _pumpScreen(tester, repository: _StubRepository(plan: _planWithActiveEntries()));

      // Active: 1 (Health topic) + 2 (uncategorized) = 3
      // The header should show count 3 for active items
      expect(find.textContaining('Active Items (3)'), findsOneWidget);
    });
  });
}
