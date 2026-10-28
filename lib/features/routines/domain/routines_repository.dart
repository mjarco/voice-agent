import 'package:voice_agent/core/models/routine.dart';

sealed class RoutinesException implements Exception {
  String get message;

  @override
  String toString() => message;
}

class RoutinesGeneralException extends RoutinesException {
  RoutinesGeneralException(this.message);
  @override
  final String message;
}

class RoutineConflictException extends RoutinesException {
  RoutineConflictException(this.message);
  @override
  final String message;
}

/// `409 overdue_occurrence` of an edit: a waits routine still owes
/// [scheduledFor]; resolve it on [routineId], then edit again (#365).
class RoutineOverdueException extends RoutineConflictException {
  RoutineOverdueException(
    super.message, {
    required this.routineId,
    required this.scheduledFor,
    this.openDays,
  });
  final String routineId;
  final String scheduledFor;

  /// How many days are still owed up to yesterday, [scheduledFor] the
  /// earliest (ADR-API-096 of personal-agent); null from an older server.
  final int? openDays;
}

/// `409 already_resolved`: the occurrence was resolved elsewhere meanwhile.
class RoutineAlreadyResolvedException extends RoutineConflictException {
  RoutineAlreadyResolvedException(super.message);
}

/// `409 routine_already_edited`: another edit replaced this version, so the
/// one to edit is its newer version (#367).
class RoutineAlreadyEditedException extends RoutineConflictException {
  RoutineAlreadyEditedException(super.message);
}

/// `409 routine_not_active`: only an active routine is edited (#369,
/// ADR-API-099 of personal-agent).
class RoutineNotActiveException extends RoutineConflictException {
  RoutineNotActiveException(super.message);
}

/// `422 no_change`: the edit equals the current version (#369).
class RoutineNoChangeException extends RoutinesGeneralException {
  RoutineNoChangeException(super.message);
}

/// The field of the routine form a server refusal is about (#367).
enum RoutineFormField { name, days, interval, monthday, startsOn, lastDay }

/// A refusal of the routine form that names its field: `422
/// invalid_last_day`, `422 invalid_starts_on`, `409 routine_name_exists`.
class RoutineFieldException extends RoutinesException {
  RoutineFieldException(
    this.message, {
    required this.field,
    this.firstDay,
    this.firstDayKnown = false,
  });
  @override
  final String message;
  final RoutineFormField field;

  /// `invalid_last_day`'s first day of the schedule from the start, without
  /// the last day; [firstDayKnown] is false when the server sent no
  /// `first_day` at all (an older server), true with a null [firstDay] when
  /// the schedule has no day.
  final String? firstDay;
  final bool firstDayKnown;
}

/// What the routine form sends to create or edit a routine.
class RoutineInput {
  const RoutineInput({
    required this.name,
    required this.rrule,
    this.startTime,
    this.lastDay,
    required this.missed,
    required this.items,
  });

  final String name;
  final String rrule;
  final String? startTime;
  final String? lastDay;
  final RoutineMissed missed;
  final List<String> items;

  Map<String, dynamic> toMap() => {
        'name': name,
        'rrule': rrule,
        'start_time': startTime,
        'last_day': lastDay,
        'missed': missed.name,
        'items': items,
      };
}

abstract class RoutinesRepository {
  Future<List<Routine>> fetchRoutines(RoutineStatus status);
  Future<Routine> fetchRoutineDetail(String id);
  Future<List<RoutineOccurrence>> fetchOccurrences(String id);
  Future<Routine> createRoutine(RoutineInput input);

  /// Ends [id] the day before [startsOn] and starts its next version that day.
  /// Throws [RoutineOverdueException] when the routine still owes a day.
  Future<Routine> editRoutine(
    String id,
    RoutineInput input, {
    required String startsOn,
  });

  /// Ends [id] after [lastDay], the last day it still occurs.
  Future<void> endRoutine(String id, String lastDay);
  Future<void> resolveOccurrence(
    String routineId,
    String scheduledFor,
    OccurrenceStatus status,
  );
  Future<void> activateRoutine(String id);
  Future<void> pauseRoutine(String id);
  Future<void> archiveRoutine(String id);
  Future<void> updateOccurrenceStatus(
    String routineId,
    String occurrenceId,
    OccurrenceStatus status,
  );
}
