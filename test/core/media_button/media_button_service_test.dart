import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/media_button/media_button_port.dart';
import 'package:voice_agent/core/media_button/media_button_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const methodChannelName = 'com.voiceagent/media_button';
  const eventChannelName = 'com.voiceagent/media_button/events';

  late MethodChannel methodChannel;
  late EventChannel eventChannel;
  late MediaButtonService service;
  late List<MethodCall> methodCalls;

  setUp(() {
    methodCalls = [];
    methodChannel = const MethodChannel(methodChannelName);
    eventChannel = const EventChannel(eventChannelName);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, (call) async {
      methodCalls.add(call);
      return null;
    });

    service = MediaButtonService(
      methodChannel: methodChannel,
      eventChannel: eventChannel,
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, null);
  });

  group('MediaButtonService', () {
    test('activate() sends activate method call to native', () async {
      await service.activate();

      expect(methodCalls, hasLength(1));
      expect(methodCalls.first.method, 'activate');
    });

    test('deactivate() sends deactivate method call to native', () async {
      await service.deactivate();

      expect(methodCalls, hasLength(1));
      expect(methodCalls.first.method, 'deactivate');
    });

    test('activate() then deactivate() sends both method calls', () async {
      await service.activate();
      await service.deactivate();

      expect(methodCalls, hasLength(2));
      expect(methodCalls[0].method, 'activate');
      expect(methodCalls[1].method, 'deactivate');
    });

    test('activate() failure is handled gracefully (no crash)', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, (call) async {
        throw PlatformException(
          code: 'UNAVAILABLE',
          message: 'Media session not available',
        );
      });

      // Should not throw.
      await expectLater(service.activate(), completes);
    });

    test('deactivate() failure is handled gracefully (no crash)', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, (call) async {
        throw PlatformException(
          code: 'UNAVAILABLE',
          message: 'Media session not available',
        );
      });

      // Should not throw.
      await expectLater(service.deactivate(), completes);
    });

    test('events stream maps EventChannel data to MediaButtonEvent', () async {
      // Simulate the native side sending events via the event channel.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(
        eventChannel,
        MockStreamHandler.inline(
          onListen: (arguments, events) {
            events.success('togglePlayPause');
            events.endOfStream();
          },
        ),
      );

      final events = await service.events.toList();

      expect(events, [MediaButtonEvent.togglePlayPause]);

      // Clean up.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(eventChannel, null);
    });

    test('events stream handles unknown event strings', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(
        eventChannel,
        MockStreamHandler.inline(
          onListen: (arguments, events) {
            events.success('unknownEvent');
            events.endOfStream();
          },
        ),
      );

      // Unknown events are dropped (no spurious togglePlayPause).
      final events = await service.events.toList();

      expect(events, isEmpty);

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(eventChannel, null);
    });
  });
}
