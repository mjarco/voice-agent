import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:voice_agent/core/models/routine.dart';
import 'package:voice_agent/features/routines/domain/routines_repository.dart';
import 'package:voice_agent/features/routines/presentation/routine_form_screen.dart';
import 'package:voice_agent/features/routines/presentation/routines_providers.dart';

import '../fake_routines_repository.dart';

/// Opens the form from a home page, which shows what the form popped with.
Future<void> _pumpForm(
  WidgetTester tester,
  FakeRoutinesRepository repo, {
  String? editId,
}) async {
  // A tall phone, so the whole form is built without scrolling.
  tester.view.physicalSize = const Size(1080, 3000);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const _Home(),
      ),
      GoRoute(
        path: '/form',
        builder: (context, state) => RoutineFormScreen(editId: editId),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        routinesRepositoryProvider.overrideWithValue(repo),
        routinesClockProvider.overrideWithValue(() => DateTime(2026, 10, 27, 9)),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

class _Home extends StatefulWidget {
  const _Home();

  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> {
  String popped = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          TextButton(
            onPressed: () async {
              final r = await context.push<Routine>('/form');
              setState(() => popped = 'popped ${r?.id}');
            },
            child: const Text('Open'),
          ),
          Text(popped),
        ],
      ),
    );
  }
}

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('routine-form-save')));
  await tester.pumpAndSettle();
}

Future<void> _chooseKind(WidgetTester tester, String label) async {
  await tester.tap(find.byKey(const Key('routine-form-kind')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> _chooseType(WidgetTester tester, String label) async {
  await tester.tap(find.descendant(
      of: find.byKey(const Key('routine-form-type')),
      matching: find.text(label)));
  await tester.pumpAndSettle();
}

void main() {
  late FakeRoutinesRepository repo;

  setUp(() {
    repo = FakeRoutinesRepository();
  });

  group('new routine', () {
    testWidgets('creates chosen weekdays and pops with the routine',
        (tester) async {
      await _pumpForm(tester, repo);
      expect(find.text('New routine'), findsOneWidget);
      expect(find.byKey(const Key('routine-form-starts-on')), findsNothing);

      await tester.enterText(
          find.byKey(const Key('routine-form-name')), ' Trening ');
      await _chooseKind(tester, 'Chosen weekdays');
      await tester.tap(find.byKey(const Key('routine-form-day-WE')));
      await tester.tap(find.byKey(const Key('routine-form-day-MO')));
      await tester.enterText(
          find.byKey(const Key('routine-form-step-0')), 'rozgrzewka');
      await tester.tap(find.byKey(const Key('routine-form-add-step')));
      await tester.pump();
      await tester.enterText(
          find.byKey(const Key('routine-form-step-1')), 'bieg');
      await _save(tester);

      expect(repo.calls, ['create']);
      final input = repo.lastInput!;
      expect(input.name, 'Trening');
      expect((input.term as RecurringTerm).rrule, 'FREQ=WEEKLY;BYDAY=MO,WE');
      expect(input.steps, ['rozgrzewka', 'bieg']);
      expect(input.missed, RoutineMissed.lapses);
      expect(input.startTime, isNull);
      expect(input.lastDay, isNull);
      expect(find.text('popped rtn-new'), findsOneWidget);
    });

    testWidgets('a task once: a day and a window, no rule fields',
        (tester) async {
      await _pumpForm(tester, repo);

      await tester.enterText(
          find.byKey(const Key('routine-form-name')), 'Hydraulik');
      await _chooseType(tester, 'Once');
      expect(find.byKey(const Key('routine-form-kind')), findsNothing);
      expect(find.byKey(const Key('routine-form-last-day')), findsNothing);
      expect(find.byKey(const Key('routine-form-missed')), findsNothing);

      await _save(tester);
      expect(find.text('Choose the day.'), findsOneWidget);
      expect(repo.calls, isEmpty);

      await tester.tap(find.byKey(const Key('routine-form-due-on')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('routine-form-due-window')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Within a week from it').last);
      await tester.pumpAndSettle();
      await _save(tester);

      expect(repo.calls, ['create']);
      final term = repo.lastInput!.term as OneOffTerm;
      expect(term.dueOn, '2026-10-27');
      expect(term.window, TimeWindow.week);
      expect(repo.lastInput!.toCreateMap().containsKey('missed'), isFalse);
    });

    testWidgets('a some-day task has no day at all', (tester) async {
      await _pumpForm(tester, repo);

      await tester.enterText(
          find.byKey(const Key('routine-form-name')), 'Płot');
      await _chooseType(tester, 'Some day');
      expect(find.byKey(const Key('routine-form-someday-note')),
          findsOneWidget);
      await _save(tester);

      expect(repo.lastInput!.term, isA<SomedayTerm>());
      expect(repo.lastInput!.lastDay, isNull);
    });

    testWidgets('names what to fix before saving', (tester) async {
      await _pumpForm(tester, repo);

      await _save(tester);
      expect(find.text('Give the routine a name.'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('routine-form-name')), 'X');
      await _chooseKind(tester, 'Chosen weekdays');
      await _save(tester);
      expect(find.text('Choose at least one day of the week.'), findsOneWidget);

      await _chooseKind(tester, 'Day of the month');
      await tester.enterText(
          find.byKey(const Key('routine-form-monthday')), '32');
      await _save(tester);
      expect(find.text('Choose a day of the month from 1 to 31.'),
          findsOneWidget);
      expect(
          tester
              .widget<TextField>(
                  find.byKey(const Key('routine-form-monthday')))
              .decoration!
              .error,
          isNotNull);
      expect(repo.calls, isEmpty);
    });

    testWidgets('a monthly routine waits unless the owner chooses',
        (tester) async {
      await _pumpForm(tester, repo);

      await tester.enterText(
          find.byKey(const Key('routine-form-name')), 'Czynsz');
      await _chooseKind(tester, 'Day of the month');
      await tester.enterText(
          find.byKey(const Key('routine-form-monthday')), '10');
      await _save(tester);

      expect((repo.lastInput!.term as RecurringTerm).rrule,
          'FREQ=MONTHLY;BYMONTHDAY=10');
      expect(repo.lastInput!.missed, RoutineMissed.waits);
    });

    testWidgets('a save error stays in the form with what was typed',
        (tester) async {
      repo.saveAnswers.add(RoutinesGeneralException('name too long'));
      await _pumpForm(tester, repo);

      await tester.enterText(
          find.byKey(const Key('routine-form-name')), 'Trening');
      await _save(tester);

      expect(find.text('name too long'), findsOneWidget);
      expect(find.text('Trening'), findsOneWidget);
      expect(find.text('New routine'), findsOneWidget);
    });

    testWidgets('a name already on the list marks Name until it changes',
        (tester) async {
      repo.saveAnswers.add(sampleRoutine(name: 'Trening', existing: true));
      await _pumpForm(tester, repo);

      bool nameMarked() => tester
          .widget<TextField>(find.byKey(const Key('routine-form-name')))
          .decoration!
          .error != null;

      await tester.enterText(
          find.byKey(const Key('routine-form-name')), 'Trening');
      expect(nameMarked(), isFalse);
      await _save(tester);

      expect(find.textContaining('is already on the list'), findsOneWidget);
      expect(find.text('popped rtn-new'), findsNothing);
      expect(nameMarked(), isTrue);

      await tester.enterText(
          find.byKey(const Key('routine-form-name')), 'Trening 2');
      await tester.pump();
      expect(nameMarked(), isFalse);
    });
  });

  group('edit', () {
    testWidgets('prefills the routine and sends only what changed',
        (tester) async {
      repo.detail = sampleRoutine(
        id: 'rtn-1',
        name: 'Trening',
        rrule: 'FREQ=WEEKLY;INTERVAL=2;BYDAY=SA;UNTIL=20261231T235959Z',
        startTime: '18:00',
        lastDay: '2026-12-31',
        missed: RoutineMissed.waits,
        steps: const [
          RoutineStep(text: 'bieg', sortOrder: 2),
          RoutineStep(text: 'rozgrzewka', sortOrder: 1),
        ],
      );
      repo.saveAnswers.add(sampleRoutine(id: 'rtn-1'));
      await _pumpForm(tester, repo, editId: 'rtn-1');

      expect(find.text('Edit routine'), findsOneWidget);
      expect(find.byKey(const Key('routine-form-starts-on')), findsNothing);
      expect(find.text('2026-12-31'), findsOneWidget);
      expect(find.text('18:00'), findsOneWidget);
      expect(find.text('Every N weeks'), findsOneWidget);
      expect(find.text('rozgrzewka'), findsOneWidget);

      await _save(tester);
      expect(find.text('Nothing changed.'), findsOneWidget);
      expect(repo.calls, ['detail rtn-1']);

      await tester.enterText(
          find.byKey(const Key('routine-form-name')), 'Trening 2');
      await _save(tester);

      expect(repo.calls, ['detail rtn-1', 'edit rtn-1']);
      expect(repo.lastPatch!.toMap(), {'name': 'Trening 2'});
      expect(find.text('popped rtn-1'), findsOneWidget);
    });

    testWidgets('a past last day is not offered again', (tester) async {
      repo.detail = sampleRoutine(
          id: 'rtn-1', name: 'Pranie', lastDay: '2026-10-20', ended: true);
      await _pumpForm(tester, repo, editId: 'rtn-1');

      expect(find.text('2026-10-20'), findsNothing);
      await tester.enterText(
          find.byKey(const Key('routine-form-name')), 'Pranie 2');
      await _save(tester);

      expect(repo.lastPatch!.toMap(), {'name': 'Pranie 2'});
    });

    testWidgets('a last day with no day of the schedule left is marked',
        (tester) async {
      // Ends today, a Tuesday, on Mondays and Fridays.
      repo.detail = sampleRoutine(
          id: 'rtn-1',
          name: 'Trening',
          rrule: 'FREQ=WEEKLY;UNTIL=20261027T235959Z;BYDAY=MO,FR',
          lastDay: '2026-10-27',
          ended: true);
      await _pumpForm(tester, repo, editId: 'rtn-1');

      Color? labelColor() => tester
          .widget<Text>(find.descendant(
              of: find.byKey(const Key('routine-form-last-day')),
              matching: find.text('Last day')))
          .style
          ?.color;
      final errorColor = Theme.of(tester.element(find.text('Last day')))
          .colorScheme
          .error;
      expect(labelColor(), isNot(errorColor));

      await _save(tester);

      expect(repo.calls, ['detail rtn-1']);
      expect(
          find.text('No day of this schedule falls between 2026-10-27 '
              'and the last day. Move the last day or clear it.'),
          findsOneWidget);
      expect(labelColor(), errorColor);

      await tester.tap(find.descendant(
          of: find.byKey(const Key('routine-form-last-day')),
          matching: find.byTooltip('Clear')));
      await tester.pump();
      expect(labelColor(), isNot(errorColor));

      await _save(tester);
      expect(repo.calls, ['detail rtn-1', 'edit rtn-1']);
      expect(repo.lastPatch!.toMap(), {'last_day': null});
    });

    testWidgets('an unknown schedule asks for a new one', (tester) async {
      repo.detail = sampleRoutine(id: 'rtn-1', name: 'X', rrule: 'FREQ=MONTHLY');
      await _pumpForm(tester, repo, editId: 'rtn-1');

      expect(find.byKey(const Key('routine-form-unknown-rrule')),
          findsOneWidget);
      await _save(tester);
      expect(find.text('Choose a schedule.'), findsOneWidget);
      expect(repo.calls, ['detail rtn-1']);
    });

    testWidgets('a one-off becomes some day', (tester) async {
      repo.detail = sampleRoutine(
          id: 'rtn-1',
          name: 'Hydraulik',
          dueOn: '2026-10-30',
          dueWindow: TimeWindow.week);
      await _pumpForm(tester, repo, editId: 'rtn-1');

      expect(find.text('2026-10-30'), findsOneWidget);
      await _chooseType(tester, 'Some day');
      await _save(tester);

      expect(repo.lastPatch!.toMap(), {'term': <String, dynamic>{}});
    });

    testWidgets('an owed day is ticked off and the edit saved again',
        (tester) async {
      repo.detail = sampleRoutine(
          id: 'rtn-1', name: 'Czynsz', rrule: 'FREQ=MONTHLY;BYMONTHDAY=10');
      repo.saveAnswers
        ..add(RoutineOverdueException('owed',
            routineId: 'rtn-1', scheduledFor: '2026-10-10'))
        ..add(sampleRoutine(id: 'rtn-1'));
      await _pumpForm(tester, repo, editId: 'rtn-1');

      await _chooseKind(tester, 'Every day');
      await _save(tester);
      expect(find.text('An occurrence is still open'), findsOneWidget);
      expect(find.textContaining('2026-10-10'), findsOneWidget);

      await tester.tap(find.byKey(const Key('routine-form-overdue-done')));
      await tester.pumpAndSettle();

      expect(repo.calls, [
        'detail rtn-1',
        'edit rtn-1',
        'resolve rtn-1 2026-10-10 done',
        'edit rtn-1',
      ]);
      expect(repo.lastPatch!.toMap(), {
        'term': {'rrule': 'FREQ=DAILY'},
      });
      expect(find.text('popped rtn-1'), findsOneWidget);
    });

    testWidgets('cancelling the owed day keeps the form', (tester) async {
      repo.detail = sampleRoutine(id: 'rtn-1', name: 'Czynsz');
      repo.saveAnswers.add(RoutineOverdueException('owed',
          routineId: 'rtn-1', scheduledFor: '2026-10-10'));
      await _pumpForm(tester, repo, editId: 'rtn-1');

      await _chooseKind(tester, 'Day of the month');
      await tester.enterText(
          find.byKey(const Key('routine-form-monthday')), '10');
      await _save(tester);
      await tester.tap(find.byKey(const Key('routine-form-overdue-cancel')));
      await tester.pumpAndSettle();

      expect(find.text('Edit routine'), findsOneWidget);
      expect(repo.lastResolve, isNull);
    });
  });
}
