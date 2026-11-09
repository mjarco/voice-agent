import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/models/pin.dart';

void main() {
  group('PinSummary.fromMap', () {
    test('parses a row and ignores a topic_label of an older server', () {
      final pin = PinSummary.fromMap({
        'record_id': 'abc123',
        'pin_name': 'garage pinout',
        'topic_label': 'Electronics',
        'created_at': '2026-06-15T10:30:00Z',
      });

      expect(pin.recordId, 'abc123');
      expect(pin.pinName, 'garage pinout');
      expect(pin.createdAt, DateTime.utc(2026, 6, 15, 10, 30));
    });

    test('parses a row of personal-agent R2 (no topic, extra fields)', () {
      final pin = PinSummary.fromMap({
        'record_id': 'abc123',
        'pin_name': 'garage pinout',
        'created_at': '2026-06-15T10:30:00Z',
        'day': '2026-06-15',
      });

      expect(pin.pinName, 'garage pinout');
    });
  });

  group('PinDetail.fromMap', () {
    test('parses a full detail with aliases, source events and conversation',
        () {
      final pin = PinDetail.fromMap({
        'record_id': 'abc123',
        'pin_name': 'garage pinout',
        'text': '# Pinout\n\n| Pin | Signal |',
        'aliases': ['pinout', 'wiring'],
        'conversation_id': 'conv-789',
        'source_event_ids': ['event-456'],
        'created_at': '2026-06-15T10:30:00Z',
      });

      expect(pin.recordId, 'abc123');
      expect(pin.pinName, 'garage pinout');
      expect(pin.text, '# Pinout\n\n| Pin | Signal |');
      expect(pin.aliases, ['pinout', 'wiring']);
      expect(pin.conversationId, 'conv-789');
      expect(pin.sourceEventIds, ['event-456']);
      expect(pin.createdAt, DateTime.utc(2026, 6, 15, 10, 30));
    });

    test('defaults optional lists to empty and the conversation to null', () {
      final pin = PinDetail.fromMap({
        'record_id': 'abc123',
        'pin_name': 'minimal',
        'text': 'body',
        'created_at': '2026-06-15T10:30:00Z',
      });

      expect(pin.aliases, isEmpty);
      expect(pin.conversationId, isNull);
      expect(pin.sourceEventIds, isEmpty);
    });

    test('a malformed optional field is empty, never an error', () {
      final pin = PinDetail.fromMap({
        'record_id': 'abc123',
        'pin_name': 'odd',
        'text': 'body',
        'created_at': '2026-06-15T10:30:00Z',
        'aliases': 'not a list',
        'source_event_ids': ['e1', 7, null],
        'conversation_id': '',
      });

      expect(pin.aliases, isEmpty);
      expect(pin.sourceEventIds, ['e1']);
      expect(pin.conversationId, isNull);
    });
  });

  group('PinSuggestion.fromMap', () {
    test('parses name and aliases, ignoring topic fields', () {
      final s = PinSuggestion.fromMap({
        'name': 'ESP32 GPIO pinout',
        'aliases': ['pinout'],
        'topic_label': 'Electronics',
        'topic_ref': 'topic-1',
      });

      expect(s.name, 'ESP32 GPIO pinout');
      expect(s.aliases, ['pinout']);
    });

    test('a missing or malformed name is empty', () {
      expect(PinSuggestion.fromMap({}).name, '');
      expect(PinSuggestion.fromMap({'name': 3}).name, '');
    });
  });

  group('PinCreateRequest.toMap', () {
    test('emits identity and name only', () {
      const req = PinCreateRequest(
        conversationId: 'conv-1',
        eventId: 'event-9',
        name: 'garage pinout',
      );

      expect(req.toMap(), {
        'conversation_id': 'conv-1',
        'event_id': 'event-9',
        'name': 'garage pinout',
      });
    });
  });

  group('PinTextCreateRequest.toMap', () {
    test('sends aliases when there are any, never a topic', () {
      const req = PinTextCreateRequest(
        text: 't',
        name: 'n',
        aliases: ['a'],
      );

      expect(req.toMap(), {
        'text': 't',
        'name': 'n',
        'aliases': ['a'],
      });
      expect(
        const PinTextCreateRequest(text: 't', name: 'n').toMap(),
        {'text': 't', 'name': 'n'},
      );
    });
  });

  group('PinCreateResult.fromMap', () {
    test('parses the nested pin and idempotency metadata', () {
      final r = PinCreateResult.fromMap({
        'pin': {
          'record_id': 'abc123',
          'pin_name': 'garage pinout',
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
        'created': 'yes',
        'superseded_record_id': null,
      });

      expect(r.created, isFalse);
      expect(r.supersededRecordId, '');
    });
  });
}
