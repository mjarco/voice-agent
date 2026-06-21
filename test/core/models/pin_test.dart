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
    test('parses a full detail with aliases and source events', () {
      final pin = PinDetail.fromMap({
        'record_id': 'abc123',
        'pin_name': 'garage pinout',
        'topic_label': 'Electronics',
        'text': '# Pinout\n\n| Pin | Signal |',
        'aliases': ['pinout', 'wiring'],
        'source_event_ids': ['event-456'],
        'created_at': '2026-06-15T10:30:00Z',
      });

      expect(pin.recordId, 'abc123');
      expect(pin.pinName, 'garage pinout');
      expect(pin.topicLabel, 'Electronics');
      expect(pin.text, '# Pinout\n\n| Pin | Signal |');
      expect(pin.aliases, ['pinout', 'wiring']);
      expect(pin.sourceEventIds, ['event-456']);
      expect(pin.createdAt, DateTime.utc(2026, 6, 15, 10, 30));
    });

    test('defaults optional lists to empty and topic to null', () {
      final pin = PinDetail.fromMap({
        'record_id': 'abc123',
        'pin_name': 'minimal',
        'text': 'body',
        'created_at': '2026-06-15T10:30:00Z',
      });

      expect(pin.topicLabel, isNull);
      expect(pin.aliases, isEmpty);
      expect(pin.sourceEventIds, isEmpty);
    });
  });
}
