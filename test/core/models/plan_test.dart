import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/models/plan.dart';

void main() {
  group('PlanResponse', () {
    final sampleMap = {
      'topics': [
        {
          'topic_ref': 'topic:health',
          'canonical_name': 'Health',
          'items': [
            {
              'entry_id': 'e-1',
              'display_text': 'Exercise daily',
              'plan_bucket': 'committed',
              'confidence': 0.9,
              'conversation_id': 'conv-1',
              'created_at': '2026-04-01T00:00:00.000Z',
            },
          ],
        },
      ],
      'uncategorized': [
        {
          'entry_id': 'e-2',
          'display_text': 'Read more books',
          'plan_bucket': 'candidate',
          'confidence': 0.7,
          'conversation_id': 'conv-2',
          'created_at': '2026-04-02T00:00:00.000Z',
        },
      ],
      'rules': [
        {
          'topic_ref': 'topic:diet',
          'canonical_name': 'Diet',
          'items': [
            {
              'entry_id': 'e-3',
              'display_text': 'No sugar after 8pm',
              'confidence': 0.85,
              'conversation_id': 'conv-3',
              'created_at': '2026-04-03T00:00:00.000Z',
              'record_type': 'constraint',
            },
          ],
        },
      ],
      'rules_uncategorized': <dynamic>[],
      'completed': [
        {
          'topic_ref': 'topic:work',
          'canonical_name': 'Work',
          'items': [
            {
              'entry_id': 'e-4',
              'display_text': 'Ship feature X',
              'confidence': 1.0,
              'conversation_id': 'conv-4',
              'created_at': '2026-03-01T00:00:00.000Z',
              'closed_at': '2026-04-15T00:00:00.000Z',
            },
          ],
        },
      ],
      'completed_uncategorized': <dynamic>[],
      'total_count': 4,
      'observed_at': '2026-04-18T12:00:00.000Z',
    };

    test('fromMap creates correct instance', () {
      final plan = PlanResponse.fromMap(sampleMap);

      expect(plan.topics, hasLength(1));
      expect(plan.uncategorized, hasLength(1));
      expect(plan.rules, hasLength(1));
      expect(plan.rulesUncategorized, isEmpty);
      expect(plan.completed, hasLength(1));
      expect(plan.completedUncategorized, isEmpty);
      expect(plan.totalCount, 4);
      expect(plan.observedAt.year, 2026);
    });

    test('round-trip preserves all fields', () {
      final plan = PlanResponse.fromMap(sampleMap);
      final roundTripped = PlanResponse.fromMap(plan.toMap());

      expect(roundTripped.topics.length, plan.topics.length);
      expect(roundTripped.uncategorized.length, plan.uncategorized.length);
      expect(roundTripped.rules.length, plan.rules.length);
      expect(roundTripped.completed.length, plan.completed.length);
      expect(roundTripped.totalCount, plan.totalCount);
    });

    test('handles null lists as empty', () {
      final minimalMap = {
        'total_count': 0,
        'observed_at': '2026-04-18T12:00:00.000Z',
      };

      final plan = PlanResponse.fromMap(minimalMap);

      expect(plan.topics, isEmpty);
      expect(plan.uncategorized, isEmpty);
      expect(plan.rules, isEmpty);
      expect(plan.rulesUncategorized, isEmpty);
      expect(plan.completed, isEmpty);
      expect(plan.completedUncategorized, isEmpty);
    });

    test('toMap produces valid JSON', () {
      final plan = PlanResponse.fromMap(sampleMap);
      final json = jsonEncode(plan.toMap());
      final decoded = jsonDecode(json) as Map<String, dynamic>;

      expect(decoded['total_count'], 4);
      expect(decoded['topics'], hasLength(1));
    });
  });

  group('PlanTopicGroup', () {
    test('fromMap parses nested items', () {
      final group = PlanTopicGroup.fromMap({
        'topic_ref': 'topic:finance',
        'canonical_name': 'Finance',
        'items': [
          {
            'entry_id': 'e-1',
            'display_text': 'Save money',
            'plan_bucket': 'proposed',
            'confidence': 0.6,
            'conversation_id': 'conv-1',
            'created_at': '2026-04-18T00:00:00.000Z',
          },
        ],
      });

      expect(group.topicRef, 'topic:finance');
      expect(group.canonicalName, 'Finance');
      expect(group.items, hasLength(1));
      expect(group.items[0].displayText, 'Save money');
    });
  });

  group('PlanEntry', () {
    test('fromMap with plan bucket (active entry)', () {
      final entry = PlanEntry.fromMap({
        'entry_id': 'e-1',
        'display_text': 'Do thing',
        'plan_bucket': 'committed',
        'confidence': 0.9,
        'conversation_id': 'conv-1',
        'created_at': '2026-04-18T00:00:00.000Z',
      });

      expect(entry.entryId, 'e-1');
      expect(entry.displayText, 'Do thing');
      expect(entry.planBucket, PlanBucket.committed);
      expect(entry.confidence, 0.9);
      expect(entry.closedAt, isNull);
      expect(entry.recordType, isNull);
    });

    test('fromMap with record type (rule entry)', () {
      final entry = PlanEntry.fromMap({
        'entry_id': 'e-2',
        'display_text': 'Always do X',
        'confidence': 0.8,
        'conversation_id': 'conv-2',
        'created_at': '2026-04-18T00:00:00.000Z',
        'record_type': 'constraint',
      });

      expect(entry.recordType, RecordType.constraint);
      expect(entry.planBucket, isNull);
    });

    test('fromMap with closed_at (completed entry)', () {
      final entry = PlanEntry.fromMap({
        'entry_id': 'e-3',
        'display_text': 'Done thing',
        'confidence': 1.0,
        'conversation_id': 'conv-3',
        'created_at': '2026-03-01T00:00:00.000Z',
        'closed_at': '2026-04-15T00:00:00.000Z',
      });

      expect(entry.closedAt, isNotNull);
      expect(entry.closedAt!.month, 4);
    });

    test('round-trip preserves all fields', () {
      final entry = PlanEntry.fromMap({
        'entry_id': 'e-1',
        'display_text': 'Test entry',
        'plan_bucket': 'candidate',
        'confidence': 0.75,
        'conversation_id': 'conv-1',
        'created_at': '2026-04-18T00:00:00.000Z',
        'closed_at': '2026-04-19T00:00:00.000Z',
        'record_type': 'preference',
      });

      final roundTripped = PlanEntry.fromMap(entry.toMap());

      expect(roundTripped.entryId, entry.entryId);
      expect(roundTripped.displayText, entry.displayText);
      expect(roundTripped.planBucket, PlanBucket.candidate);
      expect(roundTripped.confidence, entry.confidence);
      expect(roundTripped.recordType, RecordType.preference);
      expect(roundTripped.closedAt, isNotNull);
    });

    test('fromMap handles unknown plan_bucket as null', () {
      final entry = PlanEntry.fromMap({
        'entry_id': 'e-1',
        'display_text': 'Unknown bucket',
        'plan_bucket': 'unknown_value',
        'confidence': 0.5,
        'conversation_id': 'conv-1',
        'created_at': '2026-04-18T00:00:00.000Z',
      });

      expect(entry.planBucket, isNull);
    });

    test('fromMap handles unknown record_type as null', () {
      final entry = PlanEntry.fromMap({
        'entry_id': 'e-1',
        'display_text': 'Unknown type',
        'confidence': 0.5,
        'conversation_id': 'conv-1',
        'created_at': '2026-04-18T00:00:00.000Z',
        'record_type': 'unknown_type',
      });

      expect(entry.recordType, isNull);
    });

    test('PlanBucket enum covers all values', () {
      expect(PlanBucket.fromJson('committed'), PlanBucket.committed);
      expect(PlanBucket.fromJson('candidate'), PlanBucket.candidate);
      expect(PlanBucket.fromJson('proposed'), PlanBucket.proposed);
      expect(PlanBucket.fromJson(null), isNull);
    });

    test('RecordType enum covers all values', () {
      expect(RecordType.fromJson('constraint'), RecordType.constraint);
      expect(RecordType.fromJson('preference'), RecordType.preference);
      expect(RecordType.fromJson('decision'), RecordType.decision);
      expect(RecordType.fromJson(null), isNull);
    });
  });
}
