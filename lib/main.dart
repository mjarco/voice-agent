import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/app/app.dart';
import 'package:voice_agent/core/background/flutter_foreground_task_service.dart';
import 'package:voice_agent/core/notifications/come_back_notifier.dart';
import 'package:voice_agent/core/session_control/session_control_provider.dart';
import 'package:voice_agent/core/session_control/toaster.dart';
import 'package:voice_agent/core/storage/sqlite_storage_service.dart';
import 'package:voice_agent/core/storage/storage_provider.dart';
import 'package:voice_agent/features/recording/presentation/recording_providers.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterForegroundTaskService.initForegroundTask();

  await ComeBackNotifier.instance.init();

  final storage = await SqliteStorageService.initialize();

  final recovered = await storage.recoverStaleSending();
  if (kDebugMode && recovered > 0) {
    debugPrint('Recovered $recovered stale sending items');
  }

  final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

  runApp(
    ProviderScope(
      overrides: [
        storageServiceProvider.overrideWithValue(storage),
        toasterProvider.overrideWithValue(Toaster(scaffoldMessengerKey)),
        handsFreeControlPortProvider.overrideWith(
          (ref) => ref.watch(handsFreeControllerProvider.notifier),
        ),
      ],
      child: App(scaffoldMessengerKey: scaffoldMessengerKey),
    ),
  );
}
