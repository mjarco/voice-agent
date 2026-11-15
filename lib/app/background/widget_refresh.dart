import 'package:voice_agent/core/background/workmanager_core_boot.dart';
import 'package:voice_agent/core/home_widget/home_widget_numbers.dart';
import 'package:voice_agent/core/home_widget/home_widget_port.dart';
import 'package:voice_agent/core/home_widget/home_widget_service.dart';
import 'package:voice_agent/features/today/data/api_today_repository.dart';
import 'package:voice_agent/features/today/domain/today_repository.dart';
import 'package:workmanager/workmanager.dart';

/// Task name of the periodic read for the home-screen widget
/// (ADR-PLATFORM-015).
const String widgetRefreshTaskName = 'widgetRefresh';

/// Android's shortest period for periodic work.
const Duration widgetRefreshPeriod = Duration(minutes: 15);

/// Registers the periodic widget read. Called after `Workmanager().initialize`
/// (`registerAgendaRefresh`), whose dispatcher runs both tasks. Idempotent.
Future<void> registerWidgetRefresh() async {
  await Workmanager().registerPeriodicTask(
    'widget-refresh',
    widgetRefreshTaskName,
    frequency: widgetRefreshPeriod,
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
  );
}

/// One background read: the today view, drawn on the widget. Reads nothing
/// when no widget is placed. Throws when the read fails, so WorkManager
/// retries with backoff.
Future<void> refreshWidget({
  required HomeWidgetPort widget,
  required TodayRepository repository,
  DateTime Function() clock = DateTime.now,
}) async {
  if (!await widget.isPlaced()) return;
  final view = await repository.fetchToday();
  await widget.show(HomeWidgetNumbers.of(view, clock()));
}

/// The task as the WorkManager isolate runs it, over [coreBoot]'s client.
Future<void> refreshWidgetInBackground(CoreBootBundle core) => refreshWidget(
      widget: const HomeWidgetService(),
      repository: ApiTodayRepository(core.api),
    );
