import 'package:voice_agent/core/models/plan.dart';

sealed class PlanException implements Exception {
  String get message;

  @override
  String toString() => message;
}

class PlanGeneralException extends PlanException {
  PlanGeneralException(this.message);
  @override
  final String message;
}

class PlanConflictException extends PlanException {
  PlanConflictException([this.message = 'Action not available for this item']);
  @override
  final String message;
}

abstract class PlanRepository {
  Future<PlanResponse> fetchPlan();
  Future<void> markDone(String id);
  Future<void> dismiss(String id);
  Future<void> confirm(String id);
  Future<void> toggleEndorse(String id);
}
