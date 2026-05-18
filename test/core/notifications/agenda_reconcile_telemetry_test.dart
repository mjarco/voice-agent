// Verifies the dev-flavor telemetry instrumentation added in the P040
// test-infra slice. On the stable flavor `Telemetry.instance` is a
// `NoopTelemetry` and these emissions cost nothing; here we override
// the singleton with a recording impl and assert on the call shape.
//
// Mirrors the pattern from `test/features/recording/data/hands_free_telemetry_test.dart`.

import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'package:voice_agent/core/models/agenda.dart';
import 'package:voice_agent/core/notifications/agenda_notification_scheduler.dart';
import 'package:voice_agent/core/notifications/domain/notification_service.dart';
import 'package:voice_agent/core/observability/telemetry.dart';

class _FakeNotificationService implements NotificationService {
  final Map<int, ScheduledNotification> _snapshot = {};
  bool permitted = true;

  @override
  Future<void> init() async {}
  @override
  Future<bool> requestPermission() async => permitted;
  @override
  Future<bool> isPermitted() async => permitted;
  @override
  Future<void> schedule(ScheduledNotification n) async => _snapshot[n.id] = n;
  @override
  Future<void> cancel(int id) async => _snapshot.remove(id);
  @override
  Future<Map<int, ScheduledNotification>> currentlyScheduled() async =>
      Map.unmodifiable(_snapshot);
  @override
  Future<void> cancelAll() async => _snapshot.clear();
}

void main() {
  late _RecordingTelemetry recording;
  late tz.Location warsaw;
  late _FakeNotificationService service;
  late AgendaNotificationScheduler scheduler;

  setUpAll(() {
    tz_data.initializeTimeZones();
    warsaw = tz.getLocation('Europe/Warsaw');
  });

  setUp(() {
    recording = _RecordingTelemetry();
    Telemetry.instance = recording;
    service = _FakeNotificationService();
    scheduler = AgendaNotificationScheduler(
      service: service,
      location: warsaw,
      clock: () => DateTime(2026, 5, 18, 8, 0),
    );
  });

  tearDown(() {
    Telemetry.instance = const NoopTelemetry();
  });

  AgendaResponse emptyResponse() => AgendaResponse(
        date: '2026-05-18',
        granularity: 'day',
        from: '2026-05-18T00:00:00Z',
        to: '2026-05-18T23:59:59Z',
        items: const [],
        routineItems: const [],
      );

  test('reconcile opens agenda.reconcile span with response context attrs',
      () async {
    await scheduler.reconcile(emptyResponse(), sessionActive: false);

    final spans = recording.spans.where((s) => s.name == 'agenda.reconcile');
    expect(spans, hasLength(1));
    final span = spans.single;
    expect(span.attrs['session_active'], false);
    expect(span.attrs['response_date'], '2026-05-18');
    expect(span.attrs['items_count'], 0);
    expect(span.attrs['routines_count'], 0);
    expect(span.endedStatus, SpanStatus.ok);
  });

  test('reconcile emits agenda.reconcile.diff event with diff sizes',
      () async {
    await scheduler.reconcile(emptyResponse(), sessionActive: false);

    final span = recording.spans.single;
    final diffEvents =
        span.events.where((e) => e.name == 'agenda.reconcile.diff');
    expect(diffEvents, hasLength(1));
    final diff = diffEvents.single;
    // Empty response → 4 summaries scheduled, 0 to cancel.
    expect(diff.attrs['desired'], 4);
    expect(diff.attrs['current'], 0);
    expect(diff.attrs['to_cancel'], 0);
    expect(diff.attrs['to_schedule'], 4);
  });

  test(
      'reconcile increments agenda.notifications.scheduled counter on first run',
      () async {
    await scheduler.reconcile(emptyResponse(), sessionActive: false);

    final scheduled = recording.counters
        .where((c) => c.name == 'agenda.notifications.scheduled');
    expect(scheduled, hasLength(1));
    expect(scheduled.single.delta, 4);

    final cancelled = recording.counters
        .where((c) => c.name == 'agenda.notifications.cancelled');
    expect(cancelled, isEmpty,
        reason: 'first run has nothing to cancel — counter is zero-skipped');
  });

  test(
      'reconcile re-run with identical input emits diff event with 0/0/0 deltas',
      () async {
    await scheduler.reconcile(emptyResponse(), sessionActive: false);
    recording.spans.clear();
    recording.counters.clear();

    await scheduler.reconcile(emptyResponse(), sessionActive: false);

    final span = recording.spans.single;
    final diff = span.events.firstWhere((e) => e.name == 'agenda.reconcile.diff');
    expect(diff.attrs['to_cancel'], 0);
    expect(diff.attrs['to_schedule'], 0);
    expect(recording.counters, isEmpty,
        reason: 'idempotent run emits no counter ticks');
  });

  test('reconcile emits permission_denied event when service is unpermitted',
      () async {
    service.permitted = false;
    await scheduler.reconcile(emptyResponse(), sessionActive: false);

    final span = recording.spans.single;
    expect(
      span.events.where((e) => e.name == 'agenda.reconcile.permission_denied'),
      hasLength(1),
    );
    expect(span.endedStatus, SpanStatus.ok);
  });

  test(
      'reconcile emits revocation event on false-after-true permission edge',
      () async {
    // First run primes _previouslyPermitted = true.
    await scheduler.reconcile(emptyResponse(), sessionActive: false);
    service.permitted = false;
    recording.spans.clear();

    await scheduler.reconcile(emptyResponse(), sessionActive: false);

    final span = recording.spans.single;
    expect(
      span.events.where((e) => e.name == 'agenda.reconcile.revocation'),
      hasLength(1),
    );
  });
}

// ─── Recording telemetry helpers (same pattern as
//     test/features/recording/data/hands_free_telemetry_test.dart) ───

class _RecordingTelemetry implements Telemetry {
  final List<_RecEvent> events = [];
  final List<_RecCounter> counters = [];
  final List<_RecSpan> spans = [];

  @override
  void event(String name, {Map<String, Object?> attrs = const {}}) {
    events.add(_RecEvent(name, Map.unmodifiable(attrs)));
  }

  @override
  TelemetrySpan span(String name,
      {SpanKind kind = SpanKind.internal,
      Map<String, Object?> attrs = const {}}) {
    final s = _RecSpan(name, Map.unmodifiable(attrs));
    spans.add(s);
    return s;
  }

  @override
  void counter(String name,
      {int delta = 1, Map<String, Object?> attrs = const {}}) {
    counters.add(_RecCounter(name, delta, Map.unmodifiable(attrs)));
  }

  @override
  void histogram(String name, num value,
      {Map<String, Object?> attrs = const {}}) {}

  @override
  Future<void> flush() async {}
}

class _RecEvent {
  _RecEvent(this.name, this.attrs);
  final String name;
  final Map<String, Object?> attrs;
}

class _RecCounter {
  _RecCounter(this.name, this.delta, this.attrs);
  final String name;
  final int delta;
  final Map<String, Object?> attrs;
}

class _RecSpan implements TelemetrySpan {
  _RecSpan(this.name, this.attrs);
  final String name;
  final Map<String, Object?> attrs;
  final List<_RecEvent> events = [];
  SpanStatus? endedStatus;
  String? endedMessage;

  @override
  void setAttr(String key, Object? value) {}

  @override
  void addEvent(String name, {Map<String, Object?> attrs = const {}}) {
    events.add(_RecEvent(name, Map.unmodifiable(attrs)));
  }

  @override
  void end({SpanStatus status = SpanStatus.unset, String? message}) {
    if (endedStatus != null) return;
    endedStatus = status;
    endedMessage = message;
  }
}
