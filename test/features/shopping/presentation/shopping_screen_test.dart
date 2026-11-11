import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/providers/shopping_list_changes_provider.dart';
import 'package:voice_agent/features/shopping/domain/shopping_models.dart';
import 'package:voice_agent/features/shopping/domain/shopping_repository.dart';
import 'package:voice_agent/features/shopping/presentation/shopping_notifier.dart';
import 'package:voice_agent/features/shopping/presentation/shopping_providers.dart';
import 'package:voice_agent/features/shopping/presentation/shopping_screen.dart';

import '../../../core/network/fake_shopping_proposals.dart';
import '../fake_shopping_repository.dart';

Future<void> _pump(
  WidgetTester tester,
  FakeShoppingRepository repo, {
  FakeShoppingProposals? proposals,
  List<String> placeTypes = const [],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        shoppingRepositoryProvider.overrideWithValue(repo),
        shoppingNotifierProvider.overrideWith(
          (ref) => ShoppingNotifier(
            repo,
            proposals ?? FakeShoppingProposals(),
            rereadDelay: Duration.zero,
          ),
        ),
      ],
      child: MaterialApp(home: ShoppingScreen(placeTypes: placeTypes)),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const Key('shopping-text')), text);
  await tester.pump();
  await tester.tap(find.byKey(const Key('shopping-save')));
  await tester.pumpAndSettle();
}

String _fieldText(WidgetTester tester) => tester
    .widget<TextField>(find.byKey(const Key('shopping-text')))
    .controller!
    .text;

void main() {
  testWidgets('shows an item with its type labels', (tester) async {
    await _pump(tester, FakeShoppingRepository());

    expect(find.text('kabel HDMI'), findsOneWidget);
    expect(find.text('Elektryczny'), findsOneWidget);
  });

  testWidgets('an item being tagged says so', (tester) async {
    final repo = FakeShoppingRepository()
      ..toBuy = [sampleItem(storeTypes: [], typesSource: null)];
    await _pump(tester, repo);

    expect(find.text('tagging…'), findsOneWidget);
  });

  testWidgets('an item bought untagged shows its date', (tester) async {
    final repo = FakeShoppingRepository()
      ..bought = [
        sampleItem(
          id: 'b1',
          state: 'bought',
          storeTypes: [],
          typesSource: null,
          boughtAt: DateTime(2026, 10, 31),
        ),
      ];
    await _pump(tester, repo);

    await tester.tap(find.text('Bought'));
    await tester.pumpAndSettle();

    expect(find.text('tagging…'), findsNothing);
    expect(find.text('Inne · bought 31.10'), findsOneWidget);
  });

  testWidgets('a failed tag shows under other', (tester) async {
    final repo = FakeShoppingRepository()
      ..toBuy = [sampleItem(storeTypes: [], typesSource: 'failed')];
    await _pump(tester, repo);

    expect(find.text('tagging…'), findsNothing);
    expect(find.text('Inne'), findsOneWidget);
  });

  testWidgets('saving clears the field', (tester) async {
    final repo = FakeShoppingRepository();
    await _pump(tester, repo);

    await _save(tester, ' mleko ');

    expect(repo.lastAddText, 'mleko');
    expect(_fieldText(tester), '');
  });

  testWidgets('a failed save keeps the text and says so', (tester) async {
    final repo = FakeShoppingRepository()
      ..nextWriteError = ShoppingGeneralException('no route');
    await _pump(tester, repo);

    await _save(tester, 'mleko');

    expect(_fieldText(tester), 'mleko');
    expect(find.text('Not saved: no route'), findsOneWidget);
  });

  testWidgets('the same text says it is already there', (tester) async {
    final repo = FakeShoppingRepository()
      ..nextAdd = ShoppingAddResult(item: sampleItem(), created: false);
    await _pump(tester, repo);

    await _save(tester, 'kabel HDMI');

    expect(find.text('Already on the list'), findsOneWidget);
  });

  testWidgets('types can be picked while adding', (tester) async {
    final repo = FakeShoppingRepository();
    await _pump(tester, repo);
    expect(find.byKey(const Key('shopping-new-type-grocery')), findsNothing);

    await tester.enterText(find.byKey(const Key('shopping-text')), 'mleko');
    await tester.pump();
    await tester.tap(find.byKey(const Key('shopping-new-type-grocery')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('shopping-save')));
    await tester.pumpAndSettle();

    expect(repo.lastAddTypes, ['grocery']);
  });

  testWidgets('the filter hides empty types and reads one', (tester) async {
    final repo = FakeShoppingRepository();
    await _pump(tester, repo);

    expect(find.text('All (1)'), findsOneWidget);
    expect(find.byKey(const Key('shopping-filter-grocery')), findsNothing);

    await tester.tap(find.byKey(const Key('shopping-filter-electrical')));
    await tester.pumpAndSettle();

    expect(repo.lastStoreType, 'electrical');
  });

  testWidgets('ticks an item off', (tester) async {
    final repo = FakeShoppingRepository();
    await _pump(tester, repo);

    await tester.tap(find.byKey(const Key('shopping-bought-i1')));
    await tester.pumpAndSettle();

    expect(repo.lastBoughtId, 'i1');
  });

  testWidgets('a tap corrects the types, none cannot be saved', (tester) async {
    final repo = FakeShoppingRepository();
    await _pump(tester, repo);

    await tester.tap(find.text('kabel HDMI'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('shopping-edit-type-electrical')));
    await tester.pump();
    final save = find.byKey(const Key('shopping-edit-save'));
    expect(tester.widget<FilledButton>(save).onPressed, isNull);

    await tester.tap(find.byKey(const Key('shopping-edit-type-grocery')));
    await tester.pump();
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(repo.lastEditId, 'i1');
    expect(repo.lastEditText, isNull, reason: 'the text did not change');
    expect(repo.lastSetTypes, ['grocery']);
  });

  testWidgets('a tap corrects the text; an empty one cannot be saved', (
    tester,
  ) async {
    final repo = FakeShoppingRepository();
    await _pump(tester, repo);

    await tester.tap(find.text('kabel HDMI'));
    await tester.pumpAndSettle();
    final field = find.byKey(const Key('shopping-edit-text'));
    final save = find.byKey(const Key('shopping-edit-save'));
    await tester.enterText(field, '   ');
    await tester.pump();
    expect(tester.widget<FilledButton>(save).onPressed, isNull);

    await tester.enterText(field, ' kabel HDMI 2 m ');
    await tester.pump();
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(repo.lastEditId, 'i1');
    expect(repo.lastEditText, 'kabel HDMI 2 m');
    expect(repo.lastSetTypes, isNull, reason: 'the types did not change');
  });

  testWidgets('an item without types may have its text corrected alone', (
    tester,
  ) async {
    final repo = FakeShoppingRepository()
      ..toBuy = [sampleItem(storeTypes: [], typesSource: null)];
    await _pump(tester, repo);

    await tester.tap(find.text('kabel HDMI'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('shopping-edit-text')),
      'kabel HDMI 2 m',
    );
    await tester.pump();
    final save = find.byKey(const Key('shopping-edit-save'));
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(repo.lastEditText, 'kabel HDMI 2 m');
    expect(repo.lastSetTypes, isNull);
  });

  testWidgets('saving with nothing changed sends nothing', (tester) async {
    final repo = FakeShoppingRepository();
    await _pump(tester, repo);

    await tester.tap(find.text('kabel HDMI'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('shopping-edit-save')));
    await tester.pumpAndSettle();

    expect(repo.editCalls, 0);
  });

  testWidgets('removing asks first', (tester) async {
    final repo = FakeShoppingRepository();
    await _pump(tester, repo);

    await tester.tap(find.text('kabel HDMI'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('shopping-remove')));
    await tester.pumpAndSettle();
    expect(repo.lastRemovedId, isNull);

    await tester.tap(find.byKey(const Key('shopping-remove-confirm')));
    await tester.pumpAndSettle();

    expect(repo.lastRemovedId, 'i1');
  });

  testWidgets('Bought offers the way back', (tester) async {
    final repo = FakeShoppingRepository()
      ..bought = [
        sampleItem(id: 'b1', state: 'bought', boughtAt: DateTime(2026, 10, 31)),
      ];
    await _pump(tester, repo);

    await tester.tap(find.text('Bought'));
    await tester.pumpAndSettle();
    expect(find.text('Elektryczny · bought 31.10'), findsOneWidget);

    await tester.tap(find.byKey(const Key('shopping-restore-b1')));
    await tester.pumpAndSettle();

    expect(repo.lastRestoredId, 'b1');
  });

  testWidgets('a failed read of Bought hides the list, Retry reads it',
      (tester) async {
    final repo = FakeShoppingRepository();
    await _pump(tester, repo);

    repo.nextReadError = ShoppingGeneralException('no route');
    await tester.tap(find.text('Bought'));
    await tester.pumpAndSettle();

    expect(find.text('kabel HDMI'), findsNothing);
    expect(find.text('no route'), findsOneWidget);

    repo.nextReadError = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Nothing bought in the last 7 days.'), findsOneWidget);
  });

  testWidgets('the first read failing offers Retry', (tester) async {
    final repo = FakeShoppingRepository()
      ..nextReadError = ShoppingGeneralException('no route');
    await _pump(tester, repo);
    expect(find.text('no route'), findsOneWidget);

    repo.nextReadError = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('kabel HDMI'), findsOneWidget);
  });

  group('proposals', () {
    double top(WidgetTester tester, String key) =>
        tester.getTopLeft(find.byKey(Key(key))).dy;

    testWidgets('the waiting ones stand above To buy', (tester) async {
      final proposals = FakeShoppingProposals()..rows = [sampleProposal()];
      await _pump(tester, FakeShoppingRepository(), proposals: proposals);

      expect(
        top(tester, 'shopping-proposal-p1'),
        lessThan(top(tester, 'shopping-item-i1')),
      );
    });

    testWidgets('they show on an empty list too', (tester) async {
      final proposals = FakeShoppingProposals()..rows = [sampleProposal()];
      await _pump(
        tester,
        FakeShoppingRepository()..toBuy = [],
        proposals: proposals,
      );

      expect(find.byKey(const Key('shopping-proposal-p1')), findsOneWidget);
      expect(find.text('Nothing to buy.'), findsOneWidget);
    });

    testWidgets('they do not show under Bought', (tester) async {
      final proposals = FakeShoppingProposals()..rows = [sampleProposal()];
      await _pump(tester, FakeShoppingRepository(), proposals: proposals);

      await tester.tap(find.text('Bought'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('shopping-proposal-p1')), findsNothing);
    });

    testWidgets('a failed read leaves the list standing', (tester) async {
      final proposals = FakeShoppingProposals()..failReads = true;
      await _pump(tester, FakeShoppingRepository(), proposals: proposals);

      expect(find.text('kabel HDMI'), findsOneWidget);
    });

    testWidgets('accepting on the card answers it', (tester) async {
      final proposals = FakeShoppingProposals()..rows = [sampleProposal()];
      proposals.onAnswer = () => proposals.rows = [];
      await _pump(tester, FakeShoppingRepository(), proposals: proposals);

      await tester.tap(find.byKey(const Key('shopping-proposal-accept-p1')));
      await tester.pumpAndSettle();

      expect(proposals.accepted, ['p1']);
      expect(find.byKey(const Key('shopping-proposal-p1')), findsNothing);
    });

    testWidgets('a change made elsewhere reads the list again', (tester) async {
      final repo = FakeShoppingRepository();
      final proposals = FakeShoppingProposals();
      await _pump(tester, repo, proposals: proposals);
      expect(find.byKey(const Key('shopping-proposal-p1')), findsNothing);

      proposals.rows = [sampleProposal()];
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ShoppingScreen)),
      );
      container.read(shoppingListChangesProvider.notifier).state++;
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('shopping-proposal-p1')), findsOneWidget);
    });
  });

  group('a place from an arrival alert', () {
    bool selected(WidgetTester tester, String key) =>
        tester.widget<ChoiceChip>(find.byKey(Key(key))).selected;

    testWidgets('selects every one of its store types', (tester) async {
      final repo = FakeShoppingRepository()
        ..toBuy = [
          sampleItem(id: 'a', text: 'kabel HDMI', storeTypes: ['electrical']),
          sampleItem(id: 'b', text: 'mleko', storeTypes: ['grocery']),
          sampleItem(id: 'c', text: 'gwoździe', storeTypes: ['other']),
        ];
      await _pump(tester, repo, placeTypes: ['electrical', 'grocery']);

      expect(selected(tester, 'shopping-filter-electrical'), isTrue);
      expect(selected(tester, 'shopping-filter-grocery'), isTrue);
      expect(selected(tester, 'shopping-filter-all'), isFalse);
      expect(find.text('kabel HDMI'), findsOneWidget);
      expect(find.text('mleko'), findsOneWidget);
      expect(find.text('gwoździe'), findsNothing);
    });

    testWidgets('a second tap to the same place selects it again',
        (tester) async {
      final repo = FakeShoppingRepository();
      Widget screen(Object tap) => ProviderScope(
            overrides: [
              shoppingRepositoryProvider.overrideWithValue(repo),
              shoppingNotifierProvider.overrideWith(
                (ref) => ShoppingNotifier(
                  repo,
                  FakeShoppingProposals(),
                  rereadDelay: Duration.zero,
                ),
              ),
            ],
            child: MaterialApp(
              home: ShoppingScreen(placeTypes: const ['electrical'], tap: tap),
            ),
          );
      await tester.pumpWidget(screen(Object()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('shopping-filter-all')));
      await tester.pumpAndSettle();
      expect(selected(tester, 'shopping-filter-all'), isTrue);

      // The same route from a new tap: a new token, same types.
      await tester.pumpWidget(screen(Object()));
      await tester.pumpAndSettle();

      expect(selected(tester, 'shopping-filter-electrical'), isTrue);
      expect(selected(tester, 'shopping-filter-all'), isFalse);
    });

    testWidgets('a chip tap goes back to choosing one', (tester) async {
      await _pump(
        tester,
        FakeShoppingRepository(),
        placeTypes: ['electrical', 'grocery'],
      );

      await tester.tap(find.byKey(const Key('shopping-filter-electrical')));
      await tester.pumpAndSettle();

      expect(selected(tester, 'shopping-filter-electrical'), isTrue);
      // Out of the place, a type with nothing to buy has no chip again.
      expect(find.byKey(const Key('shopping-filter-grocery')), findsNothing);
    });
  });
}
