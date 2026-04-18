import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/models/conversation_record.dart';

void main() {
  group('RecordType', () {
    test('fromString parses snake_case backend values', () {
      expect(RecordType.fromString('action_item'), RecordType.actionItem);
      expect(RecordType.fromString('summary_note'), RecordType.summaryNote);
      expect(RecordType.fromString('journal_note'), RecordType.journalNote);
      expect(
          RecordType.fromString('routine_proposal'), RecordType.routineProposal);
      expect(RecordType.fromString('topic'), RecordType.topic);
    });

    test('toJson returns snake_case', () {
      expect(RecordType.actionItem.toJson(), 'action_item');
      expect(RecordType.summaryNote.toJson(), 'summary_note');
      expect(RecordType.routineProposal.toJson(), 'routine_proposal');
    });

    test('fromString throws on unknown value', () {
      expect(() => RecordType.fromString('unknown'), throwsArgumentError);
    });
  });

  group('ConversationRecord', () {
    final sampleMap = {
      'record_id': 'rec-1',
      'conversation_id': 'conv-1',
      'record_type': 'action_item',
      'subject_ref': 'topic:health',
      'payload': {'text': 'Buy groceries'},
      'confidence': 0.95,
      'origin_role': 'agent',
      'assertion_mode': 'extracted',
      'user_endorsed': true,
      'source_event_refs': ['evt-1', 'evt-2'],
    };

    test('fromMap creates correct instance', () {
      final record = ConversationRecord.fromMap(sampleMap);

      expect(record.recordId, 'rec-1');
      expect(record.conversationId, 'conv-1');
      expect(record.recordType, RecordType.actionItem);
      expect(record.subjectRef, 'topic:health');
      expect(record.payload, {'text': 'Buy groceries'});
      expect(record.confidence, 0.95);
      expect(record.originRole, OriginRole.agent);
      expect(record.assertionMode, 'extracted');
      expect(record.userEndorsed, true);
      expect(record.sourceEventRefs, ['evt-1', 'evt-2']);
    });

    test('round-trip fromMap/toMap preserves all fields', () {
      final record = ConversationRecord.fromMap(sampleMap);
      final roundTripped = ConversationRecord.fromMap(record.toMap());

      expect(roundTripped.recordId, record.recordId);
      expect(roundTripped.conversationId, record.conversationId);
      expect(roundTripped.recordType, record.recordType);
      expect(roundTripped.subjectRef, record.subjectRef);
      expect(roundTripped.payload, record.payload);
      expect(roundTripped.confidence, record.confidence);
      expect(roundTripped.originRole, record.originRole);
      expect(roundTripped.assertionMode, record.assertionMode);
      expect(roundTripped.userEndorsed, record.userEndorsed);
      expect(roundTripped.sourceEventRefs, record.sourceEventRefs);
    });

    test('toMap produces valid JSON', () {
      final record = ConversationRecord.fromMap(sampleMap);
      final json = jsonEncode(record.toMap());
      final decoded = jsonDecode(json) as Map<String, dynamic>;

      expect(decoded['record_id'], 'rec-1');
      expect(decoded['record_type'], 'action_item');
    });

    test('fromMap handles all record types', () {
      for (final type in RecordType.values) {
        final map = Map<String, dynamic>.from(sampleMap);
        map['record_type'] = type.toJson();
        final record = ConversationRecord.fromMap(map);
        expect(record.recordType, type);
      }
    });
  });
}
