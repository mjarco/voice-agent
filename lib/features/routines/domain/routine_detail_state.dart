import 'package:voice_agent/core/models/routine.dart';

sealed class RoutineDetailState {
  const RoutineDetailState();
}

class RoutineDetailInitial extends RoutineDetailState {
  const RoutineDetailInitial();
}

class RoutineDetailLoading extends RoutineDetailState {
  const RoutineDetailLoading();
}

class RoutineDetailLoaded extends RoutineDetailState {
  const RoutineDetailLoaded(
      {required this.routine, required this.occurrences});
  final Routine routine;
  final List<RoutineOccurrence> occurrences;
}

class RoutineDetailError extends RoutineDetailState {
  const RoutineDetailError({required this.message});
  final String message;
}
