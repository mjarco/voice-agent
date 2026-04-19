import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/core/models/routine.dart';
import 'package:voice_agent/features/routines/domain/routines_repository.dart';
import 'package:voice_agent/features/routines/domain/routines_state.dart';

class RoutinesNotifier extends StateNotifier<RoutinesState> {
  RoutinesNotifier(this._repository) : super(const RoutinesInitial()) {
    _selectedStatus = RoutineStatus.active;
    loadRoutines();
  }

  final RoutinesRepository _repository;
  late RoutineStatus _selectedStatus;
  List<RoutineProposal> _cachedProposals = [];
  String? lastActionError;

  RoutineStatus get selectedStatus => _selectedStatus;

  Future<void> loadRoutines() async {
    state = const RoutinesLoading();
    lastActionError = null;

    try {
      final proposalsFuture = _repository
          .fetchProposals()
          .then((v) => v)
          .catchError((_) => <RoutineProposal>[]);
      final routinesFuture = _repository.fetchRoutines(_selectedStatus);

      final results = await Future.wait([routinesFuture, proposalsFuture]);
      final routines = results[0] as List<Routine>;
      final proposals = results[1] as List<RoutineProposal>;
      _cachedProposals = proposals;

      state = RoutinesLoaded(routines: routines, proposals: proposals);
    } catch (e) {
      state = RoutinesError(message: e.toString());
    }
  }

  Future<void> selectStatus(RoutineStatus status) async {
    _selectedStatus = status;
    state = const RoutinesLoading();

    try {
      final routines = await _repository.fetchRoutines(status);
      state = RoutinesLoaded(routines: routines, proposals: _cachedProposals);
    } catch (e) {
      state = RoutinesError(message: e.toString());
    }
  }

  Future<void> refresh() => loadRoutines();

  Future<bool> triggerRoutine(String id, String scheduledFor) async {
    lastActionError = null;
    try {
      await _repository.triggerRoutine(id, scheduledFor);
      await _reloadCurrentTab();
      return true;
    } on RoutineAlreadyTriggedException catch (e) {
      lastActionError = e.message;
      return false;
    } on RoutinesException catch (e) {
      lastActionError = e.message;
      return false;
    }
  }

  Future<bool> pauseRoutine(String id) async {
    lastActionError = null;
    try {
      await _repository.pauseRoutine(id);
      await _reloadCurrentTab();
      return true;
    } on RoutinesException catch (e) {
      lastActionError = e.message;
      return false;
    }
  }

  Future<bool> approveProposal(String proposalId) async {
    lastActionError = null;
    try {
      await _repository.approveProposal(proposalId);
      await loadRoutines();
      return true;
    } on RoutinesException catch (e) {
      lastActionError = e.message;
      return false;
    }
  }

  Future<bool> rejectProposal(String proposalId) async {
    lastActionError = null;
    try {
      await _repository.rejectProposal(proposalId);
      await loadRoutines();
      return true;
    } on RoutinesException catch (e) {
      lastActionError = e.message;
      return false;
    }
  }

  Future<void> _reloadCurrentTab() async {
    try {
      final routines = await _repository.fetchRoutines(_selectedStatus);
      state = RoutinesLoaded(routines: routines, proposals: _cachedProposals);
    } catch (e) {
      state = RoutinesError(message: e.toString());
    }
  }
}
