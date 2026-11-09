import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:voice_agent/core/models/matter.dart';
import 'package:voice_agent/features/matters/domain/matters_repository.dart';
import 'package:voice_agent/features/matters/presentation/matter_form_screen.dart';
import 'package:voice_agent/features/matters/presentation/matters_providers.dart';

import '../fake_matters_repository.dart';

Future<List<Object?>> _pump(
  WidgetTester tester,
  FakeMattersRepository repo,
) async {
  final results = <Object?>[];
  final router = GoRouter(
    initialLocation: '/start',
    routes: [
      GoRoute(
        path: '/start',
        builder: (context, state) => Scaffold(
          body: TextButton(
            onPressed: () async =>
                results.add(await context.push<Object?>('/matters/new')),
            child: const Text('Start'),
          ),
        ),
      ),
      GoRoute(
        path: '/matters/new',
        builder: (context, state) => const MatterFormScreen(),
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
  return results;
}

void main() {
  group('MatterFormScreen', () {
    testWidgets('a matter needs a title', (tester) async {
      final repo = FakeMattersRepository();
      await _pump(tester, repo);

      await tester.tap(find.byKey(const Key('matter-form-save')));
      await tester.pumpAndSettle();

      expect(find.text('Sprawa potrzebuje tytułu'), findsOneWidget);
      expect(repo.calls, isEmpty);
    });

    testWidgets('saves title, keywords and next step, then closes',
        (tester) async {
      final repo = FakeMattersRepository();
      final results = await _pump(tester, repo);

      await tester.enterText(
          find.byKey(const Key('matter-form-title')), ' Remont ');
      await tester.enterText(
          find.byKey(const Key('matter-form-keywords')), 'łazienka');
      await tester.enterText(
          find.byKey(const Key('matter-form-next-step')), 'wycena');
      await tester.tap(find.byKey(const Key('matter-form-save')));
      await tester.pumpAndSettle();

      expect(repo.calls, ['create Remont|łazienka|wycena']);
      expect(find.text('Start'), findsOneWidget);
      expect(results.single, isA<MatterDetail>());
    });

    testWidgets('a taken title shows the server message and stays',
        (tester) async {
      final repo = FakeMattersRepository()
        ..error = MatterRefusedException(
            'title_taken', 'Sprawa o tym tytule już istnieje');
      await _pump(tester, repo);

      await tester.enterText(
          find.byKey(const Key('matter-form-title')), 'Remont');
      await tester.tap(find.byKey(const Key('matter-form-save')));
      await tester.pumpAndSettle();

      expect(
        find.text(
            'Nie udało się otworzyć sprawy: Sprawa o tym tytule już istnieje'),
        findsOneWidget,
      );
      expect(find.byType(MatterFormScreen), findsOneWidget);
    });
  });
}
