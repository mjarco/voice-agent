import 'package:voice_agent/core/models/agenda.dart';
import 'package:voice_agent/core/models/routine.dart';

class AgendaException implements Exception {
  AgendaException(this.message, {this.statusCode});
  final String message;

  /// The HTTP status of a refusal by the server; null for any other failure.
  final int? statusCode;

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
  Future<void> markActionItemDone(String recordId);

  /// Asks personal-agent to read the calendars now, whatever their poll
  /// schedule: `POST /calendar/refresh` (ADR-API-102, #375).
  Future<void> refreshCalendars();

  /// Ticks off (done or skipped) the routine's occurrence of [scheduledFor],
  /// with or without a stored row: `POST /routines/{id}/resolve` (#363).
  Future<void> resolveOccurrence(
    String routineId,
    String scheduledFor,
    OccurrenceStatus status,
  );
}
