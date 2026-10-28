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
    if (state.saving || state.loading || state.stale) return;
    _pending = (input: input, startsOn: startsOn);
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
      await _repository.resolveOccurrence(
          owed.routineId, owed.scheduledFor, status);
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
    state = state.copyWith(overdueDay: () => null, overdueOpenDays: () => null);
  }

  /// The form changed the field the error is about: its mark goes.
  void clearErrorField() {
    if (state.errorField == null) return;
    state = state.copyWith(errorField: () => null);
  }

  Future<void> _submit() async {
    final pending = _pending;
    if (pending == null) return;
    _overdue = null;
    state = state.copyWith(
        saving: true,
        error: () => null,
        errorField: () => null,
        overdueDay: () => null,
        overdueOpenDays: () => null);
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
      state = state.copyWith(
          saving: false,
          overdueDay: () => e.scheduledFor,
          overdueOpenDays: () => e.openDays);
    } on RoutineAlreadyEditedException {
      if (!mounted) return;
      await _openNewer();
    } on RoutineFieldException catch (e) {
      if (!mounted) return;
      state = state.copyWith(
          saving: false,
          error: () => _refusal(e, pending.startsOn),
          errorField: () => e.field);
    } on RoutinesException catch (e) {
      if (!mounted) return;
      state = state.copyWith(saving: false, error: () => e.message);
    }
  }

  /// The message of a field refusal, in the web UI's words (#575).
  String _refusal(RoutineFieldException e, String? startsOn) {
    if (e.field != RoutineFormField.lastDay || !e.firstDayKnown) {
      return e.message;
    }
    final now = _clock();
    final from =
        startsOn ?? formatRoutineDay(DateTime(now.year, now.month, now.day));
    final first = e.firstDay;
    if (first != null) {
      return 'The first day of this schedule from $from is $first, after '
          'the last day. Move the last day or clear it.';
    }
    return 'No day of this schedule falls between $from and the last day. '
        'Move the last day or clear it.';
  }

  /// A stale edit (`routine_already_edited`): the form is not saved again,
  /// and the newest version of the routine is the one to open.
  Future<void> _openNewer() async {
    const changed = 'This routine was changed meanwhile.';
    state = state.copyWith(saving: false, stale: true, error: () => changed);
    try {
      var newer = await _repository.fetchRoutineDetail(_editId!);
      // Each edit links the version it replaced; a few hops at most.
      for (var hop = 0; newer.nextRoutineId != null && hop < 10; hop++) {
        newer = await _repository.fetchRoutineDetail(newer.nextRoutineId!);
      }
      if (!mounted) return;
      if (newer.id != _editId) state = state.copyWith(newer: newer);
    } on RoutinesException catch (e) {
      if (!mounted) return;
      state = state.copyWith(
          error: () => '$changed Failed to load its newer version: $e');
    }
  }
}
