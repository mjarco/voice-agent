import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/background/background_service.dart';
import 'package:voice_agent/core/background/flutter_foreground_task_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FlutterForegroundTaskService', () {
    late FlutterForegroundTaskService service;
    late MethodChannel audioSessionChannel;
    final List<MethodCall> audioSessionCalls = [];

    setUp(() {
      audioSessionCalls.clear();
      audioSessionChannel = const MethodChannel('com.voiceagent/audio_session');

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(audioSessionChannel, (call) async {
        audioSessionCalls.add(call);
        return null;
      });

      service = FlutterForegroundTaskService(
        audioSessionChannel: audioSessionChannel,
      );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(audioSessionChannel, null);
    });

    test('isRunning is false initially', () {
      expect(service.isRunning, isFalse);
    });

    test('startService sets isRunning to true', () async {
      await service.startService();
      expect(service.isRunning, isTrue);
    });

    test('stopService sets isRunning to false', () async {
      await service.startService();
      await service.stopService();
      expect(service.isRunning, isFalse);
    });

    test('startService is idempotent when already running', () async {
      await service.startService();
      await service.startService();
      expect(service.isRunning, isTrue);
      // Only one set of platform calls should have been made
    });

    test('stopService is idempotent when not running', () async {
      await service.stopService();
      expect(service.isRunning, isFalse);
      expect(audioSessionCalls, isEmpty);
    });

    test('updateNotification is no-op when not running', () async {
      // Should not throw
      await service.updateNotification(
        title: 'Test',
        body: 'Test body',
      );
    });
  });

  group('ADR-AUDIO-015', () {
    test('the plugin option stopWithTask is left unset', () {
      // Set, it would stop the service whenever no activity is resumed.
      expect(
        FlutterForegroundTaskService.foregroundTaskOptions.stopWithTask,
        isNull,
      );
    });

    test('the manifest makes a swipe from recents stop the service', () {
      final manifest =
          File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      final service = RegExp(
        r'<service\s[^>]*flutter_foreground_task\.service\.ForegroundService[^>]*>',
      ).firstMatch(manifest)?.group(0);
      expect(service, isNotNull);
      expect(service, contains('android:stopWithTask="true"'));
    });

    test('the buttons reach the plugin with their ids and texts', () {
      final buttons = FlutterForegroundTaskService.pluginButtons(const [
        ServiceNotificationButton(id: 'pause', text: 'Pause'),
        ServiceNotificationButton(id: 'stop', text: 'Stop'),
      ]);
      expect(
        [for (final b in buttons) '${b.id}/${b.text}'],
        ['pause/Pause', 'stop/Stop'],
      );
    });
  });
}
