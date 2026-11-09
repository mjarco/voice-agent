import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:voice_agent/core/models/matter.dart';
import 'package:voice_agent/features/matters/domain/matters_repository.dart';
import 'package:voice_agent/features/matters/presentation/matter_detail_screen.dart';
import 'package:voice_agent/features/matters/presentation/matters_providers.dart';

import '../fake_matters_repository.dart';

MatterDetail _detail({MatterStatus status = MatterStatus.active}) =>
    MatterDetail(
      matter: MatterSummary(
        id: 'm1',
        title: 'Remont',
        status: status,
        nextStep: 'zadzwonić do hydraulika',
        keywords: 'łazienka',
      ),
      timeline: const [
        MatterEntry(
          id: 'e2',
          kind: MatterEntryKind.note,
          text: 'hydraulik oddzwoni',
          day: '2026-11-08',
        ),
        MatterEntry(
          kind: MatterEntryKind.tick,
          text: 'Podlać kwiaty',
          day: '2026-11-07',
        ),
        MatterEntry(
          id: 'e1',
          kind: MatterEntryKind.opened,
          text: 'Remont',
          day: '2026-11-01',
        ),
      ],
      links: const [
        MatterLink(
          id: 'l1',
          kind: MatterLinkKind.conversation,
          targetId: 'c1',
          label: 'O płytkach',
          day: '2026-11-02',
          turns: 4,
        ),
        MatterLink(
          id: 'l2',
          kind: MatterLinkKind.routine,
          targetId: 'r1',
          label: 'Podlać kwiaty',
        ),
      ],
    );

Future<FakeMattersRepository> _pump(
  WidgetTester tester, {
  MatterDetail? detail,
}) async {
  final repo = FakeMattersRepository(details: {'m1': detail ?? _detail()});
  final router = GoRouter(
    initialLocation: '/start',
    routes: [
      GoRoute(
        path: '/start',
        builder: (context, state) => Scaffold(
          body: TextButton(
            onPressed: () => context.push('/matters/m1'),
            child: const Text('Start'),
          ),
        ),
      ),
      GoRoute(
        path: '/matters/:id',
        builder: (context, state) =>
            MatterDetailScreen(matterId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/conversation/:id',
        builder: (context, state) =>
            Scaffold(body: Text('Thread ${state.pathParameters['id']}')),
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
  await tester.tap(find.text('Start'));
  await tester.pumpAndSettle();
  return repo;
}

Future<void> _scrollTo(WidgetTester tester, Finder finder) =>
    tester.scrollUntilVisible(finder, 100,
        scrollable: find.byType(Scrollable).first);

void main() {
  group('MatterDetailScreen', () {
    testWidgets('shows the state, the timeline and the links',
        (tester) async {
      await _pump(tester);

      expect(find.widgetWithText(AppBar, 'Remont'), findsOneWidget);
      expect(find.text('aktywna'), findsOneWidget);
      expect(find.text('zadzwonić do hydraulika'), findsOneWidget);
      expect(find.text('łazienka'), findsOneWidget);
      expect(find.text('hydraulik oddzwoni'), findsOneWidget);
      expect(find.text('2026-11-08'), findsOneWidget);
      await _scrollTo(tester, find.byKey(const Key('matter-link-l2')));
      expect(find.text('O płytkach'), findsOneWidget);
      expect(find.text('2026-11-02 · 4 wypowiedzi'), findsOneWidget);
    });

    testWidgets('a tick has no remove button, an entry has', (tester) async {
      await _pump(tester);

      expect(find.byKey(const Key('matter-entry-delete-e2')), findsOneWidget);
      expect(find.byKey(const Key('matter-entry-tick-1')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('matter-entry-tick-1')),
          matching: find.byType(IconButton),
        ),
        findsNothing,
      );
    });

    testWidgets('the status changes from its menu', (tester) async {
      final repo = await _pump(tester);

      await tester.tap(find.byKey(const Key('matter-status-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('matter-status-waiting')));
      await tester.pumpAndSettle();

      expect(repo.calls.single, contains('status=waiting'));
      expect(find.text('czeka'), findsOneWidget);
    });

    testWidgets('the next step is edited; an empty one clears it',
        (tester) async {
      final repo = await _pump(tester);

      await tester.tap(find.byKey(const Key('matter-edit-next-step')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('matter-text-field')), '');
      await tester.tap(find.byKey(const Key('matter-text-save')));
      await tester.pumpAndSettle();

      expect(repo.calls.single, contains('next= '));
      expect(find.text('zadzwonić do hydraulika'), findsNothing);
    });

    testWidgets('what it waits for is edited', (tester) async {
      final repo = await _pump(tester);

      await tester.tap(find.byKey(const Key('matter-edit-waiting-for')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const Key('matter-text-field')), 'wycena');
      await tester.tap(find.byKey(const Key('matter-text-save')));
      await tester.pumpAndSettle();

      expect(repo.calls.single, contains('waiting=wycena'));
      expect(find.text('wycena'), findsOneWidget);
    });

    testWidgets('a refused edit shows the server message', (tester) async {
      final repo = await _pump(tester);
      repo.error = MatterRefusedException('invalid_request', 'za długie');

      await tester.tap(find.byKey(const Key('matter-edit-waiting-for')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('matter-text-field')), 'x');
      await tester.tap(find.byKey(const Key('matter-text-save')));
      await tester.pumpAndSettle();

      expect(find.text('Nie udało się zapisać: za długie'), findsOneWidget);
    });

    testWidgets('"Dodaj wpis" adds a note to the timeline', (tester) async {
      final repo = await _pump(tester);

      await tester.tap(find.byKey(const Key('matter-add-entry')));
      await tester.pumpAndSettle();
      // The empty field says what it asks for.
      expect(find.text('Co się wydarzyło, jednym zdaniem'), findsOneWidget);
      await tester.enterText(
          find.byKey(const Key('matter-text-field')), 'kupiłem płytki');
      await tester.tap(find.byKey(const Key('matter-text-save')));
      await tester.pumpAndSettle();

      expect(repo.calls.single, 'entry m1 kupiłem płytki');
      expect(find.text('kupiłem płytki'), findsOneWidget);
    });

    testWidgets('a removed entry comes back on undo, nothing is sent',
        (tester) async {
      final repo = await _pump(tester);

      await tester.tap(find.byKey(const Key('matter-entry-delete-e2')));
      await tester.pumpAndSettle();
      expect(find.text('hydraulik oddzwoni'), findsNothing);

      await tester.tap(find.byKey(const Key('matter-entry-undo')));
      await tester.pumpAndSettle();

      expect(find.text('hydraulik oddzwoni'), findsOneWidget);
      expect(repo.calls, isEmpty);
    });

    testWidgets('a removed entry is deleted when the undo runs out',
        (tester) async {
      final repo = await _pump(tester);

      await tester.tap(find.byKey(const Key('matter-entry-delete-e2')));
      // The snackbar shows, its time runs out, it hides.
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      expect(repo.calls, ['delete-entry m1 e2']);
      expect(find.text('hydraulik oddzwoni'), findsNothing);
    });

    testWidgets('a conversation link opens that conversation',
        (tester) async {
      await _pump(tester);

      await _scrollTo(tester, find.text('O płytkach'));
      await tester.tap(find.text('O płytkach'));
      await tester.pumpAndSettle();

      expect(find.text('Thread c1'), findsOneWidget);
    });

    testWidgets('a link is removed after a confirm', (tester) async {
      final repo = await _pump(tester);

      await _scrollTo(tester, find.byKey(const Key('matter-link-remove-l2')));
      await tester.tap(find.byKey(const Key('matter-link-remove-l2')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('matter-unlink-dialog')), findsOneWidget);
      await tester.tap(find.byKey(const Key('matter-confirm')));
      await tester.pumpAndSettle();

      expect(repo.calls, ['unlink m1 l2']);
      expect(find.byKey(const Key('matter-link-l2')), findsNothing);
    });

    testWidgets('delete asks first, then leaves the screen', (tester) async {
      final repo = await _pump(tester);

      await tester.tap(find.byKey(const Key('matter-delete')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('matter-delete-dialog')), findsOneWidget);
      await tester.tap(find.byKey(const Key('matter-confirm')));
      await tester.pumpAndSettle();

      expect(repo.calls, ['delete m1']);
      expect(find.text('Start'), findsOneWidget);
    });

    testWidgets('a proposed matter shows its timeline, links and answers',
        (tester) async {
      final repo =
          await _pump(tester, detail: _detail(status: MatterStatus.proposed));

      expect(find.byKey(const Key('matter-accept-m1')), findsOneWidget);
      expect(find.byKey(const Key('matter-status-menu')), findsNothing);
      expect(find.byKey(const Key('matter-delete')), findsNothing);
      expect(find.text('hydraulik oddzwoni'), findsOneWidget);
      await _scrollTo(tester, find.text('O płytkach'));
      expect(find.text('O płytkach'), findsOneWidget);
      await tester.scrollUntilVisible(
          find.byKey(const Key('matter-accept-m1')), -100,
          scrollable: find.byType(Scrollable).first);

      await tester.tap(find.byKey(const Key('matter-accept-m1')));
      await tester.pumpAndSettle();

      expect(repo.calls, ['accept m1 active']);
      expect(find.byKey(const Key('matter-accept-m1')), findsNothing);
      expect(find.text('aktywna'), findsOneWidget);
    });

    testWidgets('dropping a proposed matter leaves the screen',
        (tester) async {
      final repo =
          await _pump(tester, detail: _detail(status: MatterStatus.proposed));

      await tester.tap(find.byKey(const Key('matter-drop-m1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('matter-confirm')));
      await tester.pumpAndSettle();

      expect(repo.calls, ['drop m1']);
      expect(find.text('Start'), findsOneWidget);
    });

    testWidgets('a missing matter shows the error', (tester) async {
      final repo = FakeMattersRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [mattersRepositoryProvider.overrideWithValue(repo)],
          child: const MaterialApp(home: MatterDetailScreen(matterId: 'x')),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Nie ma takiej sprawy'), findsOneWidget);
      expect(
        find.byKey(const Key('matter-detail-retry-button')),
        findsOneWidget,
      );
    });
  });
}
