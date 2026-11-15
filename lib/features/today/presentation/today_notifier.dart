import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/core/models/today.dart';
import 'package:voice_agent/core/providers/agenda_changes_provider.dart';
import 'package:voice_agent/features/today/domain/today_repository.dart';

/// Dziś's state: the last day read, and whether a read is running or failed.
class TodayState {
  const TodayState({this.view, this.loading = false, this.error});

  final TodayView? view;
  final bool loading;
  final String? error;
}

class TodayNotifier extends StateNotifier<TodayState> {
  TodayNotifier(this._repo, this._ref) : super(const TodayState(loading: true)) {
    refresh();
  }

  final TodayRepository _repo;
  final Ref _ref;

  Future<void> refresh() async {
    state = TodayState(view: state.view, loading: true);
    try {
      final view = await _repo.fetchToday();
      if (mounted) state = TodayState(view: view);
    } on Object catch (e) {
      if (mounted) state = TodayState(view: state.view, error: '$e');
    }
  }

  /// Takes a swiped item off the list at once; a Dismissible must leave the
  /// tree when it is dismissed, before the next read comes back.
  void drop(String key) {
    final view = state.view;
    if (view == null) return;
    state = TodayState(view: view.withoutItem(key), loading: state.loading, error: state.error);
  }

  /// Runs a task's call and reads the day again. False when it failed; the
  /// list is read again either way.
  Future<bool> run(TodayAction action) async {
    try {
      await _repo.run(action);
      _ref.read(agendaChangesProvider.notifier).state++;
      return true;
    } on Object catch (e) {
      if (mounted) state = TodayState(view: state.view, error: '$e');
      return false;
    } finally {
      await refresh();
    }
  }
}
