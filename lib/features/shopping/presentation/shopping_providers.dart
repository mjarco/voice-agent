import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/core/network/shopping_proposals_port.dart';
import 'package:voice_agent/core/providers/api_client_provider.dart';
import 'package:voice_agent/features/shopping/data/api_shopping_repository.dart';
import 'package:voice_agent/features/shopping/domain/shopping_repository.dart';
import 'package:voice_agent/features/shopping/domain/shopping_state.dart';
import 'package:voice_agent/features/shopping/presentation/shopping_notifier.dart';

final shoppingRepositoryProvider = Provider<ShoppingRepository>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return ApiShoppingRepository(apiClient);
});

final shoppingNotifierProvider =
    StateNotifierProvider<ShoppingNotifier, ShoppingState>((ref) {
  final repository = ref.watch(shoppingRepositoryProvider);
  return ShoppingNotifier(repository, ref.watch(shoppingProposalsPortProvider));
});
