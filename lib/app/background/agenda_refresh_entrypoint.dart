import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:voice_agent/app/background/wire_agenda_for_background.dart';
import 'package:voice_agent/core/background/workmanager_core_boot.dart';
import 'package:workmanager/workmanager.dart';

/// Unique task name for the periodic agenda-refresh task.
const String agendaRefreshTaskName = 'agendaRefresh';

/// Minimum interval between bg runs to avoid redundant work when the
/// foreground has recently refreshed. See ADR-NET-002 P040 amendment.
const Duration _bgSkipIfRecentThan = Duration(minutes: 50);

/// Workmanager isolate entrypoint. Must be a top-level function annotated
/// with `@pragma('vm:entry-point')` so tree-shaking does not remove it
/// (the isolate spawns into the entrypoint without going through main()).
///
/// Construction follows ADR-PLATFORM-007: `coreBoot()` for core deps,
/// `wireAgendaForBackground()` for feature deps. No `ProviderContainer`.
@pragma('vm:entry-point')
void agendaRefreshDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task != agendaRefreshTaskName) {
      return Future.value(true);
    }

    try {
      WidgetsFlutterBinding.ensureInitialized();

      final core = await coreBoot();
      final agenda = wireAgendaForBackground(core);

      // Skip if foreground recently refreshed — saves a network round trip
      // and avoids redundant OS notification queue churn.
      final last = await core.configService.getLastAgendaFetchAt();
      final now = DateTime.now();
      if (last != null && now.difference(last) < _bgSkipIfRecentThan) {
        return true;
      }

      final today = _today();
      final response = await agenda.repository.fetchAgenda(today);
      await agenda.scheduler.reconcile(response, sessionActive: false);
      await core.configService.setLastAgendaFetchAt(now);
      return true;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[agendaRefreshDispatcher] failed: $e\n$st');
      }
      // Returning false signals workmanager to retry with backoff.
      return false;
    }
  });
}

String _today() {
  final now = DateTime.now();
  final y = now.year.toString().padLeft(4, '0');
  final m = now.month.toString().padLeft(2, '0');
  final d = now.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}
