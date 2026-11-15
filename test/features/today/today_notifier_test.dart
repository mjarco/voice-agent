import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/home_widget/home_widget_numbers.dart';
import 'package:voice_agent/core/home_widget/home_widget_port.dart';
import 'package:voice_agent/core/home_widget/home_widget_provider.dart';
import 'package:voice_agent/core/models/today.dart';
import 'package:voice_agent/features/today/domain/today_repository.dart';
import 'package:voice_agent/features/today/presentation/today_providers.dart';

class _Widget implements HomeWidgetPort {
  final shown = <HomeWidgetNumbers>[];

  @override
  Future<bool> isPlaced() async => true;

  @override
  Future<void> show(HomeWidgetNumbers numbers) async => shown.add(numbers);
}

class _Repo implements TodayRepository {
  int left = 540;
  bool fails = false;

  @override
  Future<TodayView> fetchToday() async {
    if (fails) throw TodayException('offline');
    return TodayView.fromMap({
      'day': '2026-11-15',
      'food': {'has_target': true, 'left_kcal': left},
      'agenda': {'tasks_open': 1},
      'matters': {'in_progress': 2},
    });
  }

  @override
  Future<void> run(TodayAction action) async {}
}

void main() {
  test('every read of the day redraws the home-screen widget', () async {
    final widget = _Widget();
    final repo = _Repo();
    final container = ProviderContainer(overrides: [
      todayRepositoryProvider.overrideWithValue(repo),
      homeWidgetProvider.overrideWithValue(widget),
    ]);
    addTearDown(container.dispose);

    final notifier = container.read(todayNotifierProvider.notifier);
    await notifier.refresh();
    expect(widget.shown.last.kcal, '540 kcal');

    repo.left = 120;
    await notifier.refresh();
    expect(widget.shown.last.kcal, '120 kcal');
  });

  test('a failed read leaves the widget as it was', () async {
    final widget = _Widget();
    final repo = _Repo()..fails = true;
    final container = ProviderContainer(overrides: [
      todayRepositoryProvider.overrideWithValue(repo),
      homeWidgetProvider.overrideWithValue(widget),
    ]);
    addTearDown(container.dispose);

    await container.read(todayNotifierProvider.notifier).refresh();

    expect(widget.shown, isEmpty);
    expect(container.read(todayNotifierProvider).error, contains('offline'));
  });
}
