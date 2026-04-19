import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/core/providers/api_client_provider.dart';
import 'package:voice_agent/features/routines/data/api_routines_repository.dart';
import 'package:voice_agent/features/routines/domain/routines_repository.dart';
import 'package:voice_agent/features/routines/domain/routines_state.dart';
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
