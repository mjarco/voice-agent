import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/app/app.dart';
import 'package:voice_agent/core/providers/api_url_provider.dart';

void main() {
  testWidgets('Banner appears when API URL not configured', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: App()),
    );
    await tester.pumpAndSettle();

    // Default stub returns false — banner should be visible
    expect(
      find.text(
        'Set up your API endpoint in Settings to sync your transcripts.',
      ),
      findsOneWidget,
    );
    expect(find.text('Go to Settings'), findsOneWidget);
  });

  testWidgets('Banner hidden when API URL is configured', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiUrlConfiguredProvider.overrideWithValue(true),
        ],
        child: const App(),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Set up your API endpoint in Settings to sync your transcripts.',
      ),
      findsNothing,
    );
  });

  testWidgets('Tapping Go to Settings navigates to Settings tab',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: App()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Go to Settings'));
    await tester.pumpAndSettle();

    final navBar = tester.widget<NavigationBar>(
      find.byType(NavigationBar),
    );
    expect(navBar.selectedIndex, 2); // Settings tab
  });
}
