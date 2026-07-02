import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/models/pin.dart';

void main() {
  group('PinSummary.fromMap', () {
    test('parses a full row', () {
      final pin = PinSummary.fromMap({
        'record_id': 'abc123',
        'pin_name': 'garage pinout',
        'topic_label': 'Electronics',
        'created_at': '2026-06-15T10:30:00Z',
      });

      expect(pin.recordId, 'abc123');
      expect(pin.pinName, 'garage pinout');
      expect(pin.topicLabel, 'Electronics');
      expect(pin.createdAt, DateTime.utc(2026, 6, 15, 10, 30));
    });

    test('tolerates a missing topic_label (omitempty)', () {
      final pin = PinSummary.fromMap({
        'record_id': 'abc123',
        'pin_name': 'no topic',
        'created_at': '2026-06-15T10:30:00Z',
      });

      expect(pin.topicLabel, isNull);
    });
  });

  group('PinDetail.fromMap', () {
    test('parses a full detail with aliases, source events and conversation',
        () {
      final pin = PinDetail.fromMap({
        'record_id': 'abc123',
        'pin_name': 'garage pinout',
        'topic_label': 'Electronics',
        'text': '# Pinout\n\n| Pin | Signal |',
        'aliases': ['pinout', 'wiring'],
        'conversation_id': 'conv-789',
        'source_event_ids': ['event-456'],
        'created_at': '2026-06-15T10:30:00Z',
      });

      expect(pin.recordId, 'abc123');
      expect(pin.pinName, 'garage pinout');
      expect(pin.topicLabel, 'Electronics');
      expect(pin.text, '# Pinout\n\n| Pin | Signal |');
      expect(pin.aliases, ['pinout', 'wiring']);
      expect(pin.conversationId, 'conv-789');
      expect(pin.sourceEventIds, ['event-456']);
      expect(pin.createdAt, DateTime.utc(2026, 6, 15, 10, 30));
    });

    test('defaults optional lists to empty, conversation and topic to null',
        () {
      final pin = PinDetail.fromMap({
        'record_id': 'abc123',
        'pin_name': 'minimal',
        'text': 'body',
        'created_at': '2026-06-15T10:30:00Z',
      });

      expect(pin.topicLabel, isNull);
      expect(pin.aliases, isEmpty);
      expect(pin.conversationId, isNull);
      expect(pin.sourceEventIds, isEmpty);
    });
  });

  group('PinSuggestion.fromMap', () {
    test('parses name and topic, ignoring aliases and topic_ref', () {
      final s = PinSuggestion.fromMap({
        'name': 'ESP32 GPIO pinout',
        'aliases': ['pinout'],
        'topic_label': 'Electronics',
        'topic_ref': 'topic-1',
      });

      expect(s.name, 'ESP32 GPIO pinout');
      expect(s.topicLabel, 'Electronics');
    });

    test('leaves topic null when the backend matched none', () {
      final s = PinSuggestion.fromMap({'name': 'x', 'topic_label': ''});

      expect(s.name, 'x');
      expect(s.topicLabel, '');
    });
  });

  group('PinCreateRequest.toMap', () {
    test('emits identity + name + topic when topic is present', () {
      const req = PinCreateRequest(
        conversationId: 'conv-1',
        eventId: 'event-9',
        name: 'garage pinout',
        topicLabel: 'Electronics',
      );

      expect(req.toMap(), {
        'conversation_id': 'conv-1',
        'event_id': 'event-9',
        'name': 'garage pinout',
        'topic_label': 'Electronics',
      });
    });

    test('omits topic_label when null or empty (backend omitempty)', () {
      const nullTopic = PinCreateRequest(
        conversationId: 'conv-1',
        eventId: 'event-9',
        name: 'n',
      );
      const emptyTopic = PinCreateRequest(
        conversationId: 'conv-1',
        eventId: 'event-9',
        name: 'n',
        topicLabel: '',
      );

      expect(nullTopic.toMap().containsKey('topic_label'), isFalse);
      expect(emptyTopic.toMap().containsKey('topic_label'), isFalse);
    });

    test('never sends aliases', () {
      const req = PinCreateRequest(
        conversationId: 'c',
        eventId: 'e',
        name: 'n',
        topicLabel: 't',
      );

      expect(req.toMap().containsKey('aliases'), isFalse);
    });
  });

  group('PinCreateResult.fromMap', () {
    test('parses the nested pin and idempotency metadata', () {
      final r = PinCreateResult.fromMap({
        'pin': {
          'record_id': 'abc123',
          'pin_name': 'garage pinout',
          'topic_label': 'Electronics',
          'text': '# Pinout',
          'created_at': '2026-06-15T10:30:00Z',
        },
        'created': true,
        'superseded_record_id': 'old-1',
      });

      expect(r.pin.recordId, 'abc123');
      expect(r.pin.text, '# Pinout');
      expect(r.created, isTrue);
      expect(r.supersededRecordId, 'old-1');
    });

    test('defaults created to false and superseded to empty', () {
      final r = PinCreateResult.fromMap({
        'pin': {
          'record_id': 'abc123',
          'pin_name': 'p',
          'text': 'body',
          'created_at': '2026-06-15T10:30:00Z',
        },
      });

      expect(r.created, isFalse);
      expect(r.supersededRecordId, '');
    });
  });
}
