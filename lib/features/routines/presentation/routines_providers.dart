import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/core/providers/api_client_provider.dart';
import 'package:voice_agent/features/routines/data/api_routines_repository.dart';
import 'package:voice_agent/features/routines/domain/routine_detail_state.dart';
import 'package:voice_agent/features/routines/domain/routines_repository.dart';
import 'package:voice_agent/features/routines/domain/routines_state.dart';
import 'package:voice_agent/features/routines/presentation/routine_detail_notifier.dart';
import 'package:voice_agent/features/routines/presentation/routines_notifier.dart';

final routinesRepositoryProvider = Provider<RoutinesRepository>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return ApiRoutinesRepository(apiClient);
});

final routinesNotifierProvider =
    StateNotifierProvider<RoutinesNotifier, RoutinesState>((ref) {
  final repository = ref.watch(routinesRepositoryProvider);
  return RoutinesNotifier(repository);
});

final routineDetailNotifierProvider = StateNotifierProvider.family<
    RoutineDetailNotifier, RoutineDetailState, String>((ref, routineId) {
  final repository = ref.watch(routinesRepositoryProvider);
  return RoutineDetailNotifier(repository, routineId);
});
