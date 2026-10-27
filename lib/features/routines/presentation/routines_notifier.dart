import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/core/models/routine.dart';
import 'package:voice_agent/features/routines/domain/routines_repository.dart';
import 'package:voice_agent/features/routines/domain/routines_state.dart';

class RoutinesNotifier extends StateNotifier<RoutinesState> {
  RoutinesNotifier(this._repository) : super(const RoutinesInitial()) {
    loadRoutines();
  }

  final RoutinesRepository _repository;
  RoutinesTab _selectedTab = RoutinesTab.active;
  int _generation = 0;
  String? lastActionError;

  RoutinesTab get selectedTab => _selectedTab;

  Future<void> loadRoutines() async {
    final generation = ++_generation;
    final tab = _selectedTab;
    state = const RoutinesLoading();
    lastActionError = null;

    try {
      final routines = await _fetchTab(tab);
      // A tab switched meanwhile has its own load; this answer is stale.
      if (generation != _generation) return;
      state = RoutinesLoaded(routines: routines);
    } catch (e) {
      if (generation != _generation) return;
      state = RoutinesError(message: e.toString());
    }
  }

  Future<void> selectTab(RoutinesTab tab) {
    _selectedTab = tab;
    return loadRoutines();
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

  /// The routines of [tab]. Active and Paused leave out ended routines;
  /// Ended lists ended and archived ones, without the versions an edit
  /// replaced (the newer version links to them).
  Future<List<Routine>> _fetchTab(RoutinesTab tab) async {
    switch (tab) {
      case RoutinesTab.active:
        final lists = await Future.wait([
          _repository.fetchRoutines(RoutineStatus.active),
          _repository.fetchRoutines(RoutineStatus.draft),
        ]);
        return lists.expand((l) => l).where((r) => !r.ended).toList();
      case RoutinesTab.paused:
        final paused = await _repository.fetchRoutines(RoutineStatus.paused);
        return paused.where((r) => !r.ended).toList();
      case RoutinesTab.ended:
        final lists = await Future.wait(
            RoutineStatus.values.map(_repository.fetchRoutines));
        return lists
            .expand((l) => l)
            .where((r) => r.ended || r.status == RoutineStatus.archived)
            .where((r) => r.nextRoutineId == null)
            .toList();
    }
  }
}
