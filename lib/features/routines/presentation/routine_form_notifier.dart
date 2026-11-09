import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/core/models/routine.dart';
import 'package:voice_agent/features/routines/domain/routine_form_state.dart';
import 'package:voice_agent/features/routines/domain/routine_schedule.dart';
import 'package:voice_agent/features/routines/domain/routines_repository.dart';

class RoutineFormNotifier extends StateNotifier<RoutineFormState> {
  RoutineFormNotifier(this._repository, this._editId,
      {DateTime Function() clock = DateTime.now})
      : _clock = clock,
        super(RoutineFormState(loading: _editId != null)) {
    if (_editId != null) load();
  }

  final RoutinesRepository _repository;
  final String? _editId;
  final DateTime Function() _clock;

  RoutineInput? _pendingInput;
  RoutinePatch? _pendingPatch;
  RoutineOverdueException? _overdue;

  bool get isEdit => _editId != null;

  /// Loads the edited routine with its steps; saving waits for them, since
  /// the edit sends what differs from them.
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

  /// Creates the routine, or edits it with what [input] changes.
  Future<void> save(RoutineInput input) async {
    if (state.saving || state.loading) return;
    _pendingInput = input;
    _pendingPatch = null;
    final old = state.routine;
    if (isEdit && old != null) {
      final patch = RoutinePatch.between(old, input, today: _today());
      if (patch.isEmpty) {
        state = state.copyWith(
            error: () => 'Nothing changed.', errorField: () => null);
        return;
      }
      _pendingPatch = patch;
    }
    await _submit();
  }

  /// Resolves the owed day as [status], then saves the same edit again; a
  /// further owed day asks again. A day resolved elsewhere meanwhile is no
  /// longer owed, so the edit is saved all the same (#367).
  Future<void> resolveOverdue(OccurrenceStatus status) async {
    final owed = _overdue;
    if (owed == null || state.saving) return;
    state = state.copyWith(saving: true, error: () => null);
    try {
      await _repository.resolve(owed.routineId, status,
          scheduledFor: owed.scheduledFor);
    } on RoutineAlreadyResolvedException {
      // Resolved elsewhere: saved again below.
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

  /// The form changed the field the error is about: its mark goes.
  void clearErrorField() {
    if (state.errorField == null) return;
    state = state.copyWith(errorField: () => null);
  }

  String _today() {
    final now = _clock();
    return formatRoutineDay(DateTime(now.year, now.month, now.day));
  }

  Future<void> _submit() async {
    final input = _pendingInput;
    if (input == null) return;
    _overdue = null;
    state = state.copyWith(
        saving: true,
        error: () => null,
        errorField: () => null,
        overdueDay: () => null);
    try {
      final patch = _pendingPatch;
      final saved = patch == null
          ? await _repository.createRoutine(input)
          : await _repository.editRoutine(_editId!, patch);
      if (!mounted) return;
      if (saved.existing) {
        // A live routine of that name exists: nothing was written.
        state = state.copyWith(
            saving: false,
            error: () => '“${saved.name}” is already on the list: '
                'nothing was saved. Choose another name.',
            errorField: () => RoutineFormField.name);
        return;
      }
      state = state.copyWith(saving: false, saved: saved);
    } on RoutineOverdueException catch (e) {
      if (!mounted) return;
      _overdue = e;
      state = state.copyWith(saving: false, overdueDay: () => e.scheduledFor);
    } on RoutineNameTakenException catch (e) {
      if (!mounted) return;
      state = state.copyWith(
          saving: false,
          error: () => e.message,
          errorField: () => RoutineFormField.name);
    } on RoutineInvalidRRuleException catch (e) {
      if (!mounted) return;
      // With a last day the rule has no day left; without one, the schedule
      // does not parse.
      state = state.copyWith(
          saving: false,
          error: () => e.message,
          errorField: () => input.lastDay != null
              ? RoutineFormField.lastDay
              : RoutineFormField.schedule);
    } on RoutinesException catch (e) {
      if (!mounted) return;
      state = state.copyWith(saving: false, error: () => e.message);
    }
  }
}
