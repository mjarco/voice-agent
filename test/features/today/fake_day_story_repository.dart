import 'package:voice_agent/core/models/day_story.dart';
import 'package:voice_agent/features/today/domain/day_story_repository.dart';

class FakeDayStoryRepository implements DayStoryRepository {
  FakeDayStoryRepository([this.story]);

  DayStory? story;
  final fetches = <String>[];
  final settled = <String>[];
  bool failSettle = false;

  @override
  Future<DayStory> fetch(String day, {bool narrate = true}) async {
    fetches.add('$day narrate=$narrate');
    return story ?? DayStory(day: day);
  }

  @override
  Future<void> settle(String id, int? guess) async {
    if (failSettle) throw Exception('boom');
    settled.add('$id ${guess ?? 'none'}');
    story = story?.withoutPending(id);
  }
}
