import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/features/diet/domain/diet_models.dart';
import 'package:voice_agent/features/diet/domain/diet_repository.dart';
import 'package:voice_agent/features/diet/presentation/diet_days.dart';
import 'package:voice_agent/features/diet/presentation/diet_day_screen.dart';
import 'package:voice_agent/features/diet/presentation/diet_providers.dart';

/// Today with no meal; own meals to pick; what is eaten and removed recorded.
class _Diet implements DietRepository {
  _Diet(this.own);

  final List<DietOwnMeal> own;
  final eaten = <String>[];
  final removed = <String>[];

  @override
  Future<DietDay> day(String day) async => DietDay.fromMap({
        'day': day,
        'target': {'from': '2026-11-01', 'kcal_min': 1800, 'kcal_max': 2000, 'reserve_kcal': 600},
        'meals': const [],
        'eaten': {'kcal': 0},
        'left_kcal': 2000,
        'warning': '',
        'planned': const [],
      });

  @override
  Future<List<DietOwnMeal>> ownMeals() async => own;

  @override
  Future<DietMeal> eatOwnMeal(String ownMealId) async {
    eaten.add(ownMealId);
    final m = own.firstWhere((o) => o.id == ownMealId);
    return DietMeal(id: 'meal-1', day: dayKey(DateTime.now()), time: '12:00', name: m.name, estimate: m.estimate);
  }

  @override
  Future<void> removeMeal(String id) async => removed.add(id);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

const _owsianka = DietOwnMeal(
  id: 'own-1',
  name: 'Owsianka',
  portion: '1 miska',
  ingredients: [],
  estimate: DietEstimate(kcal: 455, low: 430, high: 480),
);

Future<void> _pump(WidgetTester tester, _Diet diet, {String? day}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [dietRepositoryProvider.overrideWithValue(diet)],
    child: MaterialApp(home: DietDayScreen(day: day)),
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('an own meal eaten from the day', () {
    testWidgets('a pick logs it now and Cofnij removes it', (tester) async {
      final diet = _Diet([_owsianka]);
      await _pump(tester, diet);

      await tester.tap(find.byKey(const Key('diet-eat-own')));
      await tester.pumpAndSettle();
      expect(find.text('1 miska'), findsOneWidget);
      expect(find.text('455 (430–480) kcal'), findsOneWidget);

      await tester.tap(find.byKey(const Key('own-meal-pick-own-1')));
      await tester.pumpAndSettle();
      expect(diet.eaten, ['own-1']);
      expect(find.text('Zapisane: Owsianka · 455 (430–480) kcal'), findsOneWidget);

      await tester.tap(find.text('Cofnij'));
      await tester.pumpAndSettle();
      expect(diet.removed, ['meal-1']);
    });

    testWidgets('Cofnij after the day is closed still removes the meal', (tester) async {
      final diet = _Diet([_owsianka]);
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(ProviderScope(
        overrides: [dietRepositoryProvider.overrideWithValue(diet)],
        child: MaterialApp(navigatorKey: nav, home: const Scaffold(body: Text('Dziś'))),
      ));
      unawaited(nav.currentState!.push(MaterialPageRoute<void>(builder: (_) => const DietDayScreen())));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('diet-eat-own')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('own-meal-pick-own-1')));
      await tester.pumpAndSettle();
      nav.currentState!.pop();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cofnij'));
      await tester.pumpAndSettle();
      expect(diet.removed, ['meal-1']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('closing the list logs nothing', (tester) async {
      final diet = _Diet([_owsianka]);
      await _pump(tester, diet);

      await tester.tap(find.byKey(const Key('diet-eat-own')));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(diet.eaten, isEmpty);
    });

    testWidgets('no own meals: the list says how to keep one', (tester) async {
      final diet = _Diet(const []);
      await _pump(tester, diet);

      await tester.tap(find.byKey(const Key('diet-eat-own')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Brak własnych posiłków'), findsOneWidget);
    });

    testWidgets('a past day has no button', (tester) async {
      final diet = _Diet([_owsianka]);
      await _pump(tester, diet, day: dayKey(DateTime.now().subtract(const Duration(days: 1))));

      expect(find.byKey(const Key('diet-eat-own')), findsNothing);
    });
  });
}
