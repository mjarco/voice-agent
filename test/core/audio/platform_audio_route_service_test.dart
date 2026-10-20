import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/audio/audio_route_service.dart';
import 'package:voice_agent/core/audio/platform_audio_route_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = EventChannel('test/route_changes');
  const methodChannel = MethodChannel('test/route_changes');

  group('PlatformAudioRouteService', () {
    late List<String> calls;

    setUp(() {
      calls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, (call) async {
        calls.add(call.method);
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, null);
    });

    test('off iOS the stream is empty and the channel is never listened to',
        () async {
      final svc =
          PlatformAudioRouteService(eventChannel: channel, isIOS: false);

      final events = await svc.changes.toList();

      expect(events, isEmpty);
      expect(calls, isEmpty);
    });

    test('on iOS the channel is listened to', () async {
      final svc = PlatformAudioRouteService(eventChannel: channel, isIOS: true);

      final sub = svc.changes.listen((AudioRouteChange _) {});
      await pumpEventQueue();
      await sub.cancel();

      expect(calls, contains('listen'));
    });
  });
}
