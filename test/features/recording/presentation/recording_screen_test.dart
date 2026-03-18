import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/app/app.dart';
import 'package:voice_agent/core/providers/api_url_provider.dart';

void main() {
  testWidgets('Record screen shows mic button in idle state', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiUrlConfiguredProvider.overrideWithValue(true)],
        child: const App(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.mic), findsWidgets);
    expect(find.text('Tap to record'), findsOneWidget);
  });

  testWidgets('Record screen shows banner when API not configured',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: App()),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Set up your API endpoint in Settings to sync your transcripts.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('Record screen hides banner when API configured',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiUrlConfiguredProvider.overrideWithValue(true)],
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
}
