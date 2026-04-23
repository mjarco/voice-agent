import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/core/providers/api_client_provider.dart';
import 'package:voice_agent/features/usage/data/usage_service.dart';
import 'package:voice_agent/features/usage/domain/usage_state.dart';
import 'package:voice_agent/features/usage/presentation/usage_controller.dart';

final usageServiceProvider = Provider<UsageService>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return UsageService(apiClient);
});

final usageControllerProvider =
    StateNotifierProvider<UsageController, UsageState>((ref) {
  final service = ref.watch(usageServiceProvider);
  return UsageController(service);
});
