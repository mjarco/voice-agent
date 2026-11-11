import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'package:voice_agent/core/models/agenda.dart';
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
    List<AgendaRoutineItem> routineItems = const [],
  }) =>
      AgendaResponse(
        date: date,
        granularity: 'day',
        from: '${date}T00:00:00Z',
        to: '${date}T23:59:59Z',
        routineItems: routineItems,
      );

  AgendaRoutineItem routine(
    String routineId, {
    required String name,
    String scheduledFor = '2026-05-17',
    String? startTime = '14:30',
    bool overdue = false,
    RoutineKind kind = RoutineKind.recurring,
  }) =>
      AgendaRoutineItem(
        routineId: routineId,
        routineName: name,
        kind: kind,
        scheduledFor: scheduledFor,
        dueWindow: kind == RoutineKind.oneOff ? TimeWindow.week : null,
        startTime: startTime,
        overdue: overdue,
      );

  group('no daily summaries (off-roadmap 2026-11-11-va-polish)', () {
    test('an empty agenda schedules nothing', () async {
      final scheduler = buildScheduler(now: DateTime(2026, 5, 17, 8, 0));
      await scheduler.reconcile(
        responseFor('2026-05-17'),
        sessionActive: false,
      );
      expect(service.scheduleCount, 0);
      expect(await service.currentlyScheduled(), isEmpty);
    });

    test('the summaries an older build queued are cancelled once', () async {
      final scheduler = buildScheduler(now: DateTime(2026, 5, 17, 8, 0));
      await scheduler.reconcile(
        responseFor('2026-05-17'),
        sessionActive: false,
      );
      expect(
        service.calls.where((c) => c.startsWith('cancel(')).toList(),
        ['cancel(1000)', 'cancel(1001)', 'cancel(1002)', 'cancel(1003)'],
      );
      service.calls.clear();
      await scheduler.reconcile(
        responseFor('2026-05-17'),
        sessionActive: false,
      );
      expect(service.cancelCount, 0);
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

    test('a one-off with an hour gets a reminder on its due day', () async {
      final scheduler = buildScheduler(now: DateTime(2026, 5, 17, 8, 0));
      await scheduler.reconcile(
        responseFor('2026-05-17', routineItems: [
          routine('t1', name: 'Call the plumber', kind: RoutineKind.oneOff),
        ]),
        sessionActive: false,
      );
      final snapshot = await service.currentlyScheduled();
      final routineIds = snapshot.keys.where((id) => id >= 3000000);
      expect(routineIds.length, 1);
      expect(snapshot[routineIds.first]!.title, 'Call the plumber');
    });

    test('same routine on two days gets two reminders', () async {
      final scheduler = buildScheduler(now: DateTime(2026, 5, 17, 8, 0));
      await scheduler.reconcile(
        responseFor('2026-05-17', routineItems: [
          routine('r1', name: 'Today', scheduledFor: '2026-05-17'),
          routine('r1', name: 'Tomorrow', scheduledFor: '2026-05-18'),
        ]),
        sessionActive: false,
      );
      final snapshot = await service.currentlyScheduled();
      expect(snapshot.keys.where((id) => id >= 3000000).length, 2);
    });

    test('reminder ids stay within the 32-bit notification id range', () {
      for (final hash in [0, 1, 0x7FFFFFFF, 0x80000000, 0xFFFFFFFF]) {
        final id = routineReminderIdFromHash(hash);
        expect(id, inInclusiveRange(3000000, 0x7FFFFFFF), reason: '$hash');
      }
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
  });

  group('session gating', () {
    test('sessionActive=true → occurrences skipped', () async {
      final scheduler = buildScheduler(now: DateTime(2026, 5, 17, 8, 0));
      await scheduler.reconcile(
        responseFor('2026-05-17', routineItems: [
          routine('r1', name: 'X', startTime: '14:30'),
          routine('r2', name: 'Y', startTime: '16:00'),
        ]),
        sessionActive: true,
      );
      final snapshot = await service.currentlyScheduled();
      expect(snapshot, isEmpty);
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

    test('session edge false→true: occurrences canceled', () async {
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
      expect(snapshot, isEmpty);
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
          routine('r1', name: 'Keep', startTime: '14:30'),
          routine('r2', name: 'Remove', startTime: '16:00'),
        ]),
        sessionActive: false,
      );
      service.calls.clear();
      await scheduler.reconcile(
        responseFor('2026-05-17', routineItems: [
          routine('r1', name: 'Keep', startTime: '14:30'),
        ]),
        sessionActive: false,
      );
      expect(service.cancelCount, 1);
      // The kept reminder is not rescheduled.
      expect(service.scheduleCount, 0);
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
    test('same routine and day produce the same id across runs', () async {
      final scheduler1 = buildScheduler(now: DateTime(2026, 5, 17, 8, 0));
      await scheduler1.reconcile(
        responseFor('2026-05-17', routineItems: [
          routine('r1', name: 'X', startTime: '14:30'),
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
          routine('r1', name: 'X', startTime: '14:30'),
        ]),
        sessionActive: false,
      );
      final id2 = (await service2.currentlyScheduled())
          .keys
          .firstWhere((k) => k >= 3000000);

      expect(id1, id2);
    });

    test('different routines produce different ids', () async {
      final scheduler = buildScheduler(now: DateTime(2026, 5, 17, 8, 0));
      await scheduler.reconcile(
        responseFor('2026-05-17', routineItems: [
          routine('r1', name: 'X', startTime: '14:30'),
          routine('r2', name: 'Y', startTime: '16:00'),
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
