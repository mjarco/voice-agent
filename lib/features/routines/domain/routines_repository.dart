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
  });
  final String routineId;
  final String scheduledFor;
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
