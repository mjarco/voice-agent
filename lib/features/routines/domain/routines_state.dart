import 'package:voice_agent/core/models/routine.dart';

/// The tabs of the routines list (#365). Ended holds ended and archived
/// routines; a draft is listed under Active.
enum RoutinesTab { active, paused, ended }

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
  const RoutinesLoaded({required this.routines});
  final List<Routine> routines;
}

class RoutinesError extends RoutinesState {
  const RoutinesError({required this.message});
  final String message;
}
