import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/share/shared_text_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('test/share');
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

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  group('SharedTextChannel', () {
    test('takes the text that launched the app', () async {
      answer((call) async {
        expect(call.method, 'takeInitialText');
        return 'shared';
      });

      expect(await SharedTextChannel(channel: channel).takeInitialText(),
          'shared');
    });

    test('a failed read gives nothing and opens the warm path', () async {
      answer((_) async => throw PlatformException(code: 'broken'));
      final share = SharedTextChannel(channel: channel);

      expect(await share.takeInitialText(), isNull);

      final next = share.texts.first;
      await fromNative('sharedText', 'later');
      expect((await next).text, 'later');
    });

    test('no handler on the platform gives nothing', () async {
      expect(await SharedTextChannel(channel: channel).takeInitialText(),
          isNull);
    });

    test('a share before anyone listens waits', () async {
      answer((_) async => null);
      final share = SharedTextChannel(channel: channel);
      await share.takeInitialText();

      await fromNative('sharedText', 'early');

      expect((await share.texts.first).text, 'early');
    });

    test('off Android the platform is not asked', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      var asked = false;
      answer((_) async {
        asked = true;
        return 'shared';
      });

      final text = await SharedTextChannel(channel: channel).takeInitialText();
      debugDefaultTargetPlatformOverride = null;

      expect(text, isNull);
      expect(asked, isFalse);
    });
  });
}
