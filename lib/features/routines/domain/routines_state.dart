import 'package:voice_agent/core/models/routine.dart';

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
  const RoutinesLoaded({required this.routines, required this.proposals});
  final List<Routine> routines;
  final List<RoutineProposal> proposals;
}

class RoutinesError extends RoutinesState {
  const RoutinesError({required this.message});
  final String message;
}
