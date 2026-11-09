import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/models/agenda.dart';
import 'package:voice_agent/core/models/routine.dart';

void main() {
  group('AgendaResponse', () {
    // The shape of personal-agent's GET /agenda since ADR-CORE-116: no
    // `items`, routine rows with kind and due_window.
    final sampleMap = {
      'date': '2026-11-10',
      'granularity': 'day',
      'from': '2026-11-10',
      'to': '2026-11-10',
      'routine_items': [
        {
          'routine_id': 'rt-1',
          'routine_name': 'Morning exercise',
          'kind': 'recurring',
          'scheduled_for': '2026-11-10',
          'start_time': '07:00',
          'overdue': false,
          'status': 'pending',
          'occurrence_id': null,
          'templates': [
            {'text': 'Stretch', 'sort_order': 0},
          ],
        },
        {
          'routine_id': 'rt-2',
          'routine_name': 'Call the plumber',
          'kind': 'one_off',
          'scheduled_for': '2026-11-08',
          'due_window': 'week',
          'start_time': null,
          'overdue': false,
          'status': 'pending',
          'occurrence_id': null,
          'templates': [],
        },
      ],
      'calendar_items': [],
      'calendar_sources': [],
    };

    test('reads an agenda without items', () {
      final agenda = AgendaResponse.fromMap(sampleMap);

      expect(agenda.date, '2026-11-10');
      expect(agenda.granularity, 'day');
      expect(agenda.routineItems, hasLength(2));
      expect(agenda.calendarItems, isEmpty);
    });

    test('an old agenda with items still reads; the items are ignored', () {
      final agenda = AgendaResponse.fromMap({
        ...sampleMap,
        'items': [
          {'record_id': 'rec-1', 'text': 'Buy groceries'},
        ],
      });
      expect(agenda.routineItems, hasLength(2));
      expect(agenda.toMap().containsKey('items'), isFalse);
    });

    test('round-trip preserves the rows', () {
      final agenda = AgendaResponse.fromMap(sampleMap);
      final json = jsonDecode(jsonEncode(agenda.toMap()));
      final back = AgendaResponse.fromMap(json as Map<String, dynamic>);

      expect(back.date, agenda.date);
      expect(back.routineItems.map((i) => i.routineId), ['rt-1', 'rt-2']);
      expect(back.routineItems[1].kind, RoutineKind.oneOff);
      expect(back.routineItems[1].dueWindow, TimeWindow.week);
      expect(back.routineItems[0].steps.single.text, 'Stretch');
    });

    test('drops a malformed routine row and keeps the rest', () {
      final agenda = AgendaResponse.fromMap({
        ...sampleMap,
        'routine_items': [
          null,
          {'routine_id': 'x'},
          (sampleMap['routine_items'] as List).first,
        ],
      });
      expect(agenda.routineItems.single.routineId, 'rt-1');
    });
  });

  group('AgendaRoutineItem', () {
    test('a recurring row has no window', () {
      final item = AgendaRoutineItem.fromMap({
        'routine_id': 'rt-1',
        'routine_name': 'Walk',
        'kind': 'recurring',
        'scheduled_for': '2026-11-09',
        'due_window': '',
        'start_time': '07:00',
        'overdue': true,
        'templates': [
          {'text': 'Second', 'sort_order': 1},
          {'text': 'First', 'sort_order': 0},
        ],
      });

      expect(item.kind, RoutineKind.recurring);
      expect(item.isOneOff, isFalse);
      expect(item.dueWindow, isNull);
      expect(item.startTime, '07:00');
      expect(item.overdue, isTrue);
      expect(item.steps.map((s) => s.text), ['First', 'Second']);
    });

    test('a one-off row carries its window', () {
      final item = AgendaRoutineItem.fromMap({
        'routine_id': 'rt-2',
        'routine_name': 'Call the plumber',
        'kind': 'one_off',
        'scheduled_for': '2026-11-08',
        'due_window': 'month',
        'overdue': false,
        'templates': [],
      });

      expect(item.isOneOff, isTrue);
      expect(item.dueWindow, TimeWindow.month);
      expect(item.dueWindow!.describeFrom(item.scheduledFor),
          'within a month from 2026-11-08');
    });

    test('unknown kind and window, missing fields: safe defaults', () {
      final unknown = AgendaRoutineItem.fromMap({
        'routine_id': 'rt-3',
        'routine_name': 'X',
        'kind': 'quarterly',
        'scheduled_for': '2026-11-08',
        'due_window': 'fortnight',
      });
      expect(unknown.kind, RoutineKind.recurring);
      expect(unknown.dueWindow, isNull);
      expect(unknown.overdue, isFalse);
      expect(unknown.steps, isEmpty);

      // A row with a known window but no kind reads as a one-off.
      final windowed = AgendaRoutineItem.fromMap({
        'routine_id': 'rt-4',
        'routine_name': 'Y',
        'scheduled_for': '2026-11-08',
        'due_window': 'week',
      });
      expect(windowed.kind, RoutineKind.oneOff);
    });

    test('a one-off without a window is due on its day', () {
      final item = AgendaRoutineItem.fromMap({
        'routine_id': 'rt-5',
        'routine_name': 'Z',
        'kind': 'one_off',
        'scheduled_for': '2026-11-08',
      });
      expect(item.dueWindow, TimeWindow.day);
      expect(item.dueWindow!.describeFrom('2026-11-08'), 'on 2026-11-08');
    });
  });

  group('AgendaTickedItem', () {
    test('reads ticked_items, newest first as sent, and round-trips them', () {
      final r = AgendaResponse.fromMap({
        'date': '2026-11-09',
        'granularity': 'day',
        'from': '2026-11-09',
        'to': '2026-11-09',
        'routine_items': [],
        'ticked_items': [
          {
            'routine_id': 'r1',
            'routine_name': 'Leki',
            'kind': 'recurring',
            'scheduled_for': '2026-11-07',
            'status': 'skipped',
            'ticked_at': '2026-11-09T12:01:00+01:00',
          },
          {
            'routine_id': 'r2',
            'routine_name': 'Faktura',
            'kind': 'one_off',
            'scheduled_for': '2026-11-05',
            'status': 'done',
            'ticked_at': '2026-11-09T00:30:00+01:00',
          },
        ],
      });
      expect(r.tickedItems.map((t) => t.routineName), ['Leki', 'Faktura']);
      final first = r.tickedItems.first;
      expect(first.status, OccurrenceStatus.skipped);
      expect(first.kind, RoutineKind.recurring);
      expect(first.time, '12:01');
      final again = AgendaResponse.fromMap(
          jsonDecode(jsonEncode(r.toMap())) as Map<String, dynamic>);
      expect(again.tickedItems.map((t) => t.toMap()).toList(),
          r.tickedItems.map((t) => t.toMap()).toList());
    });

    test('an agenda without ticked_items has none', () {
      final r = AgendaResponse.fromMap({
        'date': '2026-11-09',
        'granularity': 'day',
        'from': '2026-11-09',
        'to': '2026-11-09',
        'routine_items': [],
      });
      expect(r.tickedItems, isEmpty);
    });

    test('drops a row it cannot show or undo, keeps the rest', () {
      final r = AgendaResponse.fromMap({
        'date': '2026-11-09',
        'granularity': 'day',
        'from': '2026-11-09',
        'to': '2026-11-09',
        'routine_items': [],
        'ticked_items': [
          {'routine_name': 'no id', 'scheduled_for': '2026-11-09', 'status': 'done'},
          {'routine_id': 'r3', 'routine_name': 'Unknown', 'scheduled_for': '2026-11-09', 'status': 'later'},
          'not a map',
          {'routine_id': 'r4', 'routine_name': 'Kept', 'kind': 'new_kind', 'scheduled_for': '2026-11-09', 'status': 'done'},
        ],
      });
      expect(r.tickedItems.map((t) => t.routineId), ['r4']);
      expect(r.tickedItems.single.kind, isNull);
      expect(r.tickedItems.single.time, isNull);
    });
  });

  group('AgendaCalendarItem', () {
    test('reads calendar_items and round-trips them', () {
      final map = {
        'date': '2026-04-18',
        'granularity': 'day',
        'from': '2026-04-18',
        'to': '2026-04-18',
        'routine_items': [],
        'calendar_items': [
          {
            'calendar': 'CORP',
            'uid': 'su',
            'title': 'Stand-up',
            'start': '2026-04-18T09:00:00+02:00',
            'end': '2026-04-18T09:30:00+02:00',
            'all_day': false,
          },
        ],
      };
      final r = AgendaResponse.fromMap(map);
      expect(r.calendarItems.single.title, 'Stand-up');
      expect(
        AgendaResponse.fromMap(r.toMap()).calendarItems.single.calendar,
        'CORP',
      );
    });

    test('an agenda without calendar_items has no meetings', () {
      final r = AgendaResponse.fromMap({
        'date': '2026-04-18',
        'granularity': 'day',
        'from': '2026-04-18',
        'to': '2026-04-18',
      });
      expect(r.calendarItems, isEmpty);
    });

    test('says when a meeting is on a given day', () {
      AgendaCalendarItem m(String start, String end, {bool allDay = false}) =>
          AgendaCalendarItem(
            calendar: 'C',
            uid: 'u',
            title: 't',
            start: start,
            end: end,
            allDay: allDay,
          );
      const day = '2026-04-18';
      expect(
        m('2026-04-18T09:00:00+02:00', '2026-04-18T09:30:00+02:00').when(day),
        '09:00–09:30',
      );
      expect(
        m('2026-04-18T22:00:00+02:00', '2026-04-19T00:00:00+02:00').when(day),
        '22:00–00:00',
      );
      expect(
        m('2026-04-17T22:00:00+02:00', '2026-04-18T06:00:00+02:00').when(day),
        '2026-04-17 22:00 – 2026-04-18 06:00',
      );
      expect(m('2026-04-18', '2026-04-18', allDay: true).when(day), 'all day');
      expect(
        m('2026-04-17', '2026-04-19', allDay: true).when(day),
        '2026-04-17 – 2026-04-19',
      );
      expect(
        m('2026-04-18T10:00:00+02:00', '2026-04-20T00:00:00+02:00').when(day),
        '2026-04-18 10:00 – 2026-04-20 00:00',
      );
    });

    test('drops a malformed meeting and keeps the rest of the agenda', () {
      const good = {
        'calendar': 'CORP',
        'uid': 'u',
        'title': 't',
        'start': '2026-04-18T09:00:00+02:00',
        'end': '2026-04-18T09:30:00+02:00',
        'all_day': false,
      };
      final r = AgendaResponse.fromMap({
        'date': '2026-04-18',
        'granularity': 'day',
        'from': '2026-04-18',
        'to': '2026-04-18',
        'routine_items': <dynamic>[],
        'calendar_items': [
          null,
          {...good, 'title': null},
          {...good, 'start': '09:00'},
          {...good, 'all_day': true},
          good,
        ],
      });
      expect(r.calendarItems, hasLength(1));
      expect(r.calendarItems.single.title, 't');
    });
  });
}
