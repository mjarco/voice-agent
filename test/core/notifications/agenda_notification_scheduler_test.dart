import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'package:voice_agent/core/models/agenda.dart';
import 'package:voice_agent/core/models/conversation_record.dart';
import 'package:voice_agent/core/models/routine.dart';
import 'package:voice_agent/core/notifications/agenda_notification_scheduler.dart';
import 'package:voice_agent/core/notifications/domain/notification_service.dart';

/// In-memory fake that records all calls and maintains its own snapshot.
class FakeNotificationService implements NotificationService {
  final Map<int, ScheduledNotification> _snapshot = {};
  final List<String> calls = [];
  bool permitted = true;

  @override
  Future<void> init() async {
    calls.add('init');
  }

  @override
  Future<bool> requestPermission() async {
    calls.add('requestPermission');
    return permitted;
  }

  @override
  Future<bool> isPermitted() async => permitted;

  @override
  Future<void> schedule(ScheduledNotification n) async {
    calls.add('schedule(${n.id})');
    _snapshot[n.id] = n;
  }

  @override
  Future<void> cancel(int id) async {
    calls.add('cancel($id)');
    _snapshot.remove(id);
  }

  @override
  Future<Map<int, ScheduledNotification>> currentlyScheduled() async =>
      Map.unmodifiable(_snapshot);

  @override
  Future<void> cancelAll() async {
    calls.add('cancelAll');
    _snapshot.clear();
  }

  int get scheduleCount => calls.where((c) => c.startsWith('schedule(')).length;
  int get cancelCount =>
      calls.where((c) => c.startsWith('cancel(') && c != 'cancelAll').length;
}

void main() {
  late tz.Location warsaw;
  late FakeNotificationService service;

  setUpAll(() {
    tz_data.initializeTimeZones();
    warsaw = tz.getLocation('Europe/Warsaw');
  });

  setUp(() {
    service = FakeNotificationService();
  });

  AgendaNotificationScheduler buildScheduler({
    required DateTime now,
  }) {
    return AgendaNotificationScheduler(
      service: service,
      location: warsaw,
      clock: () => now,
    );
  }

  AgendaResponse responseFor(
    String date, {
    List<AgendaItem> items = const [],
    List<AgendaRoutineItem> routineItems = const [],
  }) =>
      AgendaResponse(
        date: date,
        granularity: 'day',
        from: '${date}T00:00:00Z',
        to: '${date}T23:59:59Z',
        items: items,
        routineItems: routineItems,
      );

  AgendaItem actionItem(
    String id, {
    required RecordStatus status,
    String scheduledFor = '2026-05-17',
  }) =>
      AgendaItem(
        recordId: id,
        text: 'Item $id',
        scheduledFor: scheduledFor,
        timeWindow: TimeWindow.day,
        originRole: OriginRole.user,
        status: status,
        linkedConversationCount: 0,
      );

  AgendaRoutineItem routine(
    String routineId, {
    required String name,
    String scheduledFor = '2026-05-17',
    String? startTime = '14:30',
    String? occurrenceId = 'occ-001',
    OccurrenceStatus status = OccurrenceStatus.pending,
  }) =>
      AgendaRoutineItem(
        routineId: routineId,
        routineName: name,
        scheduledFor: scheduledFor,
        startTime: startTime,
        overdue: false,
        status: status,
        occurrenceId: occurrenceId,
        templates: const [],
      );

  group('summaries', () {
    test('empty response → 4 summary slots scheduled for today', () async {
      // 2026-05-17 08:00 Warsaw — all 4 slots still in future
      final scheduler = buildScheduler(now: DateTime(2026, 5, 17, 8, 0));
      await scheduler.reconcile(
        responseFor('2026-05-17'),
        sessionActive: false,
      );
      expect(service.scheduleCount, 4);
      expect(service.cancelCount, 0);
      // IDs 1000-1003
      final snapshot = await service.currentlyScheduled();
      expect(snapshot.keys, containsAll([1000, 1001, 1002, 1003]));
    });

    test('past slot is scheduled for tomorrow', () async {
      // 13:00 — Morning (09:00) and Noon (12:00) are past
      final scheduler = buildScheduler(now: DateTime(2026, 5, 17, 13, 0));
      await scheduler.reconcile(
        responseFor('2026-05-17'),
        sessionActive: false,
      );
      final snapshot = await service.currentlyScheduled();
      final morning = snapshot[1000]!;
      final noon = snapshot[1001]!;
      final afternoon = snapshot[1002]!;
      expect(morning.fireAt.day, 18); // tomorrow
      expect(morning.fireAt.hour, 9);
      expect(noon.fireAt.day, 18);
      expect(noon.fireAt.hour, 12);
      expect(afternoon.fireAt.day, 17); // still today
      expect(afternoon.fireAt.hour, 15);
    });

    test('body: all-zero counts → "nothing scheduled today"', () async {
      final scheduler = buildScheduler(now: DateTime(2026, 5, 17, 8, 0));
      await scheduler.reconcile(
        responseFor('2026-05-17'),
        sessionActive: false,
      );
      final snapshot = await service.currentlyScheduled();
      expect(snapshot[1000]!.body, 'Morning: nothing scheduled today');
    });

    test('body: counts grouped by status with zero-elision', () async {
      final scheduler = buildScheduler(now: DateTime(2026, 5, 17, 8, 0));
      await scheduler.reconcile(
        responseFor('2026-05-17', items: [
          actionItem('a1', status: RecordStatus.active),
          actionItem('a2', status: RecordStatus.active),
          actionItem('a3', status: RecordStatus.active),
          actionItem('d1', status: RecordStatus.done),
          actionItem('p1', status: RecordStatus.promoted), // counted as done
          actionItem('s1', status: RecordStatus.superseded), // dismissed
        ]),
        sessionActive: false,
      );
      final snapshot = await service.currentlyScheduled();
      // open=3, done=2 (1 done + 1 promoted), dismissed=1
      expect(snapshot[1000]!.body, 'Morning: 3 open, 2 done, 1 dismissed');
    });

    test('body: zero terms elided', () async {
      final scheduler = buildScheduler(now: DateTime(2026, 5, 17, 8, 0));
      await scheduler.reconcile(
        responseFor('2026-05-17', items: [
          actionItem('a1', status: RecordStatus.active),
          actionItem('a2', status: RecordStatus.active),
        ]),
        sessionActive: false,
      );
      final snapshot = await service.currentlyScheduled();
      expect(snapshot[1000]!.body, 'Morning: 2 open');
    });

    test('slot labels are Morning/Noon/Afternoon/Evening', () async {
      final scheduler = buildScheduler(now: DateTime(2026, 5, 17, 8, 0));
      await scheduler.reconcile(
        responseFor('2026-05-17'),
        sessionActive: false,
      );
      final snapshot = await service.currentlyScheduled();
      expect(snapshot[1000]!.body, startsWith('Morning:'));
      expect(snapshot[1001]!.body, startsWith('Noon:'));
      expect(snapshot[1002]!.body, startsWith('Afternoon:'));
      expect(snapshot[1003]!.body, startsWith('Evening:'));
    });

    test('payload is /agenda for all summaries', () async {
      final scheduler = buildScheduler(now: DateTime(2026, 5, 17, 8, 0));
      await scheduler.reconcile(
        responseFor('2026-05-17'),
        sessionActive: false,
      );
      final snapshot = await service.currentlyScheduled();
      for (final id in [1000, 1001, 1002, 1003]) {
        expect(snapshot[id]!.payload, '/agenda');
      }
    });

    test('summaries fire in Warsaw local time, not UTC', () async {
      // 2026-05-17 08:00 local Warsaw is 06:00 UTC (summer time, CEST = UTC+2).
      // Verify Morning summary fires at 09:00 *Warsaw*, not 09:00 UTC.
      final scheduler = buildScheduler(now: DateTime(2026, 5, 17, 8, 0));
      await scheduler.reconcile(
        responseFor('2026-05-17'),
        sessionActive: false,
      );
      final snapshot = await service.currentlyScheduled();
      final morning = snapshot[1000]!;
      expect(morning.fireAt.location.name, 'Europe/Warsaw');
      expect(morning.fireAt.hour, 9);
    });
  });

  group('routine occurrences', () {
    test('future occurrence is scheduled with id in 3M+ range', () async {
      final scheduler = buildScheduler(now: DateTime(2026, 5, 17, 8, 0));
      await scheduler.reconcile(
        responseFor('2026-05-17', routineItems: [
          routine('r1', name: 'Take the dog out', startTime: '14:30'),
        ]),
        sessionActive: false,
      );
      final snapshot = await service.currentlyScheduled();
      final routineIds = snapshot.keys.where((id) => id >= 3000000);
      expect(routineIds.length, 1);
      final reminder = snapshot[routineIds.first]!;
      expect(reminder.title, 'Take the dog out');
      expect(reminder.fireAt.hour, 14);
      expect(reminder.fireAt.minute, 30);
      expect(reminder.payload, '/agenda');
    });

    test('past start_time is not scheduled', () async {
      // 15:00 — 14:30 is past
      final scheduler = buildScheduler(now: DateTime(2026, 5, 17, 15, 0));
      await scheduler.reconcile(
        responseFor('2026-05-17', routineItems: [
          routine('r1', name: 'Past routine', startTime: '14:30'),
        ]),
        sessionActive: false,
      );
      final snapshot = await service.currentlyScheduled();
      final routineIds = snapshot.keys.where((id) => id >= 3000000);
      expect(routineIds, isEmpty);
    });

    test('null occurrenceId is not scheduled', () async {
      final scheduler = buildScheduler(now: DateTime(2026, 5, 17, 8, 0));
      await scheduler.reconcile(
        responseFor('2026-05-17', routineItems: [
          routine('r1', name: 'No occurrence', occurrenceId: null),
        ]),
        sessionActive: false,
      );
      final snapshot = await service.currentlyScheduled();
      expect(snapshot.keys.where((id) => id >= 3000000), isEmpty);
    });

    test('null start_time is not scheduled', () async {
      final scheduler = buildScheduler(now: DateTime(2026, 5, 17, 8, 0));
      await scheduler.reconcile(
        responseFor('2026-05-17', routineItems: [
          routine('r1', name: 'No time', startTime: null),
        ]),
        sessionActive: false,
      );
      final snapshot = await service.currentlyScheduled();
      expect(snapshot.keys.where((id) => id >= 3000000), isEmpty);
    });

    test('skipped occurrence is not scheduled', () async {
      final scheduler = buildScheduler(now: DateTime(2026, 5, 17, 8, 0));
      await scheduler.reconcile(
        responseFor('2026-05-17', routineItems: [
          routine('r1',
              name: 'Skipped', status: OccurrenceStatus.skipped),
        ]),
        sessionActive: false,
      );
      final snapshot = await service.currentlyScheduled();
      expect(snapshot.keys.where((id) => id >= 3000000), isEmpty);
    });

    test('done occurrence is not scheduled (already complete)', () async {
      final scheduler = buildScheduler(now: DateTime(2026, 5, 17, 8, 0));
      await scheduler.reconcile(
        responseFor('2026-05-17', routineItems: [
          routine('r1', name: 'Done', status: OccurrenceStatus.done),
        ]),
        sessionActive: false,
      );
      final snapshot = await service.currentlyScheduled();
      expect(snapshot.keys.where((id) => id >= 3000000), isEmpty);
    });
  });

  group('session gating', () {
    test('sessionActive=true → summaries scheduled, occurrences skipped',
        () async {
      final scheduler = buildScheduler(now: DateTime(2026, 5, 17, 8, 0));
      await scheduler.reconcile(
        responseFor('2026-05-17', routineItems: [
          routine('r1', name: 'X', startTime: '14:30'),
          routine('r2',
              name: 'Y', startTime: '16:00', occurrenceId: 'occ-002'),
        ]),
        sessionActive: true,
      );
      final snapshot = await service.currentlyScheduled();
      expect(
        snapshot.keys.where((id) => id < 2000000).toSet(),
        {1000, 1001, 1002, 1003},
      );
      expect(snapshot.keys.where((id) => id >= 3000000), isEmpty);
    });

    test('session edge true→false: occurrences re-added on next reconcile',
        () async {
      final scheduler = buildScheduler(now: DateTime(2026, 5, 17, 8, 0));
      final response = responseFor('2026-05-17', routineItems: [
        routine('r1', name: 'Recovery', startTime: '14:30'),
      ]);
      await scheduler.reconcile(response, sessionActive: true);
      service.calls.clear();
      await scheduler.reconcile(response, sessionActive: false);
      expect(service.scheduleCount, 1); // one routine reminder added
      expect(service.cancelCount, 0);
    });

    test('session edge false→true: occurrences canceled, summaries kept',
        () async {
      final scheduler = buildScheduler(now: DateTime(2026, 5, 17, 8, 0));
      final response = responseFor('2026-05-17', routineItems: [
        routine('r1', name: 'Suppress me', startTime: '14:30'),
      ]);
      await scheduler.reconcile(response, sessionActive: false);
      service.calls.clear();
      await scheduler.reconcile(response, sessionActive: true);
      expect(service.cancelCount, 1);
      expect(service.scheduleCount, 0);
      final snapshot = await service.currentlyScheduled();
      expect(snapshot.keys.where((id) => id >= 3000000), isEmpty);
      // summaries still present
      expect(snapshot.keys, containsAll([1000, 1001, 1002, 1003]));
    });
  });

  group('diff invariants', () {
    test('identical re-run is a no-op', () async {
      final scheduler = buildScheduler(now: DateTime(2026, 5, 17, 8, 0));
      final response = responseFor('2026-05-17', routineItems: [
        routine('r1', name: 'X', startTime: '14:30'),
      ]);
      await scheduler.reconcile(response, sessionActive: false);
      service.calls.clear();
      await scheduler.reconcile(response, sessionActive: false);
      expect(service.scheduleCount, 0);
      expect(service.cancelCount, 0);
    });

    test('removed occurrence is canceled, others untouched', () async {
      final scheduler = buildScheduler(now: DateTime(2026, 5, 17, 8, 0));
      await scheduler.reconcile(
        responseFor('2026-05-17', routineItems: [
          routine('r1',
              name: 'Keep', startTime: '14:30', occurrenceId: 'occ-001'),
          routine('r2',
              name: 'Remove', startTime: '16:00', occurrenceId: 'occ-002'),
        ]),
        sessionActive: false,
      );
      service.calls.clear();
      await scheduler.reconcile(
        responseFor('2026-05-17', routineItems: [
          routine('r1',
              name: 'Keep', startTime: '14:30', occurrenceId: 'occ-001'),
        ]),
        sessionActive: false,
      );
      expect(service.cancelCount, 1);
      expect(service.scheduleCount, 0);
    });

    test('body drift (count change) triggers cancel+reschedule for summary',
        () async {
      final scheduler = buildScheduler(now: DateTime(2026, 5, 17, 8, 0));
      // First call: 1 active item
      await scheduler.reconcile(
        responseFor('2026-05-17', items: [
          actionItem('a1', status: RecordStatus.active),
        ]),
        sessionActive: false,
      );
      service.calls.clear();
      // Second call: 2 active items — summary body changes from "1 open" to "2 open"
      await scheduler.reconcile(
        responseFor('2026-05-17', items: [
          actionItem('a1', status: RecordStatus.active),
          actionItem('a2', status: RecordStatus.active),
        ]),
        sessionActive: false,
      );
      // All 4 summary bodies change. Diff should re-schedule all 4 (plugin's
      // schedule replaces on existing id, so cancel is not strictly needed,
      // but reschedule must happen for each changed body).
      expect(service.scheduleCount, 4);
    });
  });

  group('permission', () {
    test('denied permission short-circuits with zero writes', () async {
      service.permitted = false;
      final scheduler = buildScheduler(now: DateTime(2026, 5, 17, 8, 0));
      await scheduler.reconcile(
        responseFor('2026-05-17', routineItems: [
          routine('r1', name: 'X', startTime: '14:30'),
        ]),
        sessionActive: false,
      );
      expect(service.scheduleCount, 0);
      expect(service.cancelCount, 0);
    });

    test('permission revoked between runs: cancelAll once', () async {
      final scheduler = buildScheduler(now: DateTime(2026, 5, 17, 8, 0));
      await scheduler.reconcile(
        responseFor('2026-05-17', routineItems: [
          routine('r1', name: 'X', startTime: '14:30'),
        ]),
        sessionActive: false,
      );
      service.permitted = false;
      service.calls.clear();
      await scheduler.reconcile(
        responseFor('2026-05-17'),
        sessionActive: false,
      );
      expect(service.calls, contains('cancelAll'));
      final snapshot = await service.currentlyScheduled();
      expect(snapshot, isEmpty);
    });
  });

  group('id stability', () {
    test('same occurrenceId produces same id across runs', () async {
      final scheduler1 = buildScheduler(now: DateTime(2026, 5, 17, 8, 0));
      await scheduler1.reconcile(
        responseFor('2026-05-17', routineItems: [
          routine('r1',
              name: 'X',
              startTime: '14:30',
              occurrenceId: 'stable-uuid-123'),
        ]),
        sessionActive: false,
      );
      final id1 = (await service.currentlyScheduled())
          .keys
          .firstWhere((k) => k >= 3000000);

      final service2 = FakeNotificationService();
      final scheduler2 = AgendaNotificationScheduler(
        service: service2,
        location: warsaw,
        clock: () => DateTime(2026, 5, 17, 8, 0),
      );
      await scheduler2.reconcile(
        responseFor('2026-05-17', routineItems: [
          routine('r1',
              name: 'X',
              startTime: '14:30',
              occurrenceId: 'stable-uuid-123'),
        ]),
        sessionActive: false,
      );
      final id2 = (await service2.currentlyScheduled())
          .keys
          .firstWhere((k) => k >= 3000000);

      expect(id1, id2);
    });

    test('different occurrenceIds produce different ids', () async {
      final scheduler = buildScheduler(now: DateTime(2026, 5, 17, 8, 0));
      await scheduler.reconcile(
        responseFor('2026-05-17', routineItems: [
          routine('r1',
              name: 'X', startTime: '14:30', occurrenceId: 'occ-aaa'),
          routine('r2',
              name: 'Y', startTime: '16:00', occurrenceId: 'occ-bbb'),
        ]),
        sessionActive: false,
      );
      final routineIds = (await service.currentlyScheduled())
          .keys
          .where((id) => id >= 3000000)
          .toSet();
      expect(routineIds.length, 2);
    });

    test('reserved ID ranges respected', () async {
      final scheduler = buildScheduler(now: DateTime(2026, 5, 17, 8, 0));
      await scheduler.reconcile(
        responseFor('2026-05-17', routineItems: [
          routine('r1', name: 'X', startTime: '14:30'),
        ]),
        sessionActive: false,
      );
      final snapshot = await service.currentlyScheduled();
      for (final id in snapshot.keys) {
        // Summaries 1000-1003, action items 2M-2.999M reserved (P041), routines 3M+ (CRC32-derived).
        // No id should fall in 1004-1999999 (gap) or 2000000-2999999 (P041 reserved, not used by T1).
        final isSummary = id >= 1000 && id <= 1003;
        final isRoutine = id >= 3000000;
        expect(
          isSummary || isRoutine,
          isTrue,
          reason: 'id $id outside reserved ranges',
        );
      }
    });
  });
}
