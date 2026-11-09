import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/features/pins/domain/pins_repository.dart';
import 'package:voice_agent/features/pins/domain/pins_state.dart';

class PinsNotifier extends StateNotifier<PinsListState> {
  PinsNotifier(this._repository) : super(const PinsListInitial()) {
    load();
  }

  final PinsRepository _repository;
  String? lastActionError;

  Future<void> load() async {
    state = const PinsListLoading();
    lastActionError = null;
    try {
      final pins = await _repository.fetchPins();
      state = PinsListLoaded(pins: pins);
    } catch (e) {
      state = PinsListError(message: e.toString());
    }
  }

  Future<void> refresh() => load();

  /// Unpin a reference. On success removes the row from the loaded list and
  /// returns true; on failure records [lastActionError] and returns false
  /// (the screen surfaces it via a SnackBar — no state change on failure, but
  /// a refusal because the pin has a newer version reads the list again).
  Future<bool> unpin(String recordId) async {
    lastActionError = null;
    try {
      await _repository.unpin(recordId);
      final current = state;
      if (current is PinsListLoaded) {
        state = PinsListLoaded(
          pins:
              current.pins.where((p) => p.recordId != recordId).toList(),
        );
      }
      return true;
    } catch (e) {
      final message = e is PinsException ? e.message : e.toString();
      if (e is PinRefusedException && e.isStale) await load();
      lastActionError = message;
      return false;
    }
  }
}
