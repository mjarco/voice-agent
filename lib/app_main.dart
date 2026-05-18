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

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/app/app.dart';
import 'package:voice_agent/app/background/register_agenda_refresh.dart';
import 'package:voice_agent/app/background/wire_agenda_for_background.dart';
import 'package:voice_agent/core/background/flutter_foreground_task_service.dart';
import 'package:voice_agent/core/background/workmanager_core_boot.dart';
import 'package:voice_agent/core/config/app_config_provider.dart';
import 'package:voice_agent/core/notifications/data/local_notification_service.dart';
import 'package:voice_agent/core/notifications/notification_providers.dart';
import 'package:voice_agent/core/providers/api_client_provider.dart';
import 'package:voice_agent/core/providers/deep_link_providers.dart';
import 'package:voice_agent/core/session_control/session_control_provider.dart';
import 'package:voice_agent/core/session_control/toaster.dart';
import 'package:voice_agent/core/storage/storage_provider.dart';
import 'package:voice_agent/core/storage/storage_service.dart';
import 'package:voice_agent/features/agenda/presentation/agenda_providers.dart';
import 'package:voice_agent/features/recording/presentation/recording_providers.dart';

/// Optional hook for the dev flavor to wire telemetry between the
/// storage init and `runApp`. The hook receives the live
/// [StorageService] (which the dev-flavor telemetry's durable
/// processor needs) and is awaited before any subsequent boot step,
/// so the very first telemetry event lands before any other layer
/// starts emitting.
typedef AfterStorageInit = Future<void> Function(StorageService storage);

Future<void> appMain({AfterStorageInit? afterStorageInit}) async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterForegroundTaskService.initForegroundTask();

  // P040: single source of truth for core dep construction. Both this
  // foreground path and the workmanager bg isolate call coreBoot() and
  // wireAgendaForBackground(). See ADR-PLATFORM-007.
  final core = await coreBoot();
  final agenda = wireAgendaForBackground(core);

  // P039 T4b — dev-flavor entrypoint hooks in here to boot the durable
  // telemetry pipeline once the storage layer is up. No-op on the
  // stable flavor (hook is null).
  if (afterStorageInit != null) {
    await afterStorageInit(core.storage);
  }

  // Read the cold-start deep-link payload BEFORE runApp, per ADR-PLATFORM-008.
  // The plugin discards this after the warm-path callback is registered, so
  // ordering is critical: read first, callback registered inside `init()`
  // which already happened in coreBoot().
  final cold = await _readColdStartDeepLink();

  // Prompt for notification permission once. Idempotent on subsequent
  // launches — OS handles the "already resolved" case. Fire-and-forget; the
  // reconciler short-circuits gracefully if the user denies.
  unawaited(core.notifications.requestPermission());

  // Register the periodic agenda-refresh task. Idempotent (KEEP policy).
  // Per ADR-NET-002 P040 amendment.
  //
  // Best-effort: on iOS Simulator (and on physical iOS without
  // `BGTaskSchedulerPermittedIdentifiers` in Info.plist) workmanager throws
  // `unhandledMethod("registerPeriodicTask")`. Background agenda refresh
  // simply will not run there — that's the expected platform behaviour. Boot
  // must not depend on it.
  try {
    await registerAgendaRefresh();
  } catch (e, st) {
    if (kDebugMode) {
      debugPrint('registerAgendaRefresh failed (continuing): $e\n$st');
    }
  }

  final recovered = await core.storage.recoverStaleSending();
  if (kDebugMode && recovered > 0) {
    debugPrint('Recovered $recovered stale sending items');
  }

  final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

  // Expose the tap stream of LocalNotificationService through the canonical
  // provider in core/providers/ (per ADR-ARCH-008). Cast is safe at this
  // point — `core.notifications` is always a `LocalNotificationService` in
  // production (overridable in tests).
  final tapStream =
      (core.notifications as LocalNotificationService).tapStream;

  runApp(
    ProviderScope(
      overrides: [
        // Core bundle — injected so widget-tree providers see the same
        // instances coreBoot() built (parity with the bg isolate path).
        storageServiceProvider.overrideWithValue(core.storage),
        appConfigServiceProvider.overrideWithValue(core.configService),
        apiClientProvider.overrideWithValue(core.api),
        notificationServiceProvider.overrideWithValue(core.notifications),

        // Agenda feature wiring — same instance as the bg isolate will use.
        agendaRepositoryProvider.overrideWithValue(agenda.repository),
        agendaNotificationSchedulerProvider
            .overrideWithValue(agenda.scheduler),

        // Deep-link channels (ADR-PLATFORM-008).
        pendingDeepLinkProvider.overrideWith((ref) => cold),
        notificationTapStreamProvider
            .overrideWith((ref) => tapStream),

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

Future<String?> _readColdStartDeepLink() async {
  try {
    final details = await FlutterLocalNotificationsPlugin()
        .getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp != true) return null;
    return details!.notificationResponse?.payload;
  } catch (_) {
    return null;
  }
}

