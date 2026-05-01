import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:voice_agent/core/background/background_service.dart';

/// [BackgroundService] implementation using `flutter_foreground_task` (Android)
/// and AVAudioSession category switching (iOS) via platform channel.
///
/// The foreground service is purely a keepalive — no `TaskHandler` or send-port
/// communication is used (see ADR-PLATFORM-005). Start/stop is driven by
/// `HandsFreeController` at session boundaries (see ADR-PLATFORM-006).
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
        channelDescription: 'Keeps recording active when the app is in the background',
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
        notificationText: 'Starting...',
        serviceTypes: [
          ForegroundServiceTypes.microphone,
          // P028: required so flutter_tts.speak() can play through the
          // speaker while the service is running on Android 14+.
          ForegroundServiceTypes.mediaPlayback,
        ],
      );
    }

    if (Platform.isIOS) {
      try {
        await _audioSessionChannel.invokeMethod('setPlayAndRecord');
      } on PlatformException {
        // Audio session switch failed — continue anyway, background may
        // not persist but foreground still works
      } on MissingPluginException {
        // AudioSessionBridge not registered (e.g. iOS plugin wiring changed).
        // Proceed so foreground VAD still works; background recording may not
        // survive screen lock until the bridge is re-registered.
      }
    }

    _running = true;
  }

  @override
  Future<void> stopService({
    AudioSessionTarget target = AudioSessionTarget.playback,
  }) async {
    if (!_running) return;

    if (Platform.isAndroid) {
      await FlutterForegroundTask.stopService();
    }

    if (Platform.isIOS) {
      // P037 v2: by default, when leaving the engaged listening state we
      // switch to `.playback` (not `.ambient`). The app keeps the media
      // participant slot so AirPods short-click reaches its
      // MPRemoteCommandCenter targets — required for tap-to-engage.
      // Callers that want the pre-P037 "fully yield to other apps" behaviour
      // can opt into [AudioSessionTarget.ambient].
      final method = switch (target) {
        AudioSessionTarget.playback => 'setPlaybackOnly',
        AudioSessionTarget.ambient => 'setAmbient',
      };
      try {
        await _audioSessionChannel.invokeMethod(method);
      } on PlatformException {
        // Audio session revert failed — non-critical
      } on MissingPluginException {
        // Bridge not registered — nothing to revert.
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
