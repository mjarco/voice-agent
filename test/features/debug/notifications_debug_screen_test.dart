// Smoke tests for the P040 test-infra debug screen.
// We are NOT exhaustively testing UI shapes; only the contract that
// matters for the manual test runner:
//   - the snapshot is read from `notificationServiceProvider`
//   - "Fire in 2s" cancels + re-schedules the entry near-now

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'package:voice_agent/core/notifications/domain/notification_service.dart';
import 'package:voice_agent/core/notifications/notification_providers.dart';
import 'package:voice_agent/features/debug/notifications_debug_screen.dart';

class _FakeNotificationService implements NotificationService {
  final Map<int, ScheduledNotification> _snapshot = {};
  final List<String> calls = [];

  void seed(ScheduledNotification n) => _snapshot[n.id] = n;

  @override
  Future<void> init() async {}
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<bool> isPermitted() async => true;
  @override
  Future<void> schedule(ScheduledNotification n) async {
    calls.add('schedule(${n.id}, fireAt=${n.fireAt})');
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
}

void main() {
  setUpAll(() => tz_data.initializeTimeZones());

  Widget wrap(_FakeNotificationService service) {
    return ProviderScope(
      overrides: [
        notificationServiceProvider.overrideWithValue(service),
      ],
      child: const MaterialApp(home: NotificationsDebugScreen()),
    );
  }

  testWidgets('renders empty-state message when no notifications scheduled',
      (tester) async {
    final service = _FakeNotificationService();
    await tester.pumpWidget(wrap(service));
    await tester.pumpAndSettle();

    expect(find.textContaining('No notifications scheduled'), findsOneWidget);
  });

  testWidgets('renders one tile per scheduled notification', (tester) async {
    final service = _FakeNotificationService()
      ..seed(ScheduledNotification(
        id: 1000,
        title: 'Agenda',
        body: 'Morning: 2 open',
        fireAt: tz.TZDateTime.now(tz.local).add(const Duration(hours: 1)),
        payload: '/agenda',
      ))
      ..seed(ScheduledNotification(
        id: 3000123,
        title: 'Routine X',
        body: '14:30',
        fireAt: tz.TZDateTime.now(tz.local).add(const Duration(minutes: 30)),
        payload: '/agenda',
      ));

    await tester.pumpWidget(wrap(service));
    await tester.pumpAndSettle();

    expect(find.text('Agenda'), findsOneWidget);
    expect(find.text('Routine X'), findsOneWidget);
    expect(find.textContaining('id=1000'), findsOneWidget);
    expect(find.textContaining('id=3000123'), findsOneWidget);
  });

  testWidgets('"Fire in 2s" cancels + re-schedules with near-now fireAt',
      (tester) async {
    final service = _FakeNotificationService()
      ..seed(ScheduledNotification(
        id: 1000,
        title: 'Agenda',
        body: 'Morning: 2 open',
        fireAt: tz.TZDateTime.now(tz.local).add(const Duration(hours: 5)),
        payload: '/agenda',
      ));
    await tester.pumpWidget(wrap(service));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('debug-fire-now-1000')));
    await tester.pumpAndSettle();

    // Cancel + schedule sequence recorded on the fake.
    expect(service.calls.first, 'cancel(1000)');
    expect(service.calls[1], startsWith('schedule(1000'));

    // The re-scheduled fireAt is close to now.
    final scheduled = (await service.currentlyScheduled())[1000]!;
    final delta = scheduled.fireAt
        .difference(tz.TZDateTime.now(tz.local))
        .inSeconds;
    expect(delta, lessThan(10),
        reason: 'fire-now action should reschedule within ~2 s');
  });

  testWidgets('refresh button re-reads the snapshot', (tester) async {
    final service = _FakeNotificationService();
    await tester.pumpWidget(wrap(service));
    await tester.pumpAndSettle();
    expect(find.textContaining('No notifications scheduled'), findsOneWidget);

    // Seed the fake AFTER the initial read.
    service.seed(ScheduledNotification(
      id: 1000,
      title: 'After-refresh entry',
      body: 'body',
      fireAt: tz.TZDateTime.now(tz.local).add(const Duration(hours: 1)),
      payload: '/agenda',
    ));

    await tester.tap(find.byKey(const Key('debug-notifications-refresh')));
    await tester.pumpAndSettle();

    expect(find.text('After-refresh entry'), findsOneWidget);
  });
}
