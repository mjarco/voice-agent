import 'package:voice_agent/core/models/routine.dart';
import 'package:voice_agent/features/routines/domain/routine_input.dart';
import 'package:voice_agent/features/routines/domain/routine_patch.dart';

export 'package:voice_agent/features/routines/domain/routine_input.dart';
export 'package:voice_agent/features/routines/domain/routine_patch.dart';

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

/// `409 overdue_occurrence` of an edit: a recurring waits routine still owes
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

/// `409 already_resolved`: the day was ticked off elsewhere meanwhile.
class RoutineAlreadyResolvedException extends RoutineConflictException {
  RoutineAlreadyResolvedException(super.message);
}

/// `409 routine_not_active`: only an active routine is ticked off.
class RoutineNotActiveException extends RoutineConflictException {
  RoutineNotActiveException(super.message);
}

/// `409 name_taken`: an edit renames the routine to the name of another
/// live routine.
class RoutineNameTakenException extends RoutineConflictException {
  RoutineNameTakenException(super.message);
}

/// `422 invalid_rrule`: the rule does not parse or, with its last day, has
/// no day left.
class RoutineInvalidRRuleException extends RoutinesGeneralException {
  RoutineInvalidRRuleException(super.message);
}

/// The field of the routine form a refusal is about (#367).
enum RoutineFormField { name, schedule, days, interval, monthday, dueOn, lastDay }

abstract class RoutinesRepository {
  /// Every routine, archived and ended ones too (`status=all`).
  Future<List<Routine>> fetchRoutines();
  Future<Routine> fetchRoutineDetail(String id);

  /// The routine's ticks, newest first.
  Future<List<RoutineOccurrence>> fetchOccurrences(String id);

  /// Creates the routine; a live routine of the same name comes back with
  /// [Routine.existing] set and nothing is written.
  Future<Routine> createRoutine(RoutineInput input);

  /// Changes the fields [patch] sets. Throws [RoutineOverdueException] when
  /// a recurring waits routine still owes a day and the schedule changes.
  Future<Routine> editRoutine(String id, RoutinePatch patch);

  /// Ticks off (done or skipped) the routine: a recurring one on
  /// [scheduledFor], a one-off on its due day, a someday one today.
  Future<void> resolve(
    String routineId,
    OccurrenceStatus status, {
    String? scheduledFor,
  });

  /// Undoes a tick: a recurring routine's of [scheduledFor], any other's
  /// only tick.
  Future<void> unresolve(String routineId, {String? scheduledFor});

  Future<void> activateRoutine(String id);
  Future<void> pauseRoutine(String id);
  Future<void> archiveRoutine(String id);
}
