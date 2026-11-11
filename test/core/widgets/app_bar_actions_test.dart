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
        for (final (route, label, _) in AppBarActions.entries)
          GoRoute(
            path: route,
            builder: (_, _) => Scaffold(body: Text('screen $label')),
          ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  }

  testWidgets('Miejsca, Pins, Settings are icons; Settings at the right edge',
      (tester) async {
    await pump(tester);

    final xs = [
      for (final key in ['app-places', 'app-pins', 'app-settings'])
        tester.getTopLeft(find.byKey(Key(key))).dx,
    ];
    expect(xs, orderedEquals([...xs]..sort()));
    // Nothing to the right of Settings, and no overflow menu.
    final bar = tester.getRect(find.byType(AppBar));
    final settings = tester.getRect(find.byKey(const Key('app-settings')));
    expect(bar.right - settings.right, lessThan(16));
    expect(find.byType(PopupMenuButton<String>), findsNothing);
    expect(find.byIcon(Icons.more_vert), findsNothing);
  });

  for (final (route, label, _) in AppBarActions.entries) {
    testWidgets('the $label icon opens $route on top of the tab', (
      tester,
    ) async {
      await pump(tester);

      await tester.tap(find.byKey(Key('app-${route.substring(1)}')));
      await tester.pumpAndSettle();

      expect(find.text('screen $label'), findsOneWidget);
      // Pushed: back returns to the tab.
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
      expect(find.text('Tab'), findsOneWidget);
    });
  }
}
