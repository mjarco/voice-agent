import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/models/conversation_record.dart';
import 'package:voice_agent/features/chat/domain/chat_repository.dart';

ConversationRecord _record({
  String subjectRef = 'ref-1',
  Map<String, dynamic> payload = const {},
}) {
  return ConversationRecord(
    recordId: 'rec-1',
    conversationId: 'conv-1',
    recordType: RecordType.topic,
    subjectRef: subjectRef,
    payload: payload,
    confidence: 0.9,
    originRole: OriginRole.agent,
    assertionMode: 'assert',
    userEndorsed: false,
    sourceEventRefs: [],
  );
}

void main() {
  group('recordDisplayText', () {
    test('returns payload text when present and non-empty', () {
      final record = _record(
        subjectRef: 'fallback',
        payload: {'text': 'The actual text'},
      );

      expect(recordDisplayText(record), 'The actual text');
    });

    test('falls back to subjectRef when payload has no text key', () {
      final record = _record(subjectRef: 'my-subject', payload: {});

      expect(recordDisplayText(record), 'my-subject');
    });

    test('falls back to subjectRef when payload text is null', () {
      final record = _record(
        subjectRef: 'my-subject',
        payload: {'text': null},
      );

      expect(recordDisplayText(record), 'my-subject');
    });

    test('falls back to subjectRef when payload text is empty string', () {
      final record = _record(
        subjectRef: 'my-subject',
        payload: {'text': ''},
      );

      expect(recordDisplayText(record), 'my-subject');
    });
  });
}
