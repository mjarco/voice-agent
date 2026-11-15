import 'package:voice_agent/core/models/day_story.dart';

/// Reads a day's story and settles what waits (ADR-NET-010).
abstract class DayStoryRepository {
  /// The story of [day] (YYYY-MM-DD); [narrate] false skips the narration,
  /// which costs a model call when the day changed.
  Future<DayStory> fetch(String day, {bool narrate = true});

  /// Settles a waiting utterance with its guess [guess], or drops it (null).
  Future<void> settle(String id, int? guess);
}
