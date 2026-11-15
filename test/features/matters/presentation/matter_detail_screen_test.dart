import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:voice_agent/core/models/matter.dart';
import 'package:voice_agent/core/models/routine.dart';
import 'package:voice_agent/core/providers/agent_turns_provider.dart';
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
  List<Routine> tasks = const [],
}) async {
  final repo = FakeMattersRepository(details: {'m1': detail ?? _detail()})
    ..tasks = {'m1': tasks};
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
        builder: (context, state) => MatterDetailScreen(
          matterId: state.pathParameters['id']!,
          field: const Text('the field'),
        ),
      ),
      GoRoute(
        path: '/routine/:id',
        builder: (context, state) =>
            Scaffold(body: Text('Routine ${state.pathParameters['id']}')),
      ),
      GoRoute(
        path: '/conversation/:id',
        builder: (context, state) =>
            Scaffold(appBar: AppBar(), body: Text('Thread ${state.pathParameters['id']}')),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        mattersRepositoryProvider.overrideWithValue(repo),
        mattersClockProvider.overrideWithValue(() => DateTime(2026, 11, 9, 12)),
      ],
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
    testWidgets('a matter opened again is read again, once each time',
        (tester) async {
      final repo = await _pump(tester);
      expect(repo.fetches, 1);

      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();

      expect(repo.fetches, 2);
    });

    testWidgets('shows the state, the timeline and the links',
        (tester) async {
      await _pump(tester);

      expect(find.widgetWithText(AppBar, 'Remont'), findsOneWidget);
      expect(find.text('Aktywna'), findsOneWidget);
      expect(find.text('zadzwonić do hydraulika'), findsOneWidget);
      expect(find.text('hydraulik oddzwoni'), findsOneWidget);
      expect(find.text('wczoraj'), findsOneWidget);
      // The history tells the conversation as a line of its own.
      await _scrollTo(tester, find.text('Rozmowa: O płytkach (4)'));
      expect(find.text('Rozmowa: O płytkach (4)'), findsOneWidget);
      await _scrollTo(tester, find.text('łazienka'));
      expect(find.text('łazienka'), findsOneWidget);
      expect(find.text('the field'), findsOneWidget);
    });

    testWidgets('a tick has no remove button, an entry has', (tester) async {
      await _pump(tester);

      expect(find.byKey(const Key('matter-entry-delete-e2')), findsOneWidget);
      final tick = find.ancestor(of: find.text('Podlać kwiaty'), matching: find.byType(ListTile));
      expect(tick, findsOneWidget);
      expect(find.descendant(of: tick, matching: find.byType(IconButton)), findsNothing);
    });

    testWidgets('the status changes from its menu', (tester) async {
      final repo = await _pump(tester);

      await tester.tap(find.byKey(const Key('matter-status-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('matter-status-waiting')));
      await tester.pumpAndSettle();

      expect(repo.calls.single, contains('status=waiting'));
      expect(find.text('Czeka'), findsOneWidget);
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

      await _scrollTo(tester, find.text('Rozmowa: O płytkach (4)'));
      await tester.tap(find.text('Rozmowa: O płytkach (4)'));
      await tester.pumpAndSettle();
      expect(find.text('Thread c1'), findsOneWidget);

      // Back returns to the matter (04 §5).
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Remont'), findsOneWidget);
    });

    testWidgets('a conversation is unlinked after a long press and a confirm',
        (tester) async {
      final repo = await _pump(tester);

      await _scrollTo(tester, find.text('Rozmowa: O płytkach (4)'));
      await tester.longPress(find.text('Rozmowa: O płytkach (4)'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('matter-unlink-dialog')), findsOneWidget);
      await tester.tap(find.byKey(const Key('matter-confirm')));
      await tester.pumpAndSettle();

      expect(repo.calls, ['unlink m1 l1']);
      expect(find.text('Rozmowa: O płytkach (4)'), findsNothing);
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
      // Not a place to talk from, and no agenda, until accepted.
      expect(find.text('the field'), findsNothing);
      expect(find.byKey(const Key('matter-add-task')), findsNothing);
      await _scrollTo(tester, find.text('Rozmowa: O płytkach (4)'));
      expect(find.text('Rozmowa: O płytkach (4)'), findsOneWidget);
      await tester.scrollUntilVisible(
          find.byKey(const Key('matter-accept-m1')), -100,
          scrollable: find.byType(Scrollable).first);

      await tester.tap(find.byKey(const Key('matter-accept-m1')));
      await tester.pumpAndSettle();

      expect(repo.calls, ['accept m1 active']);
      expect(find.byKey(const Key('matter-accept-m1')), findsNothing);
      expect(find.text('Aktywna'), findsOneWidget);
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

    group('the agenda (04 §4)', () {
      Routine task(String id, String name, {String? due, RoutineKind kind = RoutineKind.oneOff}) => Routine(
            id: id, name: name, kind: kind, dueOn: due, nextDue: due, status: RoutineStatus.active,
            createdAt: DateTime(2026), updatedAt: DateTime(2026),
          );

      testWidgets('shows its tasks, overdue first, someday last; a tap opens one',
          (tester) async {
        await _pump(tester, tasks: [
          task('r2', 'Wybrać lustro', kind: RoutineKind.someday),
          task('r3', 'Odebrać płytki', due: '2026-11-17'),
          task('r1', 'Zadzwonić do hydraulika', due: '2026-11-03'),
        ]);

        final names = tester.widgetList<Text>(find.descendant(
          of: find.byWidgetPredicate((w) => w is Dismissible),
          matching: find.byType(Text),
        )).map((t) => t.data).toList();
        expect(names, ['! od 03.11', 'Zadzwonić do hydraulika', 'wt 17.11', 'Odebrać płytki', 'kiedyś', 'Wybrać lustro']);

        await tester.tap(find.text('Odebrać płytki'));
        await tester.pumpAndSettle();
        expect(find.text('Routine r3'), findsOneWidget);
      });

      testWidgets('a task is added with its day', (tester) async {
        final repo = await _pump(tester);

        await tester.tap(find.byKey(const Key('matter-add-task')));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('matter-task-name')), 'Kupić silikon');
        await tester.tap(find.byKey(const Key('matter-task-tomorrow')));
        await tester.tap(find.byKey(const Key('matter-task-save')));
        await tester.pumpAndSettle();

        expect(repo.calls, ['add-task m1 Kupić silikon 2026-11-10']);
        expect(find.text('Kupić silikon'), findsOneWidget);
        expect(find.text('jutro'), findsOneWidget);
      });

      testWidgets('a swipe right ticks it off, Cofnij takes it back', (tester) async {
        final repo = await _pump(tester, tasks: [task('r1', 'Zadzwonić do hydraulika', due: '2026-11-09')]);
        repo.tasks['m1'] = [];

        await tester.drag(find.text('Zadzwonić do hydraulika'), const Offset(500, 0));
        await tester.pumpAndSettle();
        expect(repo.calls, ['resolve r1 -']);
        expect(find.text('Zadzwonić do hydraulika'), findsNothing);

        await tester.tap(find.byKey(const Key('matter-task-undo')));
        await tester.pumpAndSettle();
        expect(repo.calls, ['resolve r1 -', 'unresolve r1 -']);
      });

      // personal-agent never takes an archived routine back (F2 of V3's
      // device check): the archive is asked for only when Cofnij runs out.
      testWidgets('a swipe left removes it, archived only when Cofnij runs out', (tester) async {
        final repo = await _pump(tester, tasks: [task('r1', 'Stare zadanie', kind: RoutineKind.someday)]);

        await tester.drag(find.text('Stare zadanie'), const Offset(-500, 0));
        await tester.pumpAndSettle();
        expect(find.text('Stare zadanie'), findsNothing);
        expect(repo.calls, isEmpty);

        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
        expect(repo.calls, ['archive r1']);
      });

      testWidgets('Cofnij after a removal brings the task back and archives nothing', (tester) async {
        final repo = await _pump(tester, tasks: [task('r1', 'Stare zadanie', kind: RoutineKind.someday)]);

        await tester.drag(find.text('Stare zadanie'), const Offset(-500, 0));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('matter-task-undo')));
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();

        expect(repo.calls, isEmpty);
        expect(find.text('Stare zadanie'), findsOneWidget);
      });

      testWidgets('a task waiting for its archive stays off when the agenda is read again', (tester) async {
        final repo = await _pump(tester, tasks: [
          task('r1', 'Stare zadanie', kind: RoutineKind.someday),
          task('r2', 'Zadzwonić', due: '2026-11-09'),
        ]);

        await tester.drag(find.text('Stare zadanie'), const Offset(-500, 0));
        await tester.pumpAndSettle();
        repo.tasks['m1'] = [task('r1', 'Stare zadanie', kind: RoutineKind.someday)];
        await tester.drag(find.text('Zadzwonić'), const Offset(500, 0));
        await tester.pumpAndSettle();

        // The tick's snackbar replaces the removal's: its undo is over, so
        // the archive follows the tick.
        expect(repo.calls, ['resolve r2 -', 'archive r1']);
        expect(find.text('Stare zadanie'), findsNothing);
      });

      testWidgets('a recurring routine not due yet cannot be ticked, only removed', (tester) async {
        await _pump(tester, tasks: [task('r1', 'Podlać', due: '2026-11-12', kind: RoutineKind.recurring)]);
        final d = tester.widget<Dismissible>(find.byWidgetPredicate((w) => w is Dismissible));
        expect(d.direction, DismissDirection.endToStart);
        expect(find.text('cyklicznie · czw 12.11'), findsOneWidget);
      });
    });

    // F1 of V3's device check: a typed turn on the matter left its screen
    // as it was. Every answered turn counts, also two equal replies.
    testWidgets('each answered turn reads the matter and its agenda again', (tester) async {
      final repo = await _pump(tester);
      final before = repo.fetches;
      final container = ProviderScope.containerOf(tester.element(find.byType(MatterDetailScreen)));

      container.read(agentTurnsProvider.notifier).state++;
      await tester.pumpAndSettle();
      container.read(agentTurnsProvider.notifier).state++;
      await tester.pumpAndSettle();

      expect(repo.fetches, before + 2);
      expect(repo.taskFetches, greaterThanOrEqualTo(3));
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
