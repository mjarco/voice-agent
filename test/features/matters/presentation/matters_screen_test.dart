import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:voice_agent/core/models/matter.dart';
import 'package:voice_agent/features/matters/domain/matters_repository.dart';
import 'package:voice_agent/features/matters/presentation/matters_providers.dart';
import 'package:voice_agent/features/matters/presentation/matters_screen.dart';

import '../fake_matters_repository.dart';

MatterSummary _m(
  String id,
  MatterStatus status, {
  String nextStep = '',
  String lastEntry = '',
  bool still = false,
  DateTime? lastActivity,
}) =>
    MatterSummary(
      id: id,
      title: 'Sprawa $id',
      status: status,
      nextStep: nextStep,
      lastEntry: lastEntry,
      standingStill: still,
      lastActivity: lastActivity,
    );

Future<void> _pump(WidgetTester tester, FakeMattersRepository repo) async {
  final router = GoRouter(
    initialLocation: '/matters',
    routes: [
      GoRoute(
        path: '/matters',
        builder: (context, state) => const MattersScreen(),
        routes: [
          GoRoute(
            path: 'new',
            builder: (context, state) => Scaffold(
              body: TextButton(
                onPressed: () => context.pop(),
                child: const Text('Close form'),
              ),
            ),
          ),
          GoRoute(
            path: ':id',
            builder: (context, state) => Scaffold(
              body: TextButton(
                onPressed: () => context.pop(),
                child: Text('Detail ${state.pathParameters['id']}'),
              ),
            ),
          ),
        ],
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [mattersRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('MattersScreen', () {
    testWidgets('no review section without proposed matters', (tester) async {
      await _pump(
        tester,
        FakeMattersRepository(matters: [_m('a', MatterStatus.active)]),
      );

      expect(find.byKey(const Key('matters-proposed-header')), findsNothing);
      expect(find.text('Aktywne'), findsOneWidget);
      expect(find.text('Sprawa a'), findsOneWidget);
    });

    testWidgets('proposed matters come first with their count and buttons',
        (tester) async {
      await _pump(
        tester,
        FakeMattersRepository(matters: [
          _m('p1', MatterStatus.proposed, lastEntry: 'z rozmowy'),
          _m('p2', MatterStatus.proposed),
          _m('a', MatterStatus.active),
        ]),
      );

      expect(find.text('Do przejrzenia (2)'), findsOneWidget);
      expect(find.byKey(const Key('matter-accept-p1')), findsOneWidget);
      expect(find.byKey(const Key('matter-accept-closed-p1')), findsOneWidget);
      expect(find.byKey(const Key('matter-drop-p2')), findsOneWidget);
      expect(find.text('z rozmowy'), findsOneWidget);
      final header = tester.getTopLeft(find.text('Do przejrzenia (2)'));
      final active = tester.getTopLeft(find.text('Aktywne'));
      expect(header.dy, lessThan(active.dy));
    });

    testWidgets('groups follow the status order, rows show status and step',
        (tester) async {
      await _pump(
        tester,
        FakeMattersRepository(matters: [
          _m('a', MatterStatus.active, nextStep: 'zadzwonić'),
          _m('w', MatterStatus.waiting, lastEntry: 'wysłano maila'),
          _m('p', MatterStatus.paused),
          _m('c', MatterStatus.closed),
        ]),
      );

      final ys = [
        for (final h in ['Aktywne', 'Czekają', 'Wstrzymane', 'Zamknięte'])
          tester.getTopLeft(find.text(h)).dy,
      ];
      expect(ys, orderedEquals([...ys]..sort()));
      expect(find.text('aktywna · Następny krok: zadzwonić'), findsOneWidget);
      expect(find.text('czeka · wysłano maila'), findsOneWidget);
    });

    testWidgets('each matter is its own card (va-polish)', (tester) async {
      await _pump(
        tester,
        FakeMattersRepository(matters: [
          _m('a', MatterStatus.active),
          _m('b', MatterStatus.active),
        ]),
      );

      for (final id in ['a', 'b']) {
        expect(
          find.descendant(
            of: find.byKey(Key('matter-tile-$id')),
            matching: find.byType(Card),
          ),
          findsOneWidget,
        );
      }
    });

    testWidgets('a standing-still matter says for how long', (tester) async {
      await _pump(
        tester,
        FakeMattersRepository(matters: [
          _m(
            's',
            MatterStatus.active,
            still: true,
            lastActivity: DateTime.now().subtract(const Duration(days: 12)),
          ),
          _m('a', MatterStatus.active),
        ]),
      );

      expect(find.text('stoi od 12 dni'), findsOneWidget);
      expect(find.byKey(const Key('matter-still-a')), findsNothing);
    });

    testWidgets('accept moves a proposed matter into its group',
        (tester) async {
      final repo = FakeMattersRepository(
        matters: [_m('p1', MatterStatus.proposed)],
      );
      await _pump(tester, repo);

      await tester.tap(find.byKey(const Key('matter-accept-closed-p1')));
      await tester.pumpAndSettle();

      expect(repo.calls, ['accept p1 closed']);
      expect(find.byKey(const Key('matters-proposed-header')), findsNothing);
      expect(find.text('Zamknięte'), findsOneWidget);
    });

    testWidgets('drop asks first, then removes the proposal', (tester) async {
      final repo = FakeMattersRepository(
        matters: [_m('p1', MatterStatus.proposed)],
      );
      await _pump(tester, repo);

      await tester.tap(find.byKey(const Key('matter-drop-p1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('matter-drop-dialog')), findsOneWidget);
      expect(repo.calls, isEmpty);

      await tester.tap(find.byKey(const Key('matter-confirm')));
      await tester.pumpAndSettle();

      expect(repo.calls, ['drop p1']);
      expect(find.text('Sprawa p1'), findsNothing);
    });

    testWidgets('a refused accept shows the server message', (tester) async {
      final repo = FakeMattersRepository(
        matters: [_m('p1', MatterStatus.proposed)],
      )..error = MatterRefusedException('not_proposed', 'już przyjęta');
      await _pump(tester, repo);

      await tester.tap(find.byKey(const Key('matter-accept-p1')));
      await tester.pumpAndSettle();

      expect(find.text('Nie udało się przyjąć: już przyjęta'), findsOneWidget);
    });

    testWidgets('a tapped row opens the matter; the list reads on return',
        (tester) async {
      final repo =
          FakeMattersRepository(matters: [_m('a', MatterStatus.active)]);
      await _pump(tester, repo);
      final before = repo.fetches;

      await tester.tap(find.text('Sprawa a'));
      await tester.pumpAndSettle();
      expect(find.text('Detail a'), findsOneWidget);

      await tester.tap(find.text('Detail a'));
      await tester.pumpAndSettle();
      expect(repo.fetches, greaterThan(before));
    });

    testWidgets('"+" opens the new-matter form', (tester) async {
      await _pump(tester, FakeMattersRepository());

      await tester.tap(find.byKey(const Key('matters-add')));
      await tester.pumpAndSettle();

      expect(find.text('Close form'), findsOneWidget);
    });

    testWidgets('an empty list says how to start', (tester) async {
      await _pump(tester, FakeMattersRepository());
      expect(find.textContaining('Nie ma jeszcze spraw'), findsOneWidget);
    });

    testWidgets('a failed read offers a retry', (tester) async {
      final repo = FakeMattersRepository()
        ..fetchError = MattersGeneralException('offline');
      await _pump(tester, repo);
      expect(find.text('offline'), findsOneWidget);

      repo.fetchError = null;
      repo.matters = [_m('a', MatterStatus.active)];
      await tester.tap(find.byKey(const Key('matters-retry-button')));
      await tester.pumpAndSettle();

      expect(find.text('Sprawa a'), findsOneWidget);
    });

    test('standing-still label counts days in Polish', () {
      expect(standingStillLabel(null), 'stoi');
      expect(standingStillLabel(1), 'stoi od 1 dnia');
      expect(standingStillLabel(5), 'stoi od 5 dni');
    });
  });
}
