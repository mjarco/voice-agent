import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/links/link_opener.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UrlLauncherLinkOpener', () {
    final calls = <MethodCall>[];

    setUp(() {
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/url_launcher_android'),
        (call) async {
          calls.add(call);
          return true;
        },
      );
    });

    for (final link in [
      'javascript:alert(1)',
      'intent://scan/#Intent;scheme=zxing;end',
      'file:///sdcard/x.html',
      '#notes',
    ]) {
      test('does not hand "$link" to the launcher', () async {
        final opened = await const UrlLauncherLinkOpener().open(Uri.parse(link));

        expect(opened, isFalse);
        expect(calls, isEmpty);
      });
    }
  });

  group('isOpenableLink', () {
    test('takes web and mail links', () {
      expect(isOpenableLink(Uri.parse('https://go.dev')), isTrue);
      expect(isOpenableLink(Uri.parse('HTTP://example.org')), isTrue);
      expect(isOpenableLink(Uri.parse('mailto:a@example.org')), isTrue);
    });

    test('refuses everything else', () {
      expect(isOpenableLink(Uri.parse('javascript:alert(1)')), isFalse);
      expect(isOpenableLink(Uri.parse('tel:123')), isFalse);
      expect(isOpenableLink(Uri.parse('example.org')), isFalse);
    });
  });
}
