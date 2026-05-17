// This file is the canonical feature-wiring helper for background isolates.
// New feature wiring helpers follow the `wire_<feature>_for_background.dart`
// naming convention (per ADR-PLATFORM-007 Consequences §1) so reviewers can
// locate them by pattern.
//
// App-layer code is allowed to import `features/` per ADR-ARCH-003;
// `core/background/` is not — that is the layer split this file embodies.

import 'package:timezone/timezone.dart' as tz;
import 'package:voice_agent/core/background/workmanager_core_boot.dart';
import 'package:voice_agent/core/notifications/agenda_notification_scheduler.dart';
import 'package:voice_agent/features/agenda/data/api_agenda_repository.dart';
import 'package:voice_agent/features/agenda/domain/agenda_repository.dart';

class AgendaBackgroundBundle {
  AgendaBackgroundBundle({
    required this.repository,
    required this.scheduler,
  });

  final AgendaRepository repository;
  final AgendaNotificationScheduler scheduler;
}

/// Composes agenda feature dependencies over a [CoreBootBundle].
/// Used by both the foreground init and the workmanager isolate entrypoint
/// to guarantee parity (see ADR-PLATFORM-007 — parity-gate test).
AgendaBackgroundBundle wireAgendaForBackground(CoreBootBundle core) {
  final repository = ApiAgendaRepository(core.api);
  final scheduler = AgendaNotificationScheduler(
    service: core.notifications,
    location: tz.local,
    clock: DateTime.now,
  );
  return AgendaBackgroundBundle(
    repository: repository,
    scheduler: scheduler,
  );
}
