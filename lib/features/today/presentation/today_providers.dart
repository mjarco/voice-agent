import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/core/providers/agent_turns_provider.dart';
import 'package:voice_agent/core/providers/api_client_provider.dart';
import 'package:voice_agent/features/today/data/api_day_story_repository.dart';
import 'package:voice_agent/features/today/data/api_today_repository.dart';
import 'package:voice_agent/features/today/domain/day_story_repository.dart';
import 'package:voice_agent/features/today/domain/today_repository.dart';
import 'package:voice_agent/features/today/presentation/day_story_notifier.dart';
import 'package:voice_agent/features/today/presentation/today_notifier.dart';

final todayRepositoryProvider = Provider<TodayRepository>(
  (ref) => ApiTodayRepository(ref.watch(apiClientProvider)),
);

final todayNotifierProvider =
    StateNotifierProvider<TodayNotifier, TodayState>((ref) {
  final notifier = TodayNotifier(ref.watch(todayRepositoryProvider), ref);
  // A turn answered, spoken or typed, may have logged a meal or ticked a
  // task: read the day again.
  ref.listen<int>(agentTurnsProvider, (_, _) => notifier.refresh());
  return notifier;
});

final dayStoryRepositoryProvider = Provider<DayStoryRepository>(
  (ref) => ApiDayStoryRepository(ref.watch(apiClientProvider)),
);

/// A day's story (ADR-NET-010), read again after every answered turn, which
/// may have queued an utterance or changed the day.
final dayStoryProvider = StateNotifierProvider.autoDispose
    .family<DayStoryNotifier, DayStoryState, DayStoryKey>((ref, key) {
  final turns = ref.read(agentTurnsProvider.notifier);
  final notifier = DayStoryNotifier(
    ref.watch(dayStoryRepositoryProvider),
    key,
    onSettled: () => turns.state++,
  );
  ref.listen<int>(agentTurnsProvider, (_, _) => notifier.refresh());
  return notifier;
});
