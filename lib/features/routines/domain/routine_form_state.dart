import 'package:voice_agent/core/models/routine.dart';

/// The state of the routine form (#365). [routine] is the version being
/// edited, null for a new routine.
class RoutineFormState {
  const RoutineFormState({
    this.loading = false,
    this.routine,
    this.saving = false,
    this.error,
    this.overdueDay,
    this.saved,
  });

  /// The edited routine (with its steps) is still loading.
  final bool loading;
  final Routine? routine;
  final bool saving;
  final String? error;

  /// The day a waits routine still owes (`409 overdue_occurrence`): the form
  /// asks to tick it off or skip it, then saves the same edit again.
  final String? overdueDay;

  /// The routine the save wrote; the form closes once it is set.
  final Routine? saved;

  RoutineFormState copyWith({
    bool? loading,
    Routine? routine,
    bool? saving,
    String? Function()? error,
    String? Function()? overdueDay,
    Routine? saved,
  }) {
    return RoutineFormState(
      loading: loading ?? this.loading,
      routine: routine ?? this.routine,
      saving: saving ?? this.saving,
      error: error != null ? error() : this.error,
      overdueDay: overdueDay != null ? overdueDay() : this.overdueDay,
      saved: saved ?? this.saved,
    );
  }
}
