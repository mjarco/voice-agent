import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/core/background/background_service.dart';
import 'package:voice_agent/core/background/flutter_foreground_task_service.dart';

final backgroundServiceProvider = Provider<BackgroundService>((ref) {
  final service = FlutterForegroundTaskService();
  ref.onDispose(() async {
    if (service.isRunning) {
      await service.stopService();
    }
  });
  return service;
});
