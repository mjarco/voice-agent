import 'package:voice_agent/features/usage/domain/usage_summary.dart';

sealed class UsageState {
  const UsageState();
}

class UsageLoading extends UsageState {
  const UsageLoading();
}

class UsageLoaded extends UsageState {
  const UsageLoaded({required this.currentMonth, this.previousMonth});
  final UsageSummary currentMonth;
  final UsageSummary? previousMonth;
}

class UsageError extends UsageState {
  const UsageError({required this.message});
  final String message;
}
