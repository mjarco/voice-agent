import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/features/plan/domain/plan_repository.dart';
import 'package:voice_agent/features/plan/domain/plan_state.dart';

class PlanNotifier extends StateNotifier<PlanState> {
  PlanNotifier(this._repository) : super(const PlanInitial()) {
    load();
  }

  final PlanRepository _repository;
  String? lastActionError;

  Future<void> load() async {
    state = const PlanLoading();
    lastActionError = null;
    try {
      final plan = await _repository.fetchPlan();
      state = PlanLoaded(plan: plan);
    } catch (e) {
      state = PlanError(message: e.toString());
    }
  }

  Future<void> refresh() => load();

  Future<bool> markDone(String id) => _runAction(() => _repository.markDone(id));

  Future<bool> dismiss(String id) => _runAction(() => _repository.dismiss(id));

  Future<bool> confirm(String id) => _runAction(() => _repository.confirm(id));

  Future<bool> toggleEndorse(String id) =>
      _runAction(() => _repository.toggleEndorse(id));

  Future<bool> _runAction(Future<void> Function() action) async {
    lastActionError = null;
    try {
      await action();
      await load();
      return true;
    } on PlanException catch (e) {
      lastActionError = e.message;
      return false;
    }
  }
}
