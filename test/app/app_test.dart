import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/app/app.dart';

void main() {
  testWidgets('App renders with shell and 3 tabs', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: App()),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('History'), findsWidgets);
    expect(find.text('Record'), findsWidgets);
    expect(find.text('Settings'), findsWidgets);
  });

  testWidgets('Default tab is Record', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: App()),
    );
    await tester.pumpAndSettle();

    final navBar = tester.widget<NavigationBar>(
      find.byType(NavigationBar),
    );
    expect(navBar.selectedIndex, 1);
  });

  testWidgets('Tapping History tab shows History screen', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: App()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.history));
    await tester.pumpAndSettle();

    final navBar = tester.widget<NavigationBar>(
      find.byType(NavigationBar),
    );
    expect(navBar.selectedIndex, 0);
  });

  testWidgets('Tapping Settings tab shows Settings screen', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: App()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();

    final navBar = tester.widget<NavigationBar>(
      find.byType(NavigationBar),
    );
    expect(navBar.selectedIndex, 2);
  });

  testWidgets('App uses Material 3', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: App()),
    );

    final materialApp = tester.widget<MaterialApp>(
      find.byType(MaterialApp),
    );
    expect(materialApp.theme?.useMaterial3, isTrue);
  });
}
