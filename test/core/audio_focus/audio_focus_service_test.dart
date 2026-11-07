import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/audio_focus/audio_focus_port.dart';
import 'package:voice_agent/core/audio_focus/audio_focus_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const methodChannel = MethodChannel('com.voiceagent/audio_focus');
  const eventChannel = EventChannel('com.voiceagent/audio_focus/events');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<String> calls;
  late Object? Function(MethodCall) answer;
  late AudioFocusService service;

  setUp(() {
    calls = [];
    answer = (_) => null;
    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      calls.add(call.method);
      return answer(call);
    });
    service = AudioFocusService(
      methodChannel: methodChannel,
      eventChannel: eventChannel,
    );
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(methodChannel, null);
    messenger.setMockStreamHandler(eventChannel, null);
  });

  test('request returns what the platform granted', () async {
    answer = (_) => true;
    expect(await service.request(), isTrue);
    answer = (_) => false;
    expect(await service.request(), isFalse);
    expect(calls, ['request', 'request']);
  });

  test('a failing request counts as refused', () async {
    answer = (_) => throw PlatformException(code: 'x');
    expect(await service.request(), isFalse);
  });

  test('a missing platform handler counts as refused', () async {
    messenger.setMockMethodCallHandler(methodChannel, null);
    expect(await service.request(), isFalse);
    await expectLater(service.abandon(), completes);
  });

  test('abandon is sent to the platform', () async {
    await service.abandon();
    expect(calls, ['abandon']);
  });

  test('the losses map to AudioFocusLoss, unknown ones are dropped',
      () async {
    messenger.setMockStreamHandler(
      eventChannel,
      MockStreamHandler.inline(onListen: (arguments, events) {
        events.success('loss');
        events.success('gain');
        events.success('lossTransient');
        events.success('lossTransientCanDuck');
        events.endOfStream();
      }),
    );

    expect(await service.losses.toList(), [
      AudioFocusLoss.permanent,
      AudioFocusLoss.transient,
      AudioFocusLoss.mayDuck,
    ]);
  });

  test('without a focus of ours it is always granted and never lost',
      () async {
    const none = NoAudioFocus();
    expect(await none.request(), isTrue);
    await none.abandon();
    expect(await none.losses.toList(), isEmpty);
  });
}
