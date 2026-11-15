import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/core/providers/agent_reply_provider.dart';
import 'package:voice_agent/core/providers/api_client_provider.dart';
import 'package:voice_agent/features/today/data/api_today_repository.dart';
import 'package:voice_agent/features/today/domain/today_repository.dart';
import 'package:voice_agent/features/today/presentation/today_notifier.dart';

final todayRepositoryProvider = Provider<TodayRepository>(
  (ref) => ApiTodayRepository(ref.watch(apiClientProvider)),
);

final todayNotifierProvider =
    StateNotifierProvider<TodayNotifier, TodayState>((ref) {
  final notifier = TodayNotifier(ref.watch(todayRepositoryProvider), ref);
  // A reply may have logged a meal or ticked a task: read the day again.
  ref.listen<String?>(latestAgentReplyProvider, (prev, next) {
    if (next != null && next != prev) notifier.refresh();
  });
  return notifier;
});
