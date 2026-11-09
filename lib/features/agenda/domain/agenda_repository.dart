import 'package:voice_agent/core/models/agenda.dart';
import 'package:voice_agent/core/models/routine.dart';

class AgendaException implements Exception {
  AgendaException(this.message, {this.statusCode, this.code});
  final String message;

  /// The HTTP status of a refusal by the server; null for any other failure.
  final int? statusCode;

  /// The `error.code` of the server's refusal (`already_resolved`,
  /// `routine_not_active`, …); null when it sent none.
  final String? code;

  @override
  String toString() => message;
}

class CachedAgenda {
  const CachedAgenda({required this.response, required this.fetchedAt});
  final AgendaResponse response;
  final DateTime fetchedAt;
}

abstract class AgendaRepository {
  Future<AgendaResponse> fetchAgenda(String date);
  Future<CachedAgenda?> getCachedAgenda(String date);
  Future<void> cacheAgenda(String date, AgendaResponse response);

  /// Asks personal-agent to read the calendars now, whatever their poll
  /// schedule: `POST /calendar/refresh` (ADR-API-102, #375).
  Future<void> refreshCalendars();

  /// Ticks off (done or skipped) the routine: `POST /routines/{id}/resolve`.
  /// [scheduledFor] names a recurring routine's day; a one-off is ticked on
  /// its due day without it.
  Future<void> resolveOccurrence(
    String routineId,
    OccurrenceStatus status, {
    String? scheduledFor,
  });

  /// Undoes a tick: `DELETE /routines/{id}/resolve`, with a recurring
  /// routine's day.
  Future<void> unresolveOccurrence(String routineId, {String? scheduledFor});
}
