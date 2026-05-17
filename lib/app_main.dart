// Shared boot used by both flavor entrypoints.
//
// `lib/main_dev.dart` wires `Telemetry.instance` to the OTel-backed
// implementation and then calls `appMain()`. `lib/main_stable.dart`
// (and the default `lib/main.dart`) call `appMain()` directly,
// leaving the no-op default.
//
// See ADR-OBS-001 §2.
//
// Boot path (P040): `coreBoot()` constructs the core dep graph;
// `wireAgendaForBackground()` composes feature deps over it. Both helpers
// are also called by the workmanager background isolate entrypoint
// (see ADR-PLATFORM-007 — parity gate).

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/app/app.dart';
import 'package:voice_agent/app/background/register_agenda_refresh.dart';
import 'package:voice_agent/app/background/wire_agenda_for_background.dart';
import 'package:voice_agent/core/background/flutter_foreground_task_service.dart';
import 'package:voice_agent/core/background/workmanager_core_boot.dart';
import 'package:voice_agent/core/config/app_config_provider.dart';
import 'package:voice_agent/core/notifications/come_back_notifier.dart';
import 'package:voice_agent/core/notifications/agenda_notification_scheduler.dart';
import 'package:voice_agent/core/notifications/domain/notification_service.dart';
import 'package:voice_agent/core/notifications/notification_providers.dart';
import 'package:voice_agent/core/providers/api_client_provider.dart';
import 'package:voice_agent/core/session_control/session_control_provider.dart';
import 'package:voice_agent/core/session_control/toaster.dart';
import 'package:voice_agent/core/storage/storage_provider.dart';
import 'package:voice_agent/features/agenda/domain/agenda_repository.dart';
import 'package:voice_agent/features/agenda/presentation/agenda_providers.dart';
import 'package:voice_agent/features/recording/presentation/recording_providers.dart';

Future<void> appMain() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterForegroundTaskService.initForegroundTask();

  // PoC come-back-notification is being superseded by P040; init kept for
  // backward compat during T2 — removed entirely in T3 along with the
  // lifecycle hook in app.dart.
  await ComeBackNotifier.instance.init();

  // P040: single source of truth for core dep construction. Both this
  // foreground path and the workmanager bg isolate call coreBoot() and
  // wireAgendaForBackground(). See ADR-PLATFORM-007.
  final core = await coreBoot();
  final agenda = wireAgendaForBackground(core);

  // Register the periodic agenda-refresh task. Idempotent (KEEP policy).
  // Per ADR-NET-002 P040 amendment.
  await registerAgendaRefresh();

  final recovered = await core.storage.recoverStaleSending();
  if (kDebugMode && recovered > 0) {
    debugPrint('Recovered $recovered stale sending items');
  }

  final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

  runApp(
    ProviderScope(
      overrides: [
        // Core bundle — injected so widget-tree providers see the same
        // instances coreBoot() built (parity with the bg isolate path).
        // The appConfigProvider notifier picks up the overridden service
        // and re-loads from the same SharedPreferences instance (cached),
        // so AppConfig state converges to the same values core.config holds.
        storageServiceProvider.overrideWithValue(core.storage),
        appConfigServiceProvider.overrideWithValue(core.configService),
        apiClientProvider.overrideWithValue(core.api),
        notificationServiceProvider.overrideWithValue(core.notifications),

        // Agenda feature wiring — same instance as the bg isolate will use.
        agendaRepositoryProvider.overrideWithValue(agenda.repository),
        agendaNotificationSchedulerProvider
            .overrideWithValue(agenda.scheduler),

        // Pre-existing overrides (unchanged from before P040).
        toasterProvider.overrideWithValue(Toaster(scaffoldMessengerKey)),
        handsFreeControlPortProvider.overrideWith(
          (ref) => ref.watch(handsFreeControllerProvider.notifier),
        ),
      ],
      child: App(scaffoldMessengerKey: scaffoldMessengerKey),
    ),
  );
}

// Compile-time type assertion for the override above — keeps the override
// list type-checked against the agenda scheduler shape.
// ignore: unused_element
void _assertSchedulerType(AgendaNotificationScheduler s) {}
// ignore: unused_element
void _assertAgendaRepoType(AgendaRepository r) {}
// ignore: unused_element
void _assertNotificationServiceType(NotificationService n) {}
