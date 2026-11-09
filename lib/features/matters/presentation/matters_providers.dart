import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/core/providers/api_client_provider.dart';
import 'package:voice_agent/features/matters/data/api_matters_repository.dart';
import 'package:voice_agent/features/matters/domain/matters_repository.dart';
import 'package:voice_agent/features/matters/domain/matters_state.dart';
import 'package:voice_agent/features/matters/presentation/matter_detail_notifier.dart';
import 'package:voice_agent/features/matters/presentation/matters_notifier.dart';

final mattersRepositoryProvider = Provider<MattersRepository>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return ApiMattersRepository(apiClient);
});

final mattersNotifierProvider =
    StateNotifierProvider<MattersNotifier, MattersListState>((ref) {
  return MattersNotifier(ref.watch(mattersRepositoryProvider));
});

final matterDetailNotifierProvider = StateNotifierProvider.family<
    MatterDetailNotifier, MatterDetailState, String>((ref, id) {
  return MatterDetailNotifier(ref.watch(mattersRepositoryProvider), id);
});
