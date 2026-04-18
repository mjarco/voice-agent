import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/models/agenda.dart';
import 'package:voice_agent/core/models/conversation_record.dart';
import 'package:voice_agent/core/models/routine.dart';

void main() {
  group('AgendaResponse', () {
    final sampleMap = {
      'date': '2026-04-18',
      'granularity': 'day',
      'from': '2026-04-18',
      'to': '2026-04-18',
      'items': [
        {
          'record_id': 'rec-1',
          'text': 'Buy groceries',
          'topic_ref': 'topic:health',
          'scheduled_for': '2026-04-18',
          'time_window': 'day',
          'origin_role': 'agent',
          'status': 'active',
          'linked_conversation_count': 2,
        },
      ],
      'routine_items': [
        {
          'routine_id': 'rt-1',
          'routine_name': 'Morning exercise',
          'scheduled_for': '2026-04-18',
          'start_time': '07:00',
          'overdue': false,
          'status': 'pending',
          'occurrence_id': 'occ-1',
          'templates': [
            {'text': 'Stretch', 'sort_order': 0},
          ],
        },
      ],
    };

    test('fromMap creates correct instance', () {
      final agenda = AgendaResponse.fromMap(sampleMap);

      expect(agenda.date, '2026-04-18');
      expect(agenda.granularity, 'day');
      expect(agenda.from, '2026-04-18');
      expect(agenda.to, '2026-04-18');
      expect(agenda.items, hasLength(1));
      expect(agenda.routineItems, hasLength(1));
    });

    test('round-trip preserves all fields', () {
      final agenda = AgendaResponse.fromMap(sampleMap);
      final roundTripped = AgendaResponse.fromMap(agenda.toMap());

      expect(roundTripped.date, agenda.date);
      expect(roundTripped.items.length, agenda.items.length);
      expect(roundTripped.routineItems.length, agenda.routineItems.length);
    });

    test('toMap produces valid JSON', () {
      final agenda = AgendaResponse.fromMap(sampleMap);
      final json = jsonEncode(agenda.toMap());
      final decoded = jsonDecode(json) as Map<String, dynamic>;

      expect(decoded['date'], '2026-04-18');
      expect(decoded['items'], hasLength(1));
    });
  });

  group('AgendaItem', () {
    test('fromMap parses all fields', () {
      final item = AgendaItem.fromMap({
        'record_id': 'rec-1',
        'text': 'Task text',
        'topic_ref': 'topic:work',
        'scheduled_for': '2026-04-18',
        'time_window': 'day',
        'origin_role': 'user',
        'status': 'active',
        'linked_conversation_count': 3,
      });

      expect(item.recordId, 'rec-1');
      expect(item.text, 'Task text');
      expect(item.topicRef, 'topic:work');
      expect(item.timeWindow, TimeWindow.day);
      expect(item.originRole, OriginRole.user);
      expect(item.status, RecordStatus.active);
      expect(item.linkedConversationCount, 3);
    });

    test('topicRef is nullable', () {
      final item = AgendaItem.fromMap({
        'record_id': 'rec-1',
        'text': 'Task',
        'scheduled_for': '2026-04-18',
        'time_window': 'day',
        'origin_role': 'agent',
        'status': 'done',
        'linked_conversation_count': 0,
      });

      expect(item.topicRef, isNull);
    });
  });

  group('AgendaRoutineItem', () {
    test('fromMap parses all fields', () {
      final item = AgendaRoutineItem.fromMap({
        'routine_id': 'rt-1',
        'routine_name': 'Exercise',
        'scheduled_for': '2026-04-18',
        'start_time': '07:00',
        'overdue': true,
        'status': 'pending',
        'occurrence_id': 'occ-1',
        'templates': [
          {'text': 'Step 1', 'sort_order': 0},
        ],
      });

      expect(item.routineId, 'rt-1');
      expect(item.routineName, 'Exercise');
      expect(item.startTime, '07:00');
      expect(item.overdue, true);
      expect(item.status, OccurrenceStatus.pending);
      expect(item.occurrenceId, 'occ-1');
      expect(item.templates, hasLength(1));
    });

    test('nullable fields handle absence', () {
      final item = AgendaRoutineItem.fromMap({
        'routine_id': 'rt-1',
        'routine_name': 'Walk',
        'scheduled_for': '2026-04-18',
        'overdue': false,
        'status': 'done',
        'templates': <dynamic>[],
      });

      expect(item.startTime, isNull);
      expect(item.occurrenceId, isNull);
      expect(item.templates, isEmpty);
    });
  });
}
