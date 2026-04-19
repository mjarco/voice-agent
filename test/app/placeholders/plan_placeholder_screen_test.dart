import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/app/placeholders/plan_placeholder_screen.dart';

void main() {
  group('PlanPlaceholderScreen', () {
    testWidgets('renders title and gear icon', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: PlanPlaceholderScreen()),
      );

      expect(find.text('Plan'), findsWidgets);
      expect(find.byIcon(Icons.settings), findsOneWidget);
      expect(find.byIcon(Icons.checklist), findsOneWidget);
      expect(find.text('Action items and goals'), findsOneWidget);
    });
  });
}
