import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:voice_agent/core/widgets/app_bar_actions.dart';

void main() {
  Future<void> pump(WidgetTester tester) async {
    final router = GoRouter(
      initialLocation: '/tab',
      routes: [
        GoRoute(
          path: '/tab',
          builder: (_, _) => Scaffold(
            appBar: AppBar(
              title: const Text('Tab'),
              actions: const [AppBarActions()],
            ),
          ),
        ),
        for (final (route, label, _) in [
          ...AppBarActions.shortcuts,
          ...AppBarActions.menu,
        ])
          GoRoute(
            path: route,
            builder: (_, _) => Scaffold(body: Text('screen $label')),
          ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  }

  Future<void> expectPushedOnTab(WidgetTester tester, String label) async {
    expect(find.text('screen $label'), findsOneWidget);
    // Pushed: back returns to the tab.
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    expect(find.text('Tab'), findsOneWidget);
  }

  testWidgets('Pins and Settings are icons in the bar, then the menu', (
    tester,
  ) async {
    await pump(tester);

    final xs = [
      for (final key in ['app-pins', 'app-settings', 'app-menu'])
        tester.getTopLeft(find.byKey(Key(key))).dx,
    ];
    expect(xs, orderedEquals([...xs]..sort()));
    expect(find.byTooltip('Pins'), findsOneWidget);
    expect(find.byTooltip('Settings'), findsOneWidget);
    // Neither is hidden in the menu.
    await tester.tap(find.byKey(const Key('app-menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('app-menu-places')), findsOneWidget);
    expect(find.byKey(const Key('app-menu-pins')), findsNothing);
    expect(find.byKey(const Key('app-menu-settings')), findsNothing);
  });

  for (final (route, label, _) in AppBarActions.shortcuts) {
    testWidgets('the $label icon opens $route on top of the tab', (
      tester,
    ) async {
      await pump(tester);

      await tester.tap(find.byKey(Key('app-${route.substring(1)}')));
      await tester.pumpAndSettle();

      await expectPushedOnTab(tester, label);
    });
  }

  for (final (route, label, _) in AppBarActions.menu) {
    testWidgets('$label in the menu opens $route on top of the tab', (
      tester,
    ) async {
      await pump(tester);

      await tester.tap(find.byKey(const Key('app-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('app-menu-${route.substring(1)}')));
      await tester.pumpAndSettle();

      await expectPushedOnTab(tester, label);
    });
  }
}
