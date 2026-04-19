import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/app/placeholders/routines_placeholder_screen.dart';

void main() {
  group('RoutinesPlaceholderScreen', () {
    testWidgets('renders title and gear icon', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: RoutinesPlaceholderScreen()),
      );

      expect(find.text('Routines'), findsWidgets);
      expect(find.byIcon(Icons.settings), findsOneWidget);
      expect(find.byIcon(Icons.repeat), findsOneWidget);
      expect(
        find.text('Recurring habits and schedules'),
        findsOneWidget,
      );
    });
  });
}
