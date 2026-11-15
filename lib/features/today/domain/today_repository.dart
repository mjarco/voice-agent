import 'package:voice_agent/core/models/today.dart';

/// Reads the owner's day and runs the calls it carries.
abstract class TodayRepository {
  Future<TodayView> fetchToday();

  /// Runs one of the view's calls (a task's done, skip or undo).
  Future<void> run(TodayAction action);
}

class TodayException implements Exception {
  TodayException(this.message);

  final String message;

  @override
  String toString() => message;
}
