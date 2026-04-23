import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/features/usage/data/usage_service.dart';
import 'package:voice_agent/features/usage/domain/usage_state.dart';
import 'package:voice_agent/features/usage/domain/usage_summary.dart';

class UsageController extends StateNotifier<UsageState> {
  UsageController(this._service) : super(const UsageLoading()) {
    _load();
  }

  final UsageService _service;

  Future<void> _load() async {
    state = const UsageLoading();

    try {
      final now = DateTime.now();
      final currentFrom = _firstOfMonth(now.year, now.month);
      final currentTo = _formatDate(now);

      final prevMonth = now.month == 1
          ? DateTime(now.year - 1, 12)
          : DateTime(now.year, now.month - 1);
      final previousFrom = _firstOfMonth(prevMonth.year, prevMonth.month);
      final previousTo = _lastOfMonth(prevMonth.year, prevMonth.month);

      final currentSummary = await _service.getSummary(
        from: currentFrom,
        to: currentTo,
      );

      UsageSummary? previousSummary;
      try {
        previousSummary = await _service.getSummary(
          from: previousFrom,
          to: previousTo,
        );
      } catch (_) {
        // Previous month data is optional; ignore errors
      }

      state = UsageLoaded(
        currentMonth: currentSummary,
        previousMonth: previousSummary,
      );
    } catch (e) {
      state = UsageError(message: e.toString());
    }
  }

  Future<void> refresh() => _load();

  String _firstOfMonth(int year, int month) {
    return '$year-${month.toString().padLeft(2, '0')}-01';
  }

  String _lastOfMonth(int year, int month) {
    final lastDay = DateTime(year, month + 1, 0).day;
    return '$year-${month.toString().padLeft(2, '0')}-${lastDay.toString().padLeft(2, '0')}';
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
