import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/models/routine.dart';

/// A routine as personal-agent's API sends it since ADR-CORE-116.
Map<String, dynamic> _oneOffMap() => {
      'id': 'rtn-1',
      'name': 'Zadzwonić do hydraulika',
      'kind': 'one_off',
      'rrule': '',
      'due_on': '2026-11-10',
      'due_window': 'day',
      'start_time': '09:30',
      'status': 'active',
      'missed': 'waits',
      'active_since': '2026-11-09',
      'steps': [
        {'text': 'Find the number', 'sort_order': 0},
      ],
      'ended': false,
      'last_day': null,
      'next_due': '2026-11-10',
      'resolved': null,
      'source': 'chat',
      'conversation_id': 'conv-1',
      'event_id': 'ev-1',
      'created_at': '2026-11-09T08:00:00Z',
      'updated_at': '2026-11-09T08:00:00Z',
    };

void main() {
  group('enums read tolerantly', () {
    test('OccurrenceStatus: known values, unknown → pending', () {
      expect(OccurrenceStatus.fromString('done'), OccurrenceStatus.done);
      expect(OccurrenceStatus.fromString('skipped'), OccurrenceStatus.skipped);
      expect(OccurrenceStatus.fromString('in_progress'),
          OccurrenceStatus.pending);
      expect(OccurrenceStatus.fromString(null), OccurrenceStatus.pending);
      expect(OccurrenceStatus.done.toJson(), 'done');
    });

    test('RoutineStatus: draft and unknown read as paused', () {
      expect(RoutineStatus.fromString('active'), RoutineStatus.active);
      expect(RoutineStatus.fromString('archived'), RoutineStatus.archived);
      expect(RoutineStatus.fromString('draft'), RoutineStatus.paused);
      expect(RoutineStatus.fromString(42), RoutineStatus.paused);
    });

    test('TimeWindow: ad_hoc, empty and unknown are no window', () {
      expect(TimeWindow.tryParse('week'), TimeWindow.week);
      expect(TimeWindow.tryParse('ad_hoc'), isNull);
      expect(TimeWindow.tryParse(''), isNull);
      expect(TimeWindow.tryParse(null), isNull);
    });

    test('RoutineMissed and RoutineKind', () {
      expect(RoutineMissed.fromString('waits'), RoutineMissed.waits);
      expect(RoutineMissed.fromString('sometimes'), RoutineMissed.lapses);
      expect(RoutineKind.tryParse('one_off'), RoutineKind.oneOff);
      expect(RoutineKind.tryParse('weekly'), isNull);
      expect(RoutineKind.oneOff.toJson(), 'one_off');
    });

    test('TimeWindow describes a term from its day', () {
      expect(TimeWindow.day.describeFrom('2026-11-10'), 'on 2026-11-10');
      expect(TimeWindow.week.describeFrom('2026-11-10'),
          'within a week from 2026-11-10');
    });
  });

  group('Routine', () {
    test('reads a one-off with every new field', () {
      final r = Routine.fromMap(_oneOffMap());

      expect(r.kind, RoutineKind.oneOff);
      expect(r.isRecurring, isFalse);
      expect(r.rrule, '');
      expect(r.dueOn, '2026-11-10');
      expect(r.dueWindow, TimeWindow.day);
      expect(r.startTime, '09:30');
      expect(r.status, RoutineStatus.active);
      expect(r.missed, RoutineMissed.waits);
      expect(r.steps.single.text, 'Find the number');
      expect(r.nextDue, '2026-11-10');
      expect(r.resolved, isNull);
      expect(r.source, 'chat');
      expect(r.conversationId, 'conv-1');
      expect(r.eventId, 'ev-1');
      expect(r.existing, isFalse);
      expect(r.createdAt, DateTime.utc(2026, 11, 9, 8));
    });

    test('reads a resolved someday routine and existing', () {
      final r = Routine.fromMap({
        ..._oneOffMap(),
        'kind': 'someday',
        'due_on': null,
        'due_window': null,
        'ended': true,
        'resolved': {
          'id': 'occ-1',
          'routine_id': 'rtn-1',
          'scheduled_for': '2026-11-09',
          'status': 'skipped',
          'created_at': '2026-11-09T10:00:00Z',
          'updated_at': '2026-11-09T10:00:00Z',
        },
        'existing': true,
      });

      expect(r.kind, RoutineKind.someday);
      expect(r.dueOn, isNull);
      expect(r.dueWindow, isNull);
      expect(r.ended, isTrue);
      expect(r.resolved!.status, OccurrenceStatus.skipped);
      expect(r.resolved!.scheduledFor, '2026-11-09');
      expect(r.existing, isTrue);
    });

    test('unknown values and missing fields do not throw', () {
      final r = Routine.fromMap({
        'id': 'rtn-2',
        'name': 'Old shape',
        'kind': 'project',
        'rrule': null,
        'status': 'draft',
        'missed': 'maybe',
        'due_window': 'ad_hoc',
        'steps': [
          {'text': 'kept'},
          {'sort_order': 1},
          'junk',
        ],
        'resolved': {'status': 'done'},
        'created_at': 'not a date',
      });

      expect(r.kind, RoutineKind.someday);
      expect(r.rrule, '');
      expect(r.status, RoutineStatus.paused);
      expect(r.missed, RoutineMissed.lapses);
      expect(r.dueWindow, isNull);
      expect(r.steps.single.text, 'kept');
      expect(r.resolved, isNull);
      expect(r.source, 'web');
      expect(r.createdAt.millisecondsSinceEpoch, 0);
    });

    test('a missing kind is derived from the fields', () {
      final recurring = Routine.fromMap(
          {'id': 'a', 'name': 'a', 'rrule': 'FREQ=DAILY', 'status': 'active'});
      final oneOff = Routine.fromMap(
          {'id': 'b', 'name': 'b', 'due_on': '2026-11-10', 'status': 'active'});
      expect(recurring.kind, RoutineKind.recurring);
      expect(oneOff.kind, RoutineKind.oneOff);
      expect(oneOff.dueWindow, TimeWindow.day);
    });

    test('ignores the removed fields of the old shape', () {
      final r = Routine.fromMap({
        ..._oneOffMap(),
        'source_record_id': 'src-1',
        'templates': [
          {'id': 'tpl-1', 'text': 'Old', 'sort_order': 0},
        ],
        'cadence': 'daily',
        'next_occurrence': {'date': '2026-11-10', 'time_window': 'day'},
        'previous_routine_id': 'rtn-0',
      });
      expect(r.steps.single.text, 'Find the number');
      expect(r.toMap().containsKey('templates'), isFalse);
      expect(r.toMap().containsKey('source_record_id'), isFalse);
    });

    test('round-trip through JSON keeps the fields', () {
      final r = Routine.fromMap(_oneOffMap());
      final back = Routine.fromMap(
          jsonDecode(jsonEncode(r.toMap())) as Map<String, dynamic>);

      expect(back.kind, r.kind);
      expect(back.dueOn, r.dueOn);
      expect(back.dueWindow, r.dueWindow);
      expect(back.steps.single.sortOrder, 0);
      expect(back.source, r.source);
      expect(back.updatedAt, r.updatedAt);
    });
  });

  group('RoutineOccurrence', () {
    test('reads a tick and round-trips it', () {
      final o = RoutineOccurrence.fromMap({
        'id': 'occ-1',
        'routine_id': 'rtn-1',
        'scheduled_for': '2026-11-09',
        'status': 'done',
        'created_at': '2026-11-09T10:00:00Z',
        'updated_at': '2026-11-09T10:00:00Z',
      });
      expect(o.status, OccurrenceStatus.done);
      final back = RoutineOccurrence.fromMap(o.toMap());
      expect(back.scheduledFor, '2026-11-09');
      expect(back.routineId, 'rtn-1');
    });
  });
}
