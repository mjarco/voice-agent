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

  Future<bool> activateRoutine() =>
      _act(() => _repository.activateRoutine(_routineId));

  Future<bool> pauseRoutine() =>
      _act(() => _repository.pauseRoutine(_routineId));

  Future<bool> archiveRoutine() =>
      _act(() => _repository.archiveRoutine(_routineId));

  /// Ends a recurring routine after [lastDay], the last day it still occurs:
  /// a PATCH of `last_day`.
  Future<bool> endRoutine(String lastDay) => _act(() =>
      _repository.editRoutine(_routineId, RoutinePatch.endAfter(lastDay)));

  /// Ticks off a one-off or someday routine (its due day or today).
  Future<bool> resolve(OccurrenceStatus status) =>
      _act(() => _repository.resolve(_routineId, status));

  /// Undoes [occurrence]: a recurring routine's tick of its day, any other's
  /// only tick.
  Future<bool> undo(RoutineOccurrence occurrence) {
    final loaded = state;
    final recurring =
        loaded is RoutineDetailLoaded && loaded.routine.isRecurring;
    return _act(() => _repository.unresolve(_routineId,
        scheduledFor: recurring ? occurrence.scheduledFor : null));
  }

  Future<bool> _act(Future<void> Function() action) async {
    lastActionError = null;
    try {
      await action();
      await loadDetail();
      return true;
    } on RoutinesException catch (e) {
      lastActionError = e.message;
      return false;
    }
  }
}
