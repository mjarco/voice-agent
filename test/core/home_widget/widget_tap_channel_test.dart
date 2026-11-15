import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/home_widget/widget_tap_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('test/widget_tap');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void answer(Future<Object?> Function(MethodCall) handler) =>
      messenger.setMockMethodCallHandler(channel, handler);

  Future<void> fromNative(String method, Object? arguments) async {
    final message = const StandardMethodCodec().encodeMethodCall(
      MethodCall(method, arguments),
    );
    await messenger.handlePlatformMessage(channel.name, message, (_) {});
  }

  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('takes the tap that launched the app', () async {
    answer((call) async {
      expect(call.method, 'takeInitialTap');
      return 'listen';
    });

    expect(await WidgetTapChannel(channel: channel).takeInitialTap(),
        WidgetTap.listen);
  });

  test('a launch without a tap, or with an unknown one, gives nothing',
      () async {
    answer((_) async => null);
    expect(await WidgetTapChannel(channel: channel).takeInitialTap(), isNull);
    answer((_) async => 'settings');
    expect(await WidgetTapChannel(channel: channel).takeInitialTap(), isNull);
  });

  test('later taps arrive on the stream; unknown ones are dropped', () async {
    answer((_) async => null);
    final taps = WidgetTapChannel(channel: channel);
    await taps.takeInitialTap();

    final got = taps.taps.take(3).toList();
    await fromNative('tapped', 'food');
    await fromNative('tapped', 'junk');
    await fromNative('tapped', 'matters');
    await fromNative('tapped', 'tasks');

    expect(await got, [WidgetTap.food, WidgetTap.matters, WidgetTap.tasks]);
  });

  test('off Android the platform is not asked', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    var asked = false;
    answer((_) async {
      asked = true;
      return 'food';
    });

    expect(await WidgetTapChannel(channel: channel).takeInitialTap(), isNull);
    expect(asked, isFalse);
  });
}
