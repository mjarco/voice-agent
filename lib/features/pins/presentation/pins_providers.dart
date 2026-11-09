import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/core/providers/api_client_provider.dart';
import 'package:voice_agent/features/pins/data/api_pins_repository.dart';
import 'package:voice_agent/features/pins/data/prefs_pin_draft_store.dart';
import 'package:voice_agent/features/pins/domain/pin_draft_store.dart';
import 'package:voice_agent/features/pins/domain/pins_repository.dart';
import 'package:voice_agent/features/pins/domain/pins_state.dart';
import 'package:voice_agent/features/pins/presentation/pin_detail_notifier.dart';
import 'package:voice_agent/features/pins/presentation/pins_notifier.dart';

final pinsRepositoryProvider = Provider<PinsRepository>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return ApiPinsRepository(apiClient);
});

final pinDraftStoreProvider = Provider<PinDraftStore>(
  (ref) => PrefsPinDraftStore(),
);

final pinsNotifierProvider =
    StateNotifierProvider<PinsNotifier, PinsListState>((ref) {
  final repository = ref.watch(pinsRepositoryProvider);
  return PinsNotifier(repository);
});

/// Disposed with its page, as the routine's: a pin opened again from the list
/// loads afresh instead of showing what it was before an edit.
final pinDetailNotifierProvider = StateNotifierProvider.autoDispose.family<
    PinDetailNotifier, PinDetailState, String>((ref, recordId) {
  final repository = ref.watch(pinsRepositoryProvider);
  return PinDetailNotifier(repository, recordId);
});
