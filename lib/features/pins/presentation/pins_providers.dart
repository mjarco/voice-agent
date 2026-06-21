import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/core/providers/api_client_provider.dart';
import 'package:voice_agent/features/pins/data/api_pins_repository.dart';
import 'package:voice_agent/features/pins/domain/pins_repository.dart';
import 'package:voice_agent/features/pins/domain/pins_state.dart';
import 'package:voice_agent/features/pins/presentation/pin_detail_notifier.dart';
import 'package:voice_agent/features/pins/presentation/pins_notifier.dart';

final pinsRepositoryProvider = Provider<PinsRepository>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return ApiPinsRepository(apiClient);
});

final pinsNotifierProvider =
    StateNotifierProvider<PinsNotifier, PinsListState>((ref) {
  final repository = ref.watch(pinsRepositoryProvider);
  return PinsNotifier(repository);
});

final pinDetailNotifierProvider = StateNotifierProvider.family<
    PinDetailNotifier, PinDetailState, String>((ref, recordId) {
  final repository = ref.watch(pinsRepositoryProvider);
  return PinDetailNotifier(repository, recordId);
});
