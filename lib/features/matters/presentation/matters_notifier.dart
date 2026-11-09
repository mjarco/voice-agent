import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/core/models/matter.dart';
import 'package:voice_agent/features/matters/domain/matters_repository.dart';
import 'package:voice_agent/features/matters/domain/matters_state.dart';

/// The matters list: the proposed ones (read apart, as the default list
/// leaves them out) and every other.
class MattersNotifier extends StateNotifier<MattersListState> {
  MattersNotifier(this._repository) : super(const MattersListLoading()) {
    load();
  }

  final MattersRepository _repository;
  String? lastActionError;

  Future<void> load() async {
    if (state is! MattersListLoaded) state = const MattersListLoading();
    try {
      final lists = await Future.wait([
        _repository.fetchMatters(filter: MatterFilter.proposed),
        _repository.fetchMatters(),
      ]);
      if (!mounted) return;
      state = MattersListLoaded(proposed: lists[0], matters: lists[1]);
    } catch (e) {
      if (!mounted) return;
      state = MattersListError(message: e.toString());
    }
  }

  Future<void> refresh() => load();

  /// Accepts a proposed matter as [status]; the list is read again. On
  /// failure records [lastActionError] and returns false.
  Future<bool> accept(String id, MatterStatus status) =>
      _act(() => _repository.accept(id, status));

  /// Drops a proposed matter; the list is read again.
  Future<bool> drop(String id) => _act(() => _repository.drop(id));

  Future<bool> _act(Future<void> Function() call) async {
    lastActionError = null;
    try {
      await call();
      await load();
      return true;
    } catch (e) {
      lastActionError = e is MattersException ? e.message : e.toString();
      return false;
    }
  }
}
