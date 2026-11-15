import 'package:voice_agent/core/home_widget/home_widget_numbers.dart';

/// The home-screen widget (ADR-PLATFORM-015): the app hands it the numbers
/// and it redraws. Used by the foreground (every read of the day) and by the
/// WorkManager job, so it holds no state of its own.
abstract class HomeWidgetPort {
  /// Saves [numbers] for the widget and redraws every placed instance.
  Future<void> show(HomeWidgetNumbers numbers);

  /// Whether the owner has the widget on a home screen. The background job
  /// reads nothing when not.
  Future<bool> isPlaced();
}

/// Where there is no widget (iOS, tests): nothing is shown.
class NoHomeWidget implements HomeWidgetPort {
  const NoHomeWidget();

  @override
  Future<void> show(HomeWidgetNumbers numbers) async {}

  @override
  Future<bool> isPlaced() async => false;
}
