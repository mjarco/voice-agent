import 'package:flutter/foundation.dart';
import 'package:voice_agent/app/background/agenda_refresh_entrypoint.dart';
import 'package:workmanager/workmanager.dart';

/// Registers the workmanager periodic agenda-refresh task. Called once from
/// `app_main.dart` foreground init. Idempotent via `ExistingWorkPolicy.keep`.
///
/// Authorization: ADR-NET-002 P040 amendment (narrow workmanager carve-out
/// limited to agenda reconciliation).
Future<void> registerAgendaRefresh() async {
  await Workmanager().initialize(
    agendaRefreshDispatcher,
    isInDebugMode: kDebugMode,
  );

  await Workmanager().registerPeriodicTask(
    'agenda-refresh',
    agendaRefreshTaskName,
    frequency: const Duration(hours: 1),
    constraints: Constraints(
      networkType: NetworkType.connected,
    ),
    existingWorkPolicy: ExistingWorkPolicy.keep,
  );
}
