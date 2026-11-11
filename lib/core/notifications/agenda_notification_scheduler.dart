import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:timezone/timezone.dart' as tz;
import 'package:voice_agent/core/models/agenda.dart';
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

  /// Whether this process already cancelled the [_retiredSummaryIds].
  bool _retiredCancelled = false;

  static const String _deepLinkAgenda = '/agenda';

  /// The four daily summaries (9, 12, 15, 19) were removed for now on the
  /// owner's word (off-roadmap 2026-11-11-va-polish). The snapshot is in
  /// memory, so the ones an older build queued are cancelled by id once per
  /// process; the ids stay reserved (ADR-NOTIF-001).
  static const List<int> _retiredSummaryIds = [1000, 1001, 1002, 1003];

  /// Reconcile the OS notification queue against [response].
  ///
  /// [sessionActive] gates routine-occurrence reminders (suppressed while a
  /// hands-free session is running).
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

      if (!_retiredCancelled) {
        for (final id in _retiredSummaryIds) {
          await _service.cancel(id);
        }
        _retiredCancelled = true;
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

    // Routine occurrences — gated by sessionActive.
    if (!sessionActive) {
      for (final r in response.routineItems) {
        if (r.startTime == null) continue;
        final fireAt = _parseRoutineFireTime(r.scheduledFor, r.startTime!);
        if (fireAt == null) continue;
        if (!fireAt.isAfter(now)) continue;
        out.add(ScheduledNotification(
          id: _routineReminderId(r.routineId, r.scheduledFor),
          title: r.routineName,
          body: r.startTime!,
          fireAt: fireAt,
          payload: _deepLinkAgenda,
        ));
      }
    }
    return out;
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
}

/// Routine reminder ID, keyed by routine and day (ADR-NOTIF-002): PA returns
/// `occurrence_id: null` until an occurrence is acted on, so the occurrence id
/// cannot be the key.
int _routineReminderId(String routineId, String scheduledFor) {
  return routineReminderIdFromHash(_crc32('$routineId@$scheduledFor'));
}

/// Maps a CRC-32 into `3_000_000..0x7FFFFFFF`: the reserved range
/// (ADR-NOTIF-001) capped at the 32-bit limit that `flutter_local_notifications`
/// enforces (ADR-NOTIF-002).
@visibleForTesting
int routineReminderIdFromHash(int hash) {
  const base = 3000000;
  const maxId = 0x7FFFFFFF;
  return base + hash % (maxId - base + 1);
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
