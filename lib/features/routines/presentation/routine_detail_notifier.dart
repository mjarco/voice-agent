import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/core/models/routine.dart';
import 'package:voice_agent/features/routines/domain/routine_detail_state.dart';
import 'package:voice_agent/features/routines/domain/routines_repository.dart';

class RoutineDetailNotifier extends StateNotifier<RoutineDetailState> {
  RoutineDetailNotifier(this._repository, this._routineId)
      : super(const RoutineDetailInitial()) {
    loadDetail();
  }

  final RoutinesRepository _repository;
  final String _routineId;
  String? lastActionError;

  Future<void> loadDetail() async {
    state = const RoutineDetailLoading();
    lastActionError = null;

    try {
      final results = await Future.wait([
        _repository.fetchRoutineDetail(_routineId),
        _repository.fetchOccurrences(_routineId),
      ]);
      final routine = results[0] as Routine;
      final occurrences = results[1] as List<RoutineOccurrence>;

      state = RoutineDetailLoaded(routine: routine, occurrences: occurrences);
    } catch (e) {
      state = RoutineDetailError(message: e.toString());
    }
  }

  Future<void> refresh() => loadDetail();

  Future<bool> activateRoutine() async {
    lastActionError = null;
    try {
      await _repository.activateRoutine(_routineId);
      await loadDetail();
      return true;
    } on RoutineConflictException catch (e) {
      lastActionError = e.message;
      return false;
    } on RoutinesException catch (e) {
      lastActionError = e.message;
      return false;
    }
  }

  Future<bool> pauseRoutine() async {
    lastActionError = null;
    try {
      await _repository.pauseRoutine(_routineId);
      await loadDetail();
      return true;
    } on RoutinesException catch (e) {
      lastActionError = e.message;
      return false;
    }
  }

  Future<bool> archiveRoutine() async {
    lastActionError = null;
    try {
      await _repository.archiveRoutine(_routineId);
      await loadDetail();
      return true;
    } on RoutineConflictException catch (e) {
      lastActionError = e.message;
      return false;
    } on RoutinesException catch (e) {
      lastActionError = e.message;
      return false;
    }
  }

  Future<bool> triggerRoutine(String scheduledFor) async {
    lastActionError = null;
    try {
      await _repository.triggerRoutine(_routineId, scheduledFor);
      await loadDetail();
      return true;
    } on RoutineAlreadyTriggedException catch (e) {
      lastActionError = e.message;
      return false;
    } on RoutinesException catch (e) {
      lastActionError = e.message;
      return false;
    }
  }

  Future<bool> updateOccurrenceStatus(
    String occurrenceId,
    OccurrenceStatus status,
  ) async {
    lastActionError = null;
    try {
      await _repository.updateOccurrenceStatus(
          _routineId, occurrenceId, status);
      await loadDetail();
      return true;
    } on RoutinesException catch (e) {
      lastActionError = e.message;
      return false;
    }
  }
}
