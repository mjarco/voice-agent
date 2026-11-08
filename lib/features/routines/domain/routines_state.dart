import 'package:voice_agent/core/models/routine.dart';

/// The sections of the routines list, as the web UI groups them
/// (ADR-CORE-116 of personal-agent): live recurring routines, one-off tasks
/// by due day, someday ones, paused ones, and those done, ended or archived.
class RoutineSections {
  const RoutineSections({
    this.recurring = const [],
    this.tasks = const [],
    this.someday = const [],
    this.paused = const [],
    this.finished = const [],
  });

  factory RoutineSections.of(List<Routine> routines) {
    bool live(Routine r) => !r.ended && r.status == RoutineStatus.active;
    List<Routine> where(bool Function(Routine) test) =>
        routines.where(test).toList();
    return RoutineSections(
      recurring: where((r) => live(r) && r.kind == RoutineKind.recurring),
      tasks: where((r) => live(r) && r.kind == RoutineKind.oneOff)
        ..sort((a, b) => (a.dueOn ?? '').compareTo(b.dueOn ?? '')),
      someday: where((r) => live(r) && r.kind == RoutineKind.someday),
      paused: where((r) => !r.ended && r.status == RoutineStatus.paused),
      finished: where((r) => r.ended || r.status == RoutineStatus.archived)
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)),
    );
  }

  final List<Routine> recurring;
  final List<Routine> tasks;
  final List<Routine> someday;
  final List<Routine> paused;

  /// Done, ended and archived, the latest changed first.
  final List<Routine> finished;

  bool get isEmpty =>
      recurring.isEmpty &&
      tasks.isEmpty &&
      someday.isEmpty &&
      paused.isEmpty &&
      finished.isEmpty;
}

sealed class RoutinesState {
  const RoutinesState();
}

class RoutinesInitial extends RoutinesState {
  const RoutinesInitial();
}

class RoutinesLoading extends RoutinesState {
  const RoutinesLoading();
}

class RoutinesLoaded extends RoutinesState {
  RoutinesLoaded({required this.routines})
      : sections = RoutineSections.of(routines);
  final List<Routine> routines;
  final RoutineSections sections;
}

class RoutinesError extends RoutinesState {
  const RoutinesError({required this.message});
  final String message;
}
