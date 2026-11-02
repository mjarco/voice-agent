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
      state = PinDetailError(
        message: e.toString(),
        gone: e is PinNotFoundException,
      );
    }
  }

  Future<void> refresh() => load();

  /// Unpin this reference. Returns true on success; on failure records
  /// [lastActionError] and returns false. The list refreshes on return per
  /// ADR-ARCH-011, so this notifier does not mutate list state. A refusal
  /// because the pin has a newer version reads it again.
  Future<bool> unpin() async {
    lastActionError = null;
    try {
      await _repository.unpin(_recordId);
      return true;
    } catch (e) {
      final message = e is PinsException ? e.message : e.toString();
      if (e is PinRefusedException && e.isStale) await load();
      lastActionError = message;
      return false;
    }
  }
}
