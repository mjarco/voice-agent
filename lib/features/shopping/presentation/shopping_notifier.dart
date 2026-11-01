import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/features/shopping/domain/shopping_models.dart';
import 'package:voice_agent/features/shopping/domain/shopping_repository.dart';
import 'package:voice_agent/features/shopping/domain/shopping_state.dart';

/// What became of a save, for the screen to say.
enum ShoppingAddOutcome { added, addedNotShown, alreadyOnList, failed }

class ShoppingNotifier extends StateNotifier<ShoppingState> {
  ShoppingNotifier(
    this._repository, {
    this.rereadDelay = const Duration(seconds: 4),
  }) : super(const ShoppingLoading()) {
    load();
  }

  final ShoppingRepository _repository;

  /// The server tags in the background, so the list is read once more after a
  /// save, to show the tags. There is no polling.
  final Duration rereadDelay;

  ShoppingView _view = ShoppingView.toBuy;
  String? _filter;
  int _generation = 0;
  Timer? _reread;
  String? lastActionError;

  /// Reads the catalogue and the list. A list of the current selection stays
  /// until the new one arrives, and a failed read leaves it in place; a failed
  /// read of a new selection says so.
  Future<void> load() async {
    final generation = ++_generation;
    final view = _view;
    final filter = _filter;
    try {
      final results = await Future.wait([
        _repository.fetchCatalogue(),
        _repository.fetchItems(view, storeType: filter),
      ]);
      // A newer read is on its way; this answer is stale.
      if (!mounted || generation != _generation) return;
      state = ShoppingLoaded(
        catalogue: results[0] as ShoppingCatalogue,
        items: results[1] as List<ShoppingItem>,
        view: view,
        filter: filter,
      );
    } catch (e) {
      if (!mounted || generation != _generation) return;
      final current = state;
      if (current is! ShoppingLoaded) {
        state = ShoppingError(message: e.toString());
      } else if (current.reading) {
        state = ShoppingLoaded(
          catalogue: current.catalogue,
          items: current.items,
          view: current.view,
          filter: current.filter,
          readError: e.toString(),
        );
      }
    }
  }

  /// A load from an error, which shows the spinner again.
  Future<void> retry() {
    if (state is ShoppingLoaded) {
      _showSelection();
    } else {
      state = const ShoppingLoading();
    }
    return load();
  }

  Future<void> selectView(ShoppingView view) {
    _view = view;
    _showSelection();
    return load();
  }

  /// [storeType] is a store type id, or null for all.
  Future<void> selectFilter(String? storeType) {
    _filter = storeType;
    _showSelection();
    return load();
  }

  void _showSelection() {
    final current = state;
    if (current is! ShoppingLoaded) return;
    state = ShoppingLoaded(
      catalogue: current.catalogue,
      items: current.items,
      view: _view,
      filter: _filter,
      reading: true,
    );
  }

  Future<ShoppingAddOutcome> add(
    String text, {
    List<String> storeTypes = const [],
  }) async {
    lastActionError = null;
    try {
      final result = await _repository.addItem(text, storeTypes: storeTypes);
      await load();
      if (result.item.isTagging) _scheduleReread();
      if (!result.created) return ShoppingAddOutcome.alreadyOnList;
      return _shown(result.item)
          ? ShoppingAddOutcome.added
          : ShoppingAddOutcome.addedNotShown;
    } on ShoppingException catch (e) {
      lastActionError = e.message;
      return ShoppingAddOutcome.failed;
    }
  }

  bool _shown(ShoppingItem item) {
    if (_view != ShoppingView.toBuy) return false;
    final filter = _filter;
    if (filter == null || item.storeTypes.contains(filter)) return true;
    return filter == 'other' && item.storeTypes.isEmpty;
  }

  Future<bool> setTypes(String id, List<String> storeTypes) =>
      _act(() => _repository.setTypes(id, storeTypes));

  Future<bool> markBought(String id) =>
      _act(() => _repository.markBought(id, storeType: _filter));

  Future<bool> remove(String id) => _act(() => _repository.remove(id));

  Future<bool> restore(String id) => _act(() async {
        final item = await _repository.restore(id);
        if (item.isTagging) _scheduleReread();
      });

  Future<bool> _act(Future<void> Function() action) async {
    lastActionError = null;
    try {
      await action();
      await load();
      return true;
    } on ShoppingException catch (e) {
      lastActionError = e.message;
      // The list may be out of date, which is why the action failed. The
      // screen says so without waiting for the read.
      unawaited(load());
      return false;
    }
  }

  void _scheduleReread() {
    _reread?.cancel();
    _reread = Timer(rereadDelay, load);
  }

  @override
  void dispose() {
    _reread?.cancel();
    super.dispose();
  }
}
