import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/app/background/widget_refresh.dart';
import 'package:voice_agent/core/home_widget/home_widget_numbers.dart';
import 'package:voice_agent/core/home_widget/home_widget_port.dart';
import 'package:voice_agent/core/models/today.dart';
import 'package:voice_agent/features/today/domain/today_repository.dart';

class _Widget implements HomeWidgetPort {
  _Widget({required this.placed});

  final bool placed;
  final shown = <HomeWidgetNumbers>[];

  @override
  Future<bool> isPlaced() async => placed;

  @override
  Future<void> show(HomeWidgetNumbers numbers) async => shown.add(numbers);
}

class _Repo implements TodayRepository {
  _Repo({this.fails = false});

  final bool fails;
  int reads = 0;

  @override
  Future<TodayView> fetchToday() async {
    reads++;
    if (fails) throw TodayException('offline');
    return TodayView.fromMap({
      'day': '2026-11-15',
      'food': {'has_target': true, 'left_kcal': 540, 'warning': 'low'},
      'agenda': {'tasks_open': 2, 'tasks_overdue': 1},
      'matters': {'in_progress': 6},
    });
  }

  @override
  Future<void> run(TodayAction action) async {}
}

void main() {
  test('reads the day and draws it on a placed widget', () async {
    final widget = _Widget(placed: true);
    final repo = _Repo();

    await refreshWidget(
      widget: widget,
      repository: repo,
      clock: () => DateTime(2026, 11, 15, 14, 30),
    );

    expect(repo.reads, 1);
    expect(widget.shown.single.kcal, '540 kcal');
    expect(widget.shown.single.matters, '6 spraw w toku');
    expect(widget.shown.single.updated, '14:30');
  });

  test('with no widget on a home screen nothing is read', () async {
    final widget = _Widget(placed: false);
    final repo = _Repo();

    await refreshWidget(widget: widget, repository: repo);

    expect(repo.reads, 0);
    expect(widget.shown, isEmpty);
  });

  test('a failed read throws, so WorkManager retries, and draws nothing',
      () async {
    final widget = _Widget(placed: true);

    await expectLater(
      refreshWidget(widget: widget, repository: _Repo(fails: true)),
      throwsA(isA<TodayException>()),
    );
    expect(widget.shown, isEmpty);
  });

  test('the period is Android\'s shortest', () {
    expect(widgetRefreshPeriod, const Duration(minutes: 15));
  });
}
