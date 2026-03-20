import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:voice_agent/core/tts/flutter_tts_service.dart';

// ── Mock ─────────────────────────────────────────────────────────────────────

class _MockFlutterTts implements FlutterTts {
  final List<String> setLanguageCalls = [];
  final List<String> speakCalls = [];
  final List<Map<String, String>> setVoiceCalls = [];
  int stopCount = 0;

  /// Voices returned by [getVoices]. Override in each test.
  List<dynamic> voiceList = [];

  /// When non-null, [getVoices] throws this.
  Object? getVoicesError;

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

  @override
  Future<dynamic> setVoice(Map<String, String> voice) async {
    setVoiceCalls.add(voice);
    return 1;
  }

  @override
  Future<dynamic> get getVoices async {
    if (getVoicesError != null) throw getVoicesError!;
    return voiceList;
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

  group('FlutterTtsService voice selection (iOS)', () {
    // Helper: build a service with isIOS=true so _bestVoice() is exercised.
    FlutterTtsService _svc(_MockFlutterTts mock) =>
        FlutterTtsService(tts: mock, isIOS: true);

    test('picks premium voice over enhanced and normal', () async {
      final mock = _MockFlutterTts()
        ..voiceList = [
          {'name': 'com.apple.voice.normal.pl-PL.Zosia', 'locale': 'pl-PL'},
          {'name': 'com.apple.voice.enhanced.pl-PL.Ewa', 'locale': 'pl-PL'},
          {'name': 'com.apple.voice.premium.pl-PL.Zosia', 'locale': 'pl-PL'},
        ];
      final svc = _svc(mock);

      await svc.speak('Cześć', languageCode: 'pl');

      expect(mock.setVoiceCalls, hasLength(1));
      expect(mock.setVoiceCalls.first['name'],
          contains('premium'));
    });

    test('picks enhanced when no premium available', () async {
      final mock = _MockFlutterTts()
        ..voiceList = [
          {'name': 'com.apple.voice.normal.pl-PL.Ewa', 'locale': 'pl-PL'},
          {'name': 'com.apple.voice.enhanced.pl-PL.Zosia', 'locale': 'pl-PL'},
        ];
      final svc = _svc(mock);

      await svc.speak('Cześć', languageCode: 'pl');

      expect(mock.setVoiceCalls.first['name'], contains('enhanced'));
    });

    test('picks normal when only normal voices available', () async {
      final mock = _MockFlutterTts()
        ..voiceList = [
          {'name': 'com.apple.ttsbundle.pl-PL-Zosia', 'locale': 'pl-PL'},
        ];
      final svc = _svc(mock);

      await svc.speak('Cześć', languageCode: 'pl');

      expect(mock.setVoiceCalls, hasLength(1));
      expect(mock.setVoiceCalls.first['name'], contains('pl-PL'));
    });

    test('does not call setVoice when no voice matches language', () async {
      final mock = _MockFlutterTts()
        ..voiceList = [
          {'name': 'com.apple.voice.premium.en-US.Zoe', 'locale': 'en-US'},
        ];
      final svc = _svc(mock);

      await svc.speak('Cześć', languageCode: 'pl');

      expect(mock.setVoiceCalls, isEmpty);
    });

    test('does not call setVoice when voice list is empty', () async {
      final mock = _MockFlutterTts()..voiceList = [];
      final svc = _svc(mock);

      await svc.speak('Hello', languageCode: 'en');

      expect(mock.setVoiceCalls, isEmpty);
    });

    test('caches result — getVoices called only once per language', () async {
      final mock = _MockFlutterTts()
        ..voiceList = [
          {'name': 'com.apple.voice.premium.en-US.Zoe', 'locale': 'en-US'},
        ];
      // Wrap getVoices call tracking via voiceList side-effect isn't possible,
      // so we verify via a second speak() not throwing and setVoice being called twice.
      final svc = _svc(mock);

      await svc.speak('First', languageCode: 'en');
      // Clear setVoiceCalls to distinguish second call.
      final firstVoice = mock.setVoiceCalls.first;
      mock.setVoiceCalls.clear();
      // Simulate getVoices returning empty on second call to prove it's cached.
      mock.voiceList = [];

      await svc.speak('Second', languageCode: 'en');

      // If cached, the same voice should be used again despite empty voiceList.
      expect(mock.setVoiceCalls, hasLength(1));
      expect(mock.setVoiceCalls.first, equals(firstVoice));
    });

    test('falls back silently when getVoices throws', () async {
      final mock = _MockFlutterTts()
        ..getVoicesError = Exception('platform error');
      final svc = _svc(mock);

      // Should not throw — speak() completes normally without setVoice.
      await expectLater(
        svc.speak('Hello', languageCode: 'en'),
        completes,
      );
      expect(mock.setVoiceCalls, isEmpty);
      expect(mock.speakCalls, ['Hello']);
    });

    test('language prefix matching works for locale with underscore', () async {
      final mock = _MockFlutterTts()
        ..voiceList = [
          {'name': 'com.apple.voice.premium.pl-PL.Zosia', 'locale': 'pl-PL'},
        ];
      final svc = _svc(mock);

      // "pl_PL" (underscore) should still match "pl-PL" locale.
      await svc.speak('Cześć', languageCode: 'pl_PL');

      expect(mock.setVoiceCalls, hasLength(1));
    });

    test('does not call setVoice on non-iOS', () async {
      final mock = _MockFlutterTts()
        ..voiceList = [
          {'name': 'com.apple.voice.premium.en-US.Zoe', 'locale': 'en-US'},
        ];
      // Default isIOS = Platform.isIOS — in test host (macOS/Linux) this is false.
      final svc = FlutterTtsService(tts: mock, isIOS: false);

      await svc.speak('Hello', languageCode: 'en');

      expect(mock.setVoiceCalls, isEmpty);
    });
  });
}
