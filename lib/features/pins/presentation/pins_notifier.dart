import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/features/pins/domain/pins_repository.dart';
import 'package:voice_agent/features/pins/domain/pins_state.dart';

class PinsNotifier extends StateNotifier<PinsListState> {
  PinsNotifier(this._repository) : super(const PinsListInitial()) {
    load();
  }

  final PinsRepository _repository;
  PinView _view = PinView.recent;
  String? lastActionError;

  PinView get view => _view;

  Future<void> load() async {
    state = const PinsListLoading();
    lastActionError = null;
    try {
      final pins = await _repository.fetchPins(_view);
      state = PinsListLoaded(pins: pins, view: _view);
    } catch (e) {
      state = PinsListError(message: e.toString());
    }
  }

  Future<void> refresh() => load();

  Future<void> setView(PinView view) {
    if (view == _view) return Future.value();
    _view = view;
    return load();
  }

  /// Unpin a reference. On success removes the row from the loaded list and
  /// returns true; on failure records [lastActionError] and returns false
  /// (the screen surfaces it via a SnackBar — no state change on failure).
  Future<bool> unpin(String recordId) async {
    lastActionError = null;
    try {
      await _repository.unpin(recordId);
      final current = state;
      if (current is PinsListLoaded) {
        state = PinsListLoaded(
          pins:
              current.pins.where((p) => p.recordId != recordId).toList(),
          view: current.view,
        );
      }
      return true;
    } on PinsException catch (e) {
      lastActionError = e.message;
      return false;
    }
  }
}
