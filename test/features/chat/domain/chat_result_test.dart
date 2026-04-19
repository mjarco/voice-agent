import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/features/chat/domain/chat_repository.dart';

void main() {
  group('ChatResult.fromMap', () {
    test('parses all fields present', () {
      final map = {
        'conversation_id': 'conv-1',
        'user_event_id': 'evt-u-1',
        'agent_event_id': 'evt-a-1',
        'reply': 'Hello',
        'backend': 'groq',
        'knowledge_extraction': {'user_status': 'ok', 'agent_status': 'ok'},
        'warnings': ['something'],
      };

      final result = ChatResult.fromMap(map);

      expect(result.conversationId, 'conv-1');
      expect(result.userEventId, 'evt-u-1');
      expect(result.agentEventId, 'evt-a-1');
      expect(result.reply, 'Hello');
      expect(result.backend, 'groq');
    });

    test('handles absent agentEventId', () {
      final map = {
        'conversation_id': 'conv-1',
        'user_event_id': 'evt-u-1',
        'reply': 'Hello',
      };

      final result = ChatResult.fromMap(map);

      expect(result.agentEventId, isNull);
    });

    test('handles absent backend', () {
      final map = {
        'conversation_id': 'conv-1',
        'user_event_id': 'evt-u-1',
        'reply': 'Hello',
      };

      final result = ChatResult.fromMap(map);

      expect(result.backend, isNull);
    });

    test('ignores knowledge_extraction and warnings', () {
      final map = {
        'conversation_id': 'conv-1',
        'user_event_id': 'evt-u-1',
        'reply': 'Hello',
        'knowledge_extraction': {'user_status': 'pending'},
        'warnings': ['w1', 'w2'],
      };

      final result = ChatResult.fromMap(map);

      expect(result.conversationId, 'conv-1');
      expect(result.reply, 'Hello');
    });

    test('throws on missing required fields', () {
      expect(
        () => ChatResult.fromMap({'conversation_id': 'conv-1'}),
        throwsA(isA<TypeError>()),
      );
    });
  });
}
