import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:voice_agent/core/widgets/app_menu_button.dart';

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
              actions: const [AppMenuButton()],
            ),
          ),
        ),
        for (final (route, label, _) in AppMenuButton.entries)
          GoRoute(
            path: route,
            builder: (_, _) => Scaffold(body: Text('screen $label')),
          ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  }

  testWidgets('the menu lists Miejsca, Pins and Settings in that order', (
    tester,
  ) async {
    await pump(tester);

    await tester.tap(find.byKey(const Key('app-menu')));
    await tester.pumpAndSettle();

    final ys = [
      for (final key in ['places', 'pins', 'settings'])
        tester.getTopLeft(find.byKey(Key('app-menu-$key'))).dy,
    ];
    expect(ys, orderedEquals([...ys]..sort()));
    expect(find.text('Miejsca'), findsOneWidget);
  });

  for (final (route, label, _) in AppMenuButton.entries) {
    testWidgets('$label opens $route on top of the tab', (tester) async {
      await pump(tester);

      await tester.tap(find.byKey(const Key('app-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('app-menu-${route.substring(1)}')));
      await tester.pumpAndSettle();

      expect(find.text('screen $label'), findsOneWidget);
      // Pushed: back returns to the tab.
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.pop();
      await tester.pumpAndSettle();
      expect(find.text('Tab'), findsOneWidget);
    });
  }
}
