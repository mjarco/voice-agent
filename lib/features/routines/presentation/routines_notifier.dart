import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/features/routines/domain/routines_repository.dart';
import 'package:voice_agent/features/routines/domain/routines_state.dart';

class RoutinesNotifier extends StateNotifier<RoutinesState> {
  RoutinesNotifier(this._repository) : super(const RoutinesInitial()) {
    loadRoutines();
  }

  final RoutinesRepository _repository;
  int _generation = 0;
  String? lastActionError;

  /// Loads every routine; the screen shows them in [RoutineSections].
  Future<void> loadRoutines() async {
    final generation = ++_generation;
    state = const RoutinesLoading();
    lastActionError = null;

    try {
      final routines = await _repository.fetchRoutines();
      // A later load is under way; this answer is stale.
      if (generation != _generation) return;
      state = RoutinesLoaded(routines: routines);
    } catch (e) {
      if (generation != _generation) return;
      state = RoutinesError(message: e.toString());
    }
  }

  Future<void> refresh() => loadRoutines();

  Future<bool> activateRoutine(String id) =>
      _act(() => _repository.activateRoutine(id));

  Future<bool> pauseRoutine(String id) =>
      _act(() => _repository.pauseRoutine(id));

  Future<bool> _act(Future<void> Function() action) async {
    lastActionError = null;
    try {
      await action();
      await loadRoutines();
      return true;
    } on RoutinesException catch (e) {
      lastActionError = e.message;
      return false;
    }
  }
}
