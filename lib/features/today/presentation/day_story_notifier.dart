import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/core/models/day_story.dart';
import 'package:voice_agent/features/today/domain/day_story_repository.dart';

/// A day's story: the last read, and whether a read or a settle is running
/// or failed.
class DayStoryState {
  const DayStoryState({this.story, this.loading = false, this.error, this.settling = const {}});

  final DayStory? story;
  final bool loading;
  final String? error;

  /// The utterances whose settle is in flight.
  final Set<String> settling;

  DayStoryState copyWith({DayStory? story, bool? loading, String? error, Set<String>? settling}) => DayStoryState(
        story: story ?? this.story,
        loading: loading ?? this.loading,
        error: error,
        settling: settling ?? this.settling,
      );
}

/// What a day's story is read for: the day, and whether to narrate.
typedef DayStoryKey = ({String day, bool narrate});

class DayStoryNotifier extends StateNotifier<DayStoryState> {
  DayStoryNotifier(this._repo, this.key, {void Function()? onSettled})
      : _onSettled = onSettled,
        super(const DayStoryState(loading: true)) {
    refresh();
  }

  final DayStoryRepository _repo;
  final DayStoryKey key;

  /// Told when a guess ran: it may have logged a meal, added a task or an
  /// item, or written into a matter.
  final void Function()? _onSettled;

  Future<void> refresh() async {
    state = state.copyWith(loading: true);
    try {
      final story = await _repo.fetch(key.day, narrate: key.narrate);
      if (mounted) state = DayStoryState(story: story, settling: state.settling);
    } on Object catch (e) {
      if (mounted) state = state.copyWith(loading: false, error: '$e');
    }
  }

  /// Settles [id] with guess [guess], or drops it (null). The line goes at
  /// once; a failure brings it back with the error.
  Future<bool> settle(String id, int? guess) async {
    final before = state.story;
    if (before == null || state.settling.contains(id)) return false;
    state = DayStoryState(story: before.withoutPending(id), settling: {...state.settling, id});
    try {
      await _repo.settle(id, guess);
      if (guess != null) _onSettled?.call();
      if (mounted) state = state.copyWith(settling: {...state.settling}..remove(id));
      return true;
    } on Object catch (e) {
      if (mounted) {
        state = DayStoryState(story: before, error: '$e', settling: {...state.settling}..remove(id));
      }
      return false;
    }
  }
}
