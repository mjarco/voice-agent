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

class RoutineAlreadyTriggedException extends RoutinesException {
  RoutineAlreadyTriggedException(
      [this.message = 'Already triggered for this date']);
  @override
  final String message;
}

class RoutineConflictException extends RoutinesException {
  RoutineConflictException(this.message);
  @override
  final String message;
}

abstract class RoutinesRepository {
  Future<List<Routine>> fetchRoutines(RoutineStatus status);
  Future<Routine> fetchRoutineDetail(String id);
  Future<List<RoutineOccurrence>> fetchOccurrences(String id);
  Future<List<RoutineProposal>> fetchProposals();
  Future<void> activateRoutine(String id);
  Future<void> pauseRoutine(String id);
  Future<void> archiveRoutine(String id);
  Future<void> triggerRoutine(String id, String scheduledFor);
  Future<void> updateOccurrenceStatus(
    String routineId,
    String occurrenceId,
    OccurrenceStatus status,
  );
  Future<void> approveProposal(String proposalId);
  Future<void> rejectProposal(String proposalId);
}
