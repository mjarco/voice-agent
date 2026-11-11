import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/core/models/shopping_proposal.dart';
import 'package:voice_agent/core/network/shopping_proposals_port.dart';
import 'package:voice_agent/features/shopping/domain/shopping_models.dart';
import 'package:voice_agent/features/shopping/domain/shopping_repository.dart';
import 'package:voice_agent/features/shopping/domain/shopping_state.dart';

/// What became of a save, for the screen to say.
enum ShoppingAddOutcome { added, addedNotShown, alreadyOnList, failed }

class ShoppingNotifier extends StateNotifier<ShoppingState> {
  ShoppingNotifier(
    this._repository,
    this._proposals, {
    this.rereadDelay = const Duration(seconds: 4),
  }) : super(const ShoppingLoading()) {
    load();
  }

  final ShoppingRepository _repository;
  final ShoppingProposalsPort _proposals;

  /// The server tags in the background, so the list is read once more after a
  /// save, to show the tags. There is no polling.
  final Duration rereadDelay;

  ShoppingView _view = ShoppingView.toBuy;
  String? _filter;
  List<String> _placeTypes = const [];
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
    final placeTypes = _placeTypes;
    try {
      final results = await Future.wait([
        _repository.fetchCatalogue(),
        // A place's types are read as one list and kept to them below.
        _repository.fetchItems(
          view,
          storeType: placeTypes.isEmpty ? filter : null,
        ),
        _readWaiting(),
      ]);
      // A newer read is on its way; this answer is stale.
      if (!mounted || generation != _generation) return;
      final catalogue = results[0] as ShoppingCatalogue;
      var items = results[1] as List<ShoppingItem>;
      // Types the catalogue does not know are dropped; with none left, all.
      final known = {for (final t in catalogue.storeTypes) t.id};
      final types = [
        for (final t in placeTypes)
          if (known.contains(t)) t,
      ];
      if (types.isNotEmpty) {
        items = [
          for (final item in items)
            if (_underAny(item, types)) item,
        ];
      }
      if (placeTypes.isNotEmpty) _placeTypes = types;
      final waiting = results[2] as List<ShoppingProposal>?;
      state = ShoppingLoaded(
        catalogue: catalogue,
        items: items,
        proposals: waiting == null
            ? _proposalRows
            : ShoppingProposalRow.fromRead(waiting, _proposalRows),
        view: view,
        filter: filter,
        placeTypes: types,
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
          proposals: current.proposals,
          view: current.view,
          filter: current.filter,
          placeTypes: current.placeTypes,
          readError: e.toString(),
        );
      }
    }
  }

  /// The list stands without the proposals, so a failed read does not fail it.
  /// Null when the read failed, which leaves the cards already shown.
  Future<List<ShoppingProposal>?> _readWaiting() async {
    try {
      return await _proposals.list();
    } on ShoppingProposalsException {
      return null;
    }
  }

  List<ShoppingProposalRow> get _proposalRows => switch (state) {
        ShoppingLoaded(proposals: final rows) => rows,
        _ => const [],
      };

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
    _placeTypes = const [];
    _showSelection();
    return load();
  }

  /// The store types of a place, from a tap on its arrival alert: To buy,
  /// with every one of them selected.
  Future<void> selectPlace(List<String> storeTypes) {
    if (storeTypes.isEmpty) return Future.value();
    _view = ShoppingView.toBuy;
    _filter = null;
    _placeTypes = storeTypes.toSet().toList();
    _showSelection();
    return load();
  }

  void _showSelection() {
    final current = state;
    if (current is! ShoppingLoaded) return;
    state = ShoppingLoaded(
      catalogue: current.catalogue,
      items: current.items,
      proposals: current.proposals,
      view: _view,
      filter: _filter,
      placeTypes: _placeTypes,
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
    if (_placeTypes.isNotEmpty) return _underAny(item, _placeTypes);
    final filter = _filter;
    if (filter == null || item.storeTypes.contains(filter)) return true;
    return filter == 'other' && item.storeTypes.isEmpty;
  }

  /// Under any of [types], as personal-agent counts a place's items: `other`
  /// holds the items with no type.
  static bool _underAny(ShoppingItem item, List<String> types) => types.any(
        (t) =>
            item.storeTypes.contains(t) ||
            (t == 'other' && item.storeTypes.isEmpty),
      );

  /// A corrected text, corrected types, or both; null leaves that part.
  Future<bool> edit(String id, {String? text, List<String>? storeTypes}) =>
      _act(() => _repository.edit(id, text: text, storeTypes: storeTypes));

  /// Under a place's types, where it was bought is the item's first of them.
  Future<bool> markBought(String id) =>
      _act(() => _repository.markBought(id, storeType: _boughtType(id)));

  String? _boughtType(String id) {
    if (_placeTypes.isEmpty) return _filter;
    final current = state;
    if (current is! ShoppingLoaded) return null;
    final item = current.items.where((i) => i.id == id).firstOrNull;
    if (item == null) return null;
    if (item.storeTypes.isEmpty && _placeTypes.contains('other')) return 'other';
    return item.storeTypes.where(_placeTypes.contains).firstOrNull;
  }

  Future<bool> remove(String id) => _act(() => _repository.remove(id));

  Future<bool> restore(String id) => _act(() async {
        final item = await _repository.restore(id);
        if (item.isTagging) _scheduleReread();
      });

  /// Answers a proposal from its card. A second tap while one is on its way
  /// does nothing.
  Future<void> answerProposal(String id, {required bool accept}) async {
    final row = _proposalRows.where((r) => r.proposal.id == id).firstOrNull;
    if (row == null || row.answering) return;
    _updateProposalRow(id, (r) => r.asAnswering());
    final answer =
        accept ? await _proposals.accept(id) : await _proposals.skip(id);
    if (!mounted) return;
    _updateProposalRow(id, (r) => r.after(answer));
    if (!answer.settled) return;
    await load();
    // An added item is tagged in the background.
    if (accept && row.proposal.kind == 'add') _scheduleReread();
  }

  void _updateProposalRow(
    String id,
    ShoppingProposalRow Function(ShoppingProposalRow) update,
  ) {
    final current = state;
    if (current is! ShoppingLoaded) return;
    state = ShoppingLoaded(
      catalogue: current.catalogue,
      items: current.items,
      proposals: [
        for (final row in current.proposals)
          row.proposal.id == id ? update(row) : row,
      ],
      view: current.view,
      filter: current.filter,
      placeTypes: current.placeTypes,
      reading: current.reading,
      readError: current.readError,
    );
  }

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
