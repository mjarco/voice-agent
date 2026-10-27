import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/core/models/routine.dart';
import 'package:voice_agent/features/routines/domain/routine_form_state.dart';
import 'package:voice_agent/features/routines/domain/routines_repository.dart';

class RoutineFormNotifier extends StateNotifier<RoutineFormState> {
  RoutineFormNotifier(this._repository, this._editId)
      : super(RoutineFormState(loading: _editId != null)) {
    if (_editId != null) load();
  }

  final RoutinesRepository _repository;
  final String? _editId;

  ({RoutineInput input, String? startsOn})? _pending;
  RoutineOverdueException? _overdue;

  bool get isEdit => _editId != null;

  /// Loads the edited routine with its steps; saving waits for them, since
  /// an edit without the steps would replace them.
  Future<void> load() async {
    state = state.copyWith(loading: true, error: () => null);
    try {
      final routine = await _repository.fetchRoutineDetail(_editId!);
      if (!mounted) return;
      state = RoutineFormState(routine: routine);
    } on RoutinesException catch (e) {
      if (!mounted) return;
      state = state.copyWith(
          loading: false, error: () => 'Failed to load the routine: $e');
    }
  }

  /// Creates the routine, or edits it from [startsOn].
  Future<void> save(RoutineInput input, {String? startsOn}) async {
    if (state.saving || state.loading) return;
    _pending = (input: input, startsOn: startsOn);
    await _submit();
  }

  /// Resolves the owed day as [status], then saves the same edit again; a
  /// further owed day asks again.
  Future<void> resolveOverdue(OccurrenceStatus status) async {
    final owed = _overdue;
    if (owed == null || state.saving) return;
    state = state.copyWith(saving: true, error: () => null);
    try {
      await _repository.resolveOccurrence(
          owed.routineId, owed.scheduledFor, status);
    } on RoutinesException catch (e) {
      if (!mounted) return;
      state = state.copyWith(saving: false, error: () => e.message);
      return;
    }
    if (!mounted) return;
    state = state.copyWith(saving: false);
    await _submit();
  }

  void dismissOverdue() {
    _overdue = null;
    state = state.copyWith(overdueDay: () => null);
  }

  Future<void> _submit() async {
    final pending = _pending;
    if (pending == null) return;
    _overdue = null;
    state = state.copyWith(
        saving: true, error: () => null, overdueDay: () => null);
    try {
      final saved = _editId == null
          ? await _repository.createRoutine(pending.input)
          : await _repository.editRoutine(_editId, pending.input,
              startsOn: pending.startsOn!);
      if (!mounted) return;
      state = state.copyWith(saving: false, saved: saved);
    } on RoutineOverdueException catch (e) {
      if (!mounted) return;
      _overdue = e;
      state = state.copyWith(saving: false, overdueDay: () => e.scheduledFor);
    } on RoutinesException catch (e) {
      if (!mounted) return;
      state = state.copyWith(saving: false, error: () => e.message);
    }
  }
}
