import 'package:timezone/timezone.dart' as tz;
import 'package:voice_agent/core/models/agenda.dart';
import 'package:voice_agent/core/models/conversation_record.dart';
import 'package:voice_agent/core/models/routine.dart';
import 'package:voice_agent/core/notifications/domain/notification_service.dart';
import 'package:voice_agent/core/observability/telemetry.dart';

/// Pure reconciler — turns an [AgendaResponse] into a desired set of OS
/// notifications and diffs against the [NotificationService] snapshot.
///
/// See ADR-NOTIF-001 for the architectural contract (single writer,
/// in-memory snapshot diff, reserved ID partitioning, session gating,
/// permission revocation handling).
///
/// The reconciler is invoked only with **today's** [AgendaResponse]; the
/// notifier enforces that gate (P040 §Reconciler Triggers). It does not
/// re-verify the date.
class AgendaNotificationScheduler {
  AgendaNotificationScheduler({
    required NotificationService service,
    required tz.Location location,
    required DateTime Function() clock,
  })  : _service = service,
        _location = location,
        _clock = clock;

  final NotificationService _service;
  final tz.Location _location;
  final DateTime Function() _clock;

  /// Tracks the previous permission state to detect revocation
  /// (granted → denied edge triggers cancelAll once, per ADR-NOTIF-001).
  bool? _previouslyPermitted;

  static const String _deepLinkAgenda = '/agenda';
  static const String _summaryTitle = 'Agenda';

  /// Reconcile the OS notification queue against [response].
  ///
  /// [sessionActive] gates routine-occurrence reminders (suppressed while a
  /// hands-free session is running). Summaries are scheduled regardless.
  ///
  /// Emits `agenda.reconcile` span (dev-flavor telemetry per ADR-OBS-001)
  /// with events for permission short-circuit, revocation cancelAll, and
  /// the diff sizes. Counter `agenda.notifications.scheduled` /
  /// `.cancelled` for histogram-friendly aggregation. Stable flavor:
  /// NoopTelemetry — zero cost.
  Future<void> reconcile(
    AgendaResponse response, {
    required bool sessionActive,
  }) async {
    final span = Telemetry.instance.span('agenda.reconcile', attrs: {
      'session_active': sessionActive,
      'response_date': response.date,
      'items_count': response.items.length,
      'routines_count': response.routineItems.length,
    });
    try {
      final permitted = await _service.isPermitted();

      // Revocation edge: if we were permitted before and now we aren't, scrub
      // the OS queue once so it doesn't diverge from our in-memory snapshot.
      if (_previouslyPermitted == true && !permitted) {
        span.addEvent('agenda.reconcile.revocation');
        await _service.cancelAll();
      }
      _previouslyPermitted = permitted;

      if (!permitted) {
        span.addEvent('agenda.reconcile.permission_denied');
        span.end(status: SpanStatus.ok);
        return;
      }

      final now = tz.TZDateTime.from(_clock(), _location);
      final desired = _computeDesired(response, now, sessionActive);
      final current = await _service.currentlyScheduled();

      final desiredIds = desired.map((n) => n.id).toSet();
      final toCancel =
          current.keys.where((id) => !desiredIds.contains(id)).toList();
      final toSchedule = desired
          .where((n) => current[n.id] == null || current[n.id] != n)
          .toList();

      span.addEvent('agenda.reconcile.diff', attrs: {
        'desired': desired.length,
        'current': current.length,
        'to_cancel': toCancel.length,
        'to_schedule': toSchedule.length,
      });

      for (final id in toCancel) {
        await _service.cancel(id);
      }
      for (final n in toSchedule) {
        await _service.schedule(n);
      }

      if (toCancel.isNotEmpty) {
        Telemetry.instance.counter('agenda.notifications.cancelled',
            delta: toCancel.length);
      }
      if (toSchedule.isNotEmpty) {
        Telemetry.instance.counter('agenda.notifications.scheduled',
            delta: toSchedule.length);
      }

      span.end(status: SpanStatus.ok);
    } catch (e) {
      span.end(status: SpanStatus.error, message: e.toString());
      rethrow;
    }
  }

  List<ScheduledNotification> _computeDesired(
    AgendaResponse response,
    tz.TZDateTime now,
    bool sessionActive,
  ) {
    final out = <ScheduledNotification>[];

    // Four daily summaries — always scheduled, even during active session.
    final counts = _SummaryCounts.from(response.items);
    for (final slot in _SummarySlot.values) {
      final fireAt = _nextSlotFireTime(now, slot.hour);
      out.add(ScheduledNotification(
        id: slot.id,
        title: _summaryTitle,
        body: _summaryBody(slot.label, counts),
        fireAt: fireAt,
        payload: _deepLinkAgenda,
      ));
    }

    // Routine occurrences — gated by sessionActive.
    if (!sessionActive) {
      for (final r in response.routineItems) {
        if (r.occurrenceId == null) continue;
        if (r.startTime == null) continue;
        if (r.status == OccurrenceStatus.skipped ||
            r.status == OccurrenceStatus.done) {
          continue;
        }
        final fireAt = _parseRoutineFireTime(r.scheduledFor, r.startTime!);
        if (fireAt == null) continue;
        if (!fireAt.isAfter(now)) continue;
        out.add(ScheduledNotification(
          id: _routineReminderId(r.occurrenceId!),
          title: r.routineName,
          body: r.startTime!,
          fireAt: fireAt,
          payload: _deepLinkAgenda,
        ));
      }
    }
    return out;
  }

  tz.TZDateTime _nextSlotFireTime(tz.TZDateTime now, int slotHour) {
    final today = tz.TZDateTime(_location, now.year, now.month, now.day, slotHour);
    if (today.isAfter(now)) return today;
    return today.add(const Duration(days: 1));
  }

  tz.TZDateTime? _parseRoutineFireTime(String date, String hhmm) {
    // date is YYYY-MM-DD; hhmm is HH:MM.
    final dateParts = date.split('-');
    if (dateParts.length != 3) return null;
    final timeParts = hhmm.split(':');
    if (timeParts.length != 2) return null;
    final year = int.tryParse(dateParts[0]);
    final month = int.tryParse(dateParts[1]);
    final day = int.tryParse(dateParts[2]);
    final hour = int.tryParse(timeParts[0]);
    final minute = int.tryParse(timeParts[1]);
    if (year == null ||
        month == null ||
        day == null ||
        hour == null ||
        minute == null) {
      return null;
    }
    return tz.TZDateTime(_location, year, month, day, hour, minute);
  }

  String _summaryBody(String slotLabel, _SummaryCounts c) {
    if (c.isEmpty) return '$slotLabel: nothing scheduled today';
    final parts = <String>[];
    if (c.open > 0) parts.add('${c.open} open');
    if (c.done > 0) parts.add('${c.done} done');
    if (c.dismissed > 0) parts.add('${c.dismissed} dismissed');
    return '$slotLabel: ${parts.join(', ')}';
  }
}

/// Fixed-time daily summary slots. IDs partitioned 1000–1003 per ADR-NOTIF-001.
enum _SummarySlot {
  morning(id: 1000, label: 'Morning', hour: 9),
  noon(id: 1001, label: 'Noon', hour: 12),
  afternoon(id: 1002, label: 'Afternoon', hour: 15),
  evening(id: 1003, label: 'Evening', hour: 19);

  const _SummarySlot({required this.id, required this.label, required this.hour});
  final int id;
  final String label;
  final int hour;
}

class _SummaryCounts {
  const _SummaryCounts({
    required this.open,
    required this.done,
    required this.dismissed,
  });

  final int open;
  final int done;
  final int dismissed;

  bool get isEmpty => open == 0 && done == 0 && dismissed == 0;

  /// Status mapping (ADR-NOTIF-001 + P040 §Time Resolution):
  ///   open      = active
  ///   done      = done ∪ promoted (promoted is a positive resolution)
  ///   dismissed = superseded
  factory _SummaryCounts.from(List<AgendaItem> items) {
    var open = 0, done = 0, dismissed = 0;
    for (final item in items) {
      switch (item.status) {
        case RecordStatus.active:
          open++;
        case RecordStatus.done:
        case RecordStatus.promoted:
          done++;
        case RecordStatus.superseded:
          dismissed++;
      }
    }
    return _SummaryCounts(open: open, done: done, dismissed: dismissed);
  }
}

/// Routine reminder ID = 3_000_000 + (CRC32(occurrenceId) & 0x7FFFFFFF).
/// Range reserved per ADR-NOTIF-001.
int _routineReminderId(String occurrenceId) {
  return 3000000 + (_crc32(occurrenceId) & 0x7FFFFFFF);
}

/// CRC-32/ISO-HDLC. Standalone implementation to avoid pulling a hash
/// dependency just for this. Stable across runs and platforms.
int _crc32(String input) {
  final bytes = input.codeUnits;
  var crc = 0xFFFFFFFF;
  for (final b in bytes) {
    crc ^= b & 0xFF;
    for (var i = 0; i < 8; i++) {
      if ((crc & 1) != 0) {
        crc = (crc >> 1) ^ 0xEDB88320;
      } else {
        crc = crc >> 1;
      }
    }
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}
