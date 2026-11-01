import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/features/shopping/domain/shopping_models.dart';
import 'package:voice_agent/features/shopping/domain/shopping_repository.dart';
import 'package:voice_agent/features/shopping/presentation/shopping_notifier.dart';
import 'package:voice_agent/features/shopping/presentation/shopping_providers.dart';
import 'package:voice_agent/features/shopping/presentation/shopping_screen.dart';

import '../fake_shopping_repository.dart';

Future<void> _pump(WidgetTester tester, FakeShoppingRepository repo) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        shoppingRepositoryProvider.overrideWithValue(repo),
        shoppingNotifierProvider.overrideWith(
          (ref) => ShoppingNotifier(repo, rereadDelay: Duration.zero),
        ),
      ],
      child: const MaterialApp(home: ShoppingScreen()),
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

    expect(repo.lastSetTypesId, 'i1');
    expect(repo.lastSetTypes, ['grocery']);
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
}
