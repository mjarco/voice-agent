import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/core/providers/api_client_provider.dart';
import 'package:voice_agent/features/plan/data/api_plan_repository.dart';
import 'package:voice_agent/features/plan/domain/plan_repository.dart';
import 'package:voice_agent/features/plan/domain/plan_state.dart';
import 'package:voice_agent/features/plan/presentation/plan_notifier.dart';

final planRepositoryProvider = Provider<PlanRepository>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return ApiPlanRepository(apiClient);
});

final planNotifierProvider =
    StateNotifierProvider<PlanNotifier, PlanState>((ref) {
  final repository = ref.watch(planRepositoryProvider);
  return PlanNotifier(repository);
});
