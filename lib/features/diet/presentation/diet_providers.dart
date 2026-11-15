import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/core/providers/api_client_provider.dart';
import 'package:voice_agent/features/diet/data/api_diet_repository.dart';
import 'package:voice_agent/features/diet/domain/diet_repository.dart';

final dietRepositoryProvider = Provider<DietRepository>(
  (ref) => ApiDietRepository(ref.watch(apiClientProvider)),
);

/// Bumped when the diet is written outside its day's screen (a card under a
/// reply corrected or undid a meal, ADR-NET-009); the day reads itself again.
final dietChangedProvider = StateProvider<int>((ref) => 0);
