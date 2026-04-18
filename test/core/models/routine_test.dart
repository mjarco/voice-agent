import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/models/routine.dart';

void main() {
  group('OccurrenceStatus', () {
    test('fromString parses snake_case', () {
      expect(
          OccurrenceStatus.fromString('in_progress'), OccurrenceStatus.inProgress);
      expect(OccurrenceStatus.fromString('done'), OccurrenceStatus.done);
    });

    test('toJson returns snake_case', () {
      expect(OccurrenceStatus.inProgress.toJson(), 'in_progress');
    });
  });

  group('TimeWindow', () {
    test('fromString parses ad_hoc', () {
      expect(TimeWindow.fromString('ad_hoc'), TimeWindow.adHoc);
      expect(TimeWindow.fromString('day'), TimeWindow.day);
    });

    test('toJson returns snake_case', () {
      expect(TimeWindow.adHoc.toJson(), 'ad_hoc');
    });
  });

  group('Routine', () {
    final sampleMap = {
      'id': 'rt-1',
      'source_record_id': 'rec-1',
      'name': 'Morning exercise',
      'rrule': 'FREQ=DAILY',
      'cadence': 'daily',
      'start_time': '07:00',
      'status': 'active',
      'templates': [
        {'id': 'tmpl-1', 'text': 'Stretch', 'sort_order': 0},
        {'id': 'tmpl-2', 'text': 'Run', 'sort_order': 1},
      ],
      'next_occurrence': {
        'date': '2026-04-19',
        'time_window': 'day',
      },
      'created_at': '2026-01-01T00:00:00.000Z',
      'updated_at': '2026-04-18T12:00:00.000Z',
    };

    test('fromMap creates correct instance', () {
      final routine = Routine.fromMap(sampleMap);

      expect(routine.id, 'rt-1');
      expect(routine.sourceRecordId, 'rec-1');
      expect(routine.name, 'Morning exercise');
      expect(routine.rrule, 'FREQ=DAILY');
      expect(routine.cadence, 'daily');
      expect(routine.startTime, '07:00');
      expect(routine.status, RoutineStatus.active);
      expect(routine.templates, hasLength(2));
      expect(routine.templates[0].text, 'Stretch');
      expect(routine.templates[1].sortOrder, 1);
      expect(routine.nextOccurrence, isNotNull);
      expect(routine.nextOccurrence!.date, '2026-04-19');
      expect(routine.nextOccurrence!.timeWindow, TimeWindow.day);
    });

    test('round-trip preserves all fields', () {
      final routine = Routine.fromMap(sampleMap);
      final roundTripped = Routine.fromMap(routine.toMap());

      expect(roundTripped.id, routine.id);
      expect(roundTripped.name, routine.name);
      expect(roundTripped.status, routine.status);
      expect(roundTripped.templates.length, routine.templates.length);
      expect(roundTripped.nextOccurrence?.date, routine.nextOccurrence?.date);
    });

    test('templates default to empty list when absent', () {
      final map = Map<String, dynamic>.from(sampleMap);
      map.remove('templates');
      final routine = Routine.fromMap(map);

      expect(routine.templates, isEmpty);
    });

    test('nextOccurrence is null when absent', () {
      final map = Map<String, dynamic>.from(sampleMap);
      map.remove('next_occurrence');
      final routine = Routine.fromMap(map);

      expect(routine.nextOccurrence, isNull);
    });

    test('startTime is null when absent', () {
      final map = Map<String, dynamic>.from(sampleMap);
      map.remove('start_time');
      final routine = Routine.fromMap(map);

      expect(routine.startTime, isNull);
    });

    test('toMap produces valid JSON', () {
      final routine = Routine.fromMap(sampleMap);
      final json = jsonEncode(routine.toMap());
      final decoded = jsonDecode(json) as Map<String, dynamic>;

      expect(decoded['id'], 'rt-1');
      expect(decoded['status'], 'active');
    });
  });

  group('RoutineTemplate', () {
    test('id is optional', () {
      final template = RoutineTemplate.fromMap({
        'text': 'Step one',
        'sort_order': 0,
      });

      expect(template.id, isNull);
      expect(template.text, 'Step one');

      final map = template.toMap();
      expect(map.containsKey('id'), isFalse);
    });
  });

  group('RoutineOccurrence', () {
    final sampleMap = {
      'id': 'occ-1',
      'routine_id': 'rt-1',
      'scheduled_for': '2026-04-18',
      'time_window': 'day',
      'status': 'pending',
      'created_at': '2026-04-18T00:00:00.000Z',
      'updated_at': '2026-04-18T00:00:00.000Z',
    };

    test('fromMap creates correct instance', () {
      final occ = RoutineOccurrence.fromMap(sampleMap);

      expect(occ.id, 'occ-1');
      expect(occ.routineId, 'rt-1');
      expect(occ.scheduledFor, '2026-04-18');
      expect(occ.timeWindow, TimeWindow.day);
      expect(occ.status, OccurrenceStatus.pending);
      expect(occ.conversationId, isNull);
    });

    test('round-trip preserves all fields', () {
      final map = Map<String, dynamic>.from(sampleMap);
      map['conversation_id'] = 'conv-1';
      map['status'] = 'in_progress';

      final occ = RoutineOccurrence.fromMap(map);
      final roundTripped = RoutineOccurrence.fromMap(occ.toMap());

      expect(roundTripped.conversationId, 'conv-1');
      expect(roundTripped.status, OccurrenceStatus.inProgress);
    });
  });

  group('RoutineProposal', () {
    final sampleMap = {
      'id': 'prop-1',
      'topic_ref': 'topic:fitness',
      'name': 'Evening walk',
      'cadence': 'daily',
      'start_time': '18:00',
      'items': [
        {'text': 'Walk 30 min', 'sort_order': 0},
      ],
      'confidence': 0.85,
      'conversation_id': 'conv-1',
      'created_at': '2026-04-18T00:00:00.000Z',
    };

    test('fromMap creates correct instance', () {
      final proposal = RoutineProposal.fromMap(sampleMap);

      expect(proposal.id, 'prop-1');
      expect(proposal.topicRef, 'topic:fitness');
      expect(proposal.name, 'Evening walk');
      expect(proposal.items, hasLength(1));
      expect(proposal.items[0].text, 'Walk 30 min');
      expect(proposal.confidence, 0.85);
    });

    test('round-trip preserves all fields', () {
      final proposal = RoutineProposal.fromMap(sampleMap);
      final roundTripped = RoutineProposal.fromMap(proposal.toMap());

      expect(roundTripped.id, proposal.id);
      expect(roundTripped.name, proposal.name);
      expect(roundTripped.items.length, proposal.items.length);
    });

    test('topicRef is nullable', () {
      final map = Map<String, dynamic>.from(sampleMap);
      map['topic_ref'] = null;

      final proposal = RoutineProposal.fromMap(map);
      expect(proposal.topicRef, isNull);
    });
  });
}
