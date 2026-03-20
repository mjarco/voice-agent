import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:voice_agent/core/tts/flutter_tts_service.dart';

// ── Mock ─────────────────────────────────────────────────────────────────────

class _MockFlutterTts implements FlutterTts {
  final List<String> setLanguageCalls = [];
  final List<String> speakCalls = [];
  int stopCount = 0;

  @override
  Future<dynamic> setLanguage(String language) async {
    setLanguageCalls.add(language);
    return 1;
  }

  @override
  Future<dynamic> speak(String text, {bool focus = true}) async {
    speakCalls.add(text);
    return 1;
  }

  @override
  Future<dynamic> stop() async {
    stopCount++;
    return 1;
  }

  // Unused FlutterTts members — not needed for these tests.
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('FlutterTtsService', () {
    test('speak() with explicit languageCode calls setLanguage with that code', () async {
      final mock = _MockFlutterTts();
      final svc = FlutterTtsService(tts: mock);

      await svc.speak('Hello', languageCode: 'pl');

      expect(mock.setLanguageCalls, ['pl']);
      expect(mock.speakCalls, ['Hello']);
    });

    test('speak() with "auto" calls setLanguage with full Platform.localeName, not "auto"',
        () async {
      final mock = _MockFlutterTts();
      final svc = FlutterTtsService(tts: mock);

      await svc.speak('Cześć', languageCode: 'auto');

      expect(mock.setLanguageCalls, hasLength(1));
      final lang = mock.setLanguageCalls.first;
      expect(lang, isNot('auto'));
      // Full locale: at minimum two chars separated by _ or just the locale.
      expect(lang, equals(Platform.localeName));
    });

    test('speak() with null languageCode also uses Platform.localeName', () async {
      final mock = _MockFlutterTts();
      final svc = FlutterTtsService(tts: mock);

      await svc.speak('Hi');

      expect(mock.setLanguageCalls, [Platform.localeName]);
    });

    test('stop() delegates to FlutterTts.stop()', () async {
      final mock = _MockFlutterTts();
      final svc = FlutterTtsService(tts: mock);

      await svc.stop();

      expect(mock.stopCount, 1);
    });
  });
}
