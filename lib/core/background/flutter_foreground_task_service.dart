import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:voice_agent/core/background/background_service.dart';

/// [BackgroundService] implementation using `flutter_foreground_task` (Android)
/// and AVAudioSession category switching (iOS) via platform channel.
///
/// The foreground service is purely a keepalive — no [TaskHandler] or send-port
/// communication is used (see ADR-PLATFORM-005).
class FlutterForegroundTaskService implements BackgroundService {
  FlutterForegroundTaskService({MethodChannel? audioSessionChannel})
      : _audioSessionChannel = audioSessionChannel ??
            const MethodChannel('com.voiceagent/audio_session');

  final MethodChannel _audioSessionChannel;
  bool _running = false;

  @override
  bool get isRunning => _running;

  /// Call once before [startService], typically in `main()` before `runApp()`.
  static void initForegroundTask() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'voice_agent_background',
        channelName: 'Voice Agent Background',
        channelDescription: 'Background listening for wake word detection',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );
  }

  @override
  Future<void> startService() async {
    if (_running) return;

    if (Platform.isAndroid) {
      await FlutterForegroundTask.startService(
        serviceId: 1,
        notificationTitle: 'Voice Agent',
        notificationText: 'Listening for wake word...',
        serviceTypes: [ForegroundServiceTypes.microphone],
      );
    }

    if (Platform.isIOS) {
      try {
        await _audioSessionChannel.invokeMethod('setPlayAndRecord');
      } on PlatformException {
        // Audio session switch failed — continue anyway, background may
        // not persist but foreground still works
      }
    }

    _running = true;
  }

  @override
  Future<void> stopService() async {
    if (!_running) return;

    if (Platform.isAndroid) {
      await FlutterForegroundTask.stopService();
    }

    if (Platform.isIOS) {
      try {
        await _audioSessionChannel.invokeMethod('setAmbient');
      } on PlatformException {
        // Audio session revert failed — non-critical
      }
    }

    _running = false;
  }

  @override
  Future<void> updateNotification({
    required String title,
    required String body,
  }) async {
    if (!_running) return;
    if (Platform.isAndroid) {
      await FlutterForegroundTask.updateService(
        notificationTitle: title,
        notificationText: body,
      );
    }
  }
}
