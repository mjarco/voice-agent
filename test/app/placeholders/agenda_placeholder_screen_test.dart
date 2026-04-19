import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/app/placeholders/agenda_placeholder_screen.dart';

void main() {
  group('AgendaPlaceholderScreen', () {
    testWidgets('renders title and gear icon', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: AgendaPlaceholderScreen()),
      );

      expect(find.text('Agenda'), findsWidgets);
      expect(find.byIcon(Icons.settings), findsOneWidget);
      expect(find.byIcon(Icons.calendar_today), findsOneWidget);
      expect(
        find.text('Daily tasks and routine schedule'),
        findsOneWidget,
      );
    });
  });
}
