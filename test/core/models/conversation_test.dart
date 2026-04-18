import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/models/conversation.dart';

void main() {
  group('Conversation', () {
    final sampleMap = {
      'conversation_id': 'conv-1',
      'session_id': 'sess-1',
      'status': 'open',
      'created_at': '2026-04-18T10:00:00.000Z',
      'event_count': 5,
      'last_event_at': '2026-04-18T10:30:00.000Z',
      'first_message_preview': 'Hello agent',
      'subject_record_id': 'rec-1',
      'subject_record_text': 'Health topic',
      'subject_record_status': 'active',
    };

    test('fromMap creates correct instance', () {
      final conv = Conversation.fromMap(sampleMap);

      expect(conv.conversationId, 'conv-1');
      expect(conv.sessionId, 'sess-1');
      expect(conv.status, ConversationStatus.open);
      expect(conv.eventCount, 5);
      expect(conv.lastEventAt, isNotNull);
      expect(conv.firstMessagePreview, 'Hello agent');
      expect(conv.subjectRecordId, 'rec-1');
      expect(conv.subjectRecordText, 'Health topic');
      expect(conv.subjectRecordStatus, 'active');
    });

    test('round-trip preserves all fields', () {
      final conv = Conversation.fromMap(sampleMap);
      final roundTripped = Conversation.fromMap(conv.toMap());

      expect(roundTripped.conversationId, conv.conversationId);
      expect(roundTripped.sessionId, conv.sessionId);
      expect(roundTripped.status, conv.status);
      expect(roundTripped.eventCount, conv.eventCount);
      expect(roundTripped.firstMessagePreview, conv.firstMessagePreview);
      expect(roundTripped.subjectRecordId, conv.subjectRecordId);
    });

    test('nullable fields handle absence', () {
      final minimalMap = {
        'conversation_id': 'conv-2',
        'session_id': 'sess-2',
        'status': 'closed',
        'created_at': '2026-04-18T10:00:00.000Z',
        'event_count': 0,
      };

      final conv = Conversation.fromMap(minimalMap);

      expect(conv.lastEventAt, isNull);
      expect(conv.firstMessagePreview, isNull);
      expect(conv.subjectRecordId, isNull);
      expect(conv.subjectRecordText, isNull);
      expect(conv.subjectRecordStatus, isNull);
    });

    test('toMap produces valid JSON', () {
      final conv = Conversation.fromMap(sampleMap);
      final json = jsonEncode(conv.toMap());
      final decoded = jsonDecode(json) as Map<String, dynamic>;

      expect(decoded['conversation_id'], 'conv-1');
      expect(decoded['status'], 'open');
    });
  });

  group('ConversationEvent', () {
    final sampleMap = {
      'event_id': 'evt-1',
      'conversation_id': 'conv-1',
      'sequence': 3,
      'role': 'user',
      'content': 'Tell me about my agenda',
      'occurred_at': '2026-04-18T10:00:00.000Z',
      'received_at': '2026-04-18T10:00:01.000Z',
    };

    test('fromMap creates correct instance', () {
      final event = ConversationEvent.fromMap(sampleMap);

      expect(event.eventId, 'evt-1');
      expect(event.conversationId, 'conv-1');
      expect(event.sequence, 3);
      expect(event.role, EventRole.user);
      expect(event.content, 'Tell me about my agenda');
      expect(event.occurredAt, isNotNull);
      expect(event.receivedAt, isNotNull);
    });

    test('round-trip preserves all fields', () {
      final event = ConversationEvent.fromMap(sampleMap);
      final roundTripped = ConversationEvent.fromMap(event.toMap());

      expect(roundTripped.eventId, event.eventId);
      expect(roundTripped.sequence, event.sequence);
      expect(roundTripped.role, event.role);
      expect(roundTripped.content, event.content);
    });

    test('occurredAt is nullable', () {
      final map = Map<String, dynamic>.from(sampleMap);
      map.remove('occurred_at');

      final event = ConversationEvent.fromMap(map);
      expect(event.occurredAt, isNull);
    });

    test('agent role parses correctly', () {
      final map = Map<String, dynamic>.from(sampleMap);
      map['role'] = 'agent';

      final event = ConversationEvent.fromMap(map);
      expect(event.role, EventRole.agent);
    });
  });
}
