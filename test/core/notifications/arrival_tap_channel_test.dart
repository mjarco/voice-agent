import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/notifications/arrival_tap_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('arrivalRoute', () {
    test('lets through the route personal-agent arms', () {
      expect(arrivalRoute('/shopping?store=diy,garden'),
          '/shopping?store=diy,garden');
      expect(arrivalRoute('/shopping?store=home_garden'),
          '/shopping?store=home_garden');
    });

    test('drops store ids of another shape, and repeats', () {
      expect(arrivalRoute('/shopping?store=diy,DROP%20TABLE,,diy,garden'),
          '/shopping?store=diy,garden');
      expect(arrivalRoute('/shopping?store=%2Fagenda'), '/shopping');
      expect(arrivalRoute('/shopping'), '/shopping');
    });

    test('any other route, junk or none opens the start screen', () {
      for (final open in [
        '',
        '/agenda',
        '/settings/advanced',
        '/shopping/x',
        'https://example.com/shopping?store=diy',
        '//evil/shopping',
        'shopping?store=diy',
        '%%%',
      ]) {
        expect(arrivalRoute(open), arrivalStartRoute, reason: open);
      }
      expect(arrivalStartRoute, '/record');
    });

    test('no tap is null', () {
      expect(arrivalRoute(null), isNull);
    });
  });

  group('ArrivalTapChannel', () {
    const channel = MethodChannel('test/arrival_tap');
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

    test('takes the checked route of the tap that launched the app', () async {
      answer((call) async {
        expect(call.method, 'takeInitialRoute');
        return '/shopping?store=diy';
      });

      expect(await ArrivalTapChannel(channel: channel).takeInitialRoute(),
          '/shopping?store=diy');
    });

    test('a launch route it may not open gives the start screen', () async {
      answer((_) async => '/settings');

      expect(await ArrivalTapChannel(channel: channel).takeInitialRoute(),
          arrivalStartRoute);
    });

    test('a launch with no tap gives nothing', () async {
      answer((_) async => null);

      expect(await ArrivalTapChannel(channel: channel).takeInitialRoute(),
          isNull);
    });

    test('later taps arrive on the stream, checked, after the cold read',
        () async {
      answer((_) async => null);
      final taps = ArrivalTapChannel(channel: channel);
      expect(await taps.takeInitialRoute(), isNull);

      final routes = taps.routes.take(3).toList();
      await fromNative('tapped', '/shopping?store=grocery');
      await fromNative('tapped', '/agenda');
      await fromNative('tapped', null);

      expect(await routes, ['/shopping?store=grocery', '/record', '/record']);
    });

    test('no handler on the platform gives nothing', () async {
      expect(await ArrivalTapChannel(channel: channel).takeInitialRoute(),
          isNull);
    });

    test('off Android the platform is not asked', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      var asked = false;
      answer((_) async {
        asked = true;
        return '/shopping';
      });

      expect(await ArrivalTapChannel(channel: channel).takeInitialRoute(),
          isNull);
      expect(asked, isFalse);
    });
  });
}
