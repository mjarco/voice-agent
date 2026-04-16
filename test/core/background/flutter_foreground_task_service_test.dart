import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
