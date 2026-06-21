import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/features/pins/domain/pins_repository.dart';
import 'package:voice_agent/features/pins/domain/pins_state.dart';

class PinDetailNotifier extends StateNotifier<PinDetailState> {
  PinDetailNotifier(this._repository, this._recordId)
      : super(const PinDetailLoading()) {
    load();
  }

  final PinsRepository _repository;
  final String _recordId;
  String? lastActionError;

  Future<void> load() async {
    state = const PinDetailLoading();
    lastActionError = null;
    try {
      final pin = await _repository.fetchPin(_recordId);
      state = PinDetailLoaded(pin: pin);
    } catch (e) {
      state = PinDetailError(message: e.toString());
    }
  }

  Future<void> refresh() => load();

  /// Unpin this reference. Returns true on success; on failure records
  /// [lastActionError] and returns false. The list refreshes on return per
  /// ADR-ARCH-011, so this notifier does not mutate list state.
  Future<bool> unpin() async {
    lastActionError = null;
    try {
      await _repository.unpin(_recordId);
      return true;
    } on PinsException catch (e) {
      lastActionError = e.message;
      return false;
    }
  }
}
