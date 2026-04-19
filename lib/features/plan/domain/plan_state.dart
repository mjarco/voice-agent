import 'package:voice_agent/core/models/plan.dart';

sealed class PlanState {
  const PlanState();
}

class PlanInitial extends PlanState {
  const PlanInitial();
}

class PlanLoading extends PlanState {
  const PlanLoading();
}

class PlanLoaded extends PlanState {
  const PlanLoaded({required this.plan});
  final PlanResponse plan;
}

class PlanError extends PlanState {
  const PlanError({required this.message});
  final String message;
}
