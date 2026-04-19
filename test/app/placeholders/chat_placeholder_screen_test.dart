import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/app/placeholders/chat_placeholder_screen.dart';

void main() {
  group('ChatPlaceholderScreen', () {
    testWidgets('renders title and gear icon', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: ChatPlaceholderScreen()),
      );

      expect(find.text('Chat'), findsWidgets);
      expect(find.byIcon(Icons.settings), findsOneWidget);
      expect(find.byIcon(Icons.chat_bubble_outline), findsOneWidget);
      expect(
        find.text('Conversations with your agent'),
        findsOneWidget,
      );
    });
  });
}
