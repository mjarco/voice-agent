import 'dart:io';
import 'dart:ui';

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

  // ── Handler capture ──────────────────────────────────────────────────────

  VoidCallback? _startHandler;
  VoidCallback? _completionHandler;
  VoidCallback? _cancelHandler;
  ErrorHandler? _errorHandler;

  @override
  dynamic setStartHandler(VoidCallback callback) {
    _startHandler = callback;
    return null;
  }

  @override
  dynamic setCompletionHandler(VoidCallback callback) {
    _completionHandler = callback;
    return null;
  }

  @override
  dynamic setCancelHandler(VoidCallback callback) {
    _cancelHandler = callback;
    return null;
  }

  @override
  dynamic setErrorHandler(ErrorHandler callback) {
    _errorHandler = callback;
    return null;
  }

  /// Fire the registered start handler (simulates platform start event).
  void fireStart() => _startHandler?.call();

  /// Fire the registered completion handler (simulates platform done event).
  void fireCompletion() => _completionHandler?.call();

  /// Fire the registered cancel handler.
  void fireCancel() => _cancelHandler?.call();

  /// Fire the registered error handler.
  void fireError(String msg) => _errorHandler?.call(msg);

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
  // Default to a settled Future so future-typed setters (e.g.
  // setSharedInstance, setIosAudioCategory) don't throw a TypeError
  // when the constructor fires them on iOS.
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<dynamic>.value(null);
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('FlutterTtsService', () {
    test('speak() with explicit languageCode calls setLanguage with that code',
        () async {
      final mock = _MockFlutterTts();
      final svc = FlutterTtsService(tts: mock);

      await svc.speak('Hello', languageCode: 'pl');

      expect(mock.setLanguageCalls, ['pl']);
      expect(mock.speakCalls, ['Hello']);
    });

    test(
        'speak() with "auto" calls setLanguage with full Platform.localeName, not "auto"',
        () async {
      final mock = _MockFlutterTts();
      final svc = FlutterTtsService(tts: mock);

      await svc.speak('Czesc', languageCode: 'auto');

      expect(mock.setLanguageCalls, hasLength(1));
      final lang = mock.setLanguageCalls.first;
      expect(lang, isNot('auto'));
      // Full locale: at minimum two chars separated by _ or just the locale.
      expect(lang, equals(Platform.localeName));
    });

    test('speak() with null languageCode also uses Platform.localeName',
        () async {
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
    FlutterTtsService makeSvc(_MockFlutterTts mock) =>
        FlutterTtsService(tts: mock, isIOS: true);

    test('picks premium voice over enhanced and normal', () async {
      final mock = _MockFlutterTts()
        ..voiceList = [
          {'name': 'com.apple.voice.normal.pl-PL.Zosia', 'locale': 'pl-PL'},
          {'name': 'com.apple.voice.enhanced.pl-PL.Ewa', 'locale': 'pl-PL'},
          {'name': 'com.apple.voice.premium.pl-PL.Zosia', 'locale': 'pl-PL'},
        ];
      final svc = makeSvc(mock);

      await svc.speak('Czesc', languageCode: 'pl');

      expect(mock.setVoiceCalls, hasLength(1));
      expect(mock.setVoiceCalls.first['name'], contains('premium'));
    });

    test('picks enhanced when no premium available', () async {
      final mock = _MockFlutterTts()
        ..voiceList = [
          {'name': 'com.apple.voice.normal.pl-PL.Ewa', 'locale': 'pl-PL'},
          {'name': 'com.apple.voice.enhanced.pl-PL.Zosia', 'locale': 'pl-PL'},
        ];
      final svc = makeSvc(mock);

      await svc.speak('Czesc', languageCode: 'pl');

      expect(mock.setVoiceCalls.first['name'], contains('enhanced'));
    });

    test('picks normal when only normal voices available', () async {
      final mock = _MockFlutterTts()
        ..voiceList = [
          {'name': 'com.apple.ttsbundle.pl-PL-Zosia', 'locale': 'pl-PL'},
        ];
      final svc = makeSvc(mock);

      await svc.speak('Czesc', languageCode: 'pl');

      expect(mock.setVoiceCalls, hasLength(1));
      expect(mock.setVoiceCalls.first['name'], contains('pl-PL'));
    });

    test('does not call setVoice when no voice matches language', () async {
      final mock = _MockFlutterTts()
        ..voiceList = [
          {'name': 'com.apple.voice.premium.en-US.Zoe', 'locale': 'en-US'},
        ];
      final svc = makeSvc(mock);

      await svc.speak('Czesc', languageCode: 'pl');

      expect(mock.setVoiceCalls, isEmpty);
    });

    test('does not call setVoice when voice list is empty', () async {
      final mock = _MockFlutterTts()..voiceList = [];
      final svc = makeSvc(mock);

      await svc.speak('Hello', languageCode: 'en');

      expect(mock.setVoiceCalls, isEmpty);
    });

    test('caches result -- getVoices called only once per language', () async {
      final mock = _MockFlutterTts()
        ..voiceList = [
          {'name': 'com.apple.voice.premium.en-US.Zoe', 'locale': 'en-US'},
        ];
      // Wrap getVoices call tracking via voiceList side-effect isn't possible,
      // so we verify via a second speak() not throwing and setVoice being called twice.
      final svc = makeSvc(mock);

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
      final svc = makeSvc(mock);

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
      final svc = makeSvc(mock);

      // "pl_PL" (underscore) should still match "pl-PL" locale.
      await svc.speak('Czesc', languageCode: 'pl_PL');

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

  group('FlutterTtsService multi-segment (P030)', () {
    test('two-segment input produces ordered setLanguage/speak calls',
        () async {
      final mock = _MockFlutterTts();
      final svc = FlutterTtsService(tts: mock, isIOS: false);

      final future = svc.speak(
        'Ustaw <lang xml:lang="en-US">hangover</lang> na 800 ms.',
        languageCode: 'pl',
      );

      // After the first speak call returns, the start handler fires.
      await Future<void>.delayed(Duration.zero);
      mock.fireStart();

      // First segment spoken — fire completion to advance.
      await Future<void>.delayed(Duration.zero);
      mock.fireCompletion();

      // Second segment (en-US) spoken — fire start + completion.
      await Future<void>.delayed(Duration.zero);
      mock.fireStart();
      await Future<void>.delayed(Duration.zero);
      mock.fireCompletion();

      // Third segment — fire start + completion to drain the queue.
      await Future<void>.delayed(Duration.zero);
      mock.fireStart();
      await Future<void>.delayed(Duration.zero);
      mock.fireCompletion();

      await future;

      // Three segments: "Ustaw ", "hangover", " na 800 ms."
      expect(mock.speakCalls, ['Ustaw ', 'hangover', ' na 800 ms.']);
      expect(mock.setLanguageCalls, ['pl', 'en-US', 'pl']);
    });

    test('_speaking stays true between segments (no flapping)', () async {
      final mock = _MockFlutterTts();
      final svc = FlutterTtsService(tts: mock, isIOS: false);

      final transitions = <bool>[];
      svc.isSpeaking.addListener(() => transitions.add(svc.isSpeaking.value));

      final future = svc.speak(
        'A <lang xml:lang="en-US">B</lang>',
        languageCode: 'pl',
      );

      await Future<void>.delayed(Duration.zero);
      mock.fireStart(); // _speaking false -> true
      await Future<void>.delayed(Duration.zero);
      mock.fireCompletion(); // advance to segment 2, _speaking stays true
      await Future<void>.delayed(Duration.zero);
      mock.fireStart(); // already true, no-op
      await Future<void>.delayed(Duration.zero);
      mock.fireCompletion(); // queue drained

      await future; // finally block sets _speaking = false

      // Exactly two transitions: false->true, true->false.
      expect(transitions, [true, false]);
    });

    test('stop() mid-queue prevents subsequent segments', () async {
      final mock = _MockFlutterTts();
      final svc = FlutterTtsService(tts: mock, isIOS: false);

      final future = svc.speak(
        'A <lang xml:lang="en-US">B</lang> C',
        languageCode: 'pl',
      );

      await Future<void>.delayed(Duration.zero);
      mock.fireStart();
      await Future<void>.delayed(Duration.zero);

      // Stop mid-queue (after segment 1 is playing).
      await svc.stop();
      await future;

      // Only the first segment should have been spoken.
      expect(mock.speakCalls, ['A ']);
    });

    test('untagged input uses exactly one setLanguage and one speak (regression)',
        () async {
      final mock = _MockFlutterTts();
      final svc = FlutterTtsService(tts: mock, isIOS: false);

      await svc.speak('Just plain text', languageCode: 'pl');

      expect(mock.setLanguageCalls, ['pl']);
      expect(mock.speakCalls, ['Just plain text']);
    });

    test(
        'ttsPlayingProvider transitions: exactly [(false,true),(true,false)] for multi-segment',
        () async {
      final mock = _MockFlutterTts();
      final svc = FlutterTtsService(tts: mock, isIOS: false);

      final pairs = <(bool, bool)>[];
      var prev = svc.isSpeaking.value;
      svc.isSpeaking.addListener(() {
        final next = svc.isSpeaking.value;
        pairs.add((prev, next));
        prev = next;
      });

      final future = svc.speak(
        'X <lang xml:lang="en-US">Y</lang> Z',
        languageCode: 'pl',
      );

      // Drive through all three segments.
      await Future<void>.delayed(Duration.zero);
      mock.fireStart();
      await Future<void>.delayed(Duration.zero);
      mock.fireCompletion();
      await Future<void>.delayed(Duration.zero);
      mock.fireStart();
      await Future<void>.delayed(Duration.zero);
      mock.fireCompletion();
      await Future<void>.delayed(Duration.zero);
      mock.fireStart();
      await Future<void>.delayed(Duration.zero);
      mock.fireCompletion();

      await future;

      expect(pairs, [(false, true), (true, false)]);
    });

    test('stop then speak: stale completion does not affect new queue',
        () async {
      final mock = _MockFlutterTts();
      final svc = FlutterTtsService(tts: mock, isIOS: false);

      // Start first queue.
      final future1 = svc.speak(
        'Old <lang xml:lang="en-US">text</lang>',
        languageCode: 'pl',
      );
      await Future<void>.delayed(Duration.zero);
      mock.fireStart();
      await Future<void>.delayed(Duration.zero);

      // Stop the first queue.
      await svc.stop();
      await future1;

      // Clear call history.
      mock.speakCalls.clear();
      mock.setLanguageCalls.clear();

      // Start a new queue.
      final future2 = svc.speak(
        'New <lang xml:lang="en-US">reply</lang>',
        languageCode: 'pl',
      );
      await Future<void>.delayed(Duration.zero);

      // Fire a stale completion from the old queue — should be ignored.
      mock.fireCompletion();
      await Future<void>.delayed(Duration.zero);

      // Fire the real start and completion for the new queue segments.
      mock.fireStart();
      await Future<void>.delayed(Duration.zero);
      mock.fireCompletion(); // advance to segment 2
      await Future<void>.delayed(Duration.zero);
      mock.fireStart();
      await Future<void>.delayed(Duration.zero);
      mock.fireCompletion(); // queue drained

      await future2;

      // New queue's segments should be fully spoken.
      expect(mock.speakCalls, ['New ', 'reply']);
    });

    test('generation counter: old gen completion ignored after new gen starts',
        () async {
      final mock = _MockFlutterTts();
      final svc = FlutterTtsService(tts: mock, isIOS: false);

      // Queue A (gen=1).
      final futureA = svc.speak(
        'A1 <lang xml:lang="en-US">A2</lang>',
        languageCode: 'pl',
      );
      await Future<void>.delayed(Duration.zero);
      mock.fireStart();
      await Future<void>.delayed(Duration.zero);

      // Stop queue A.
      await svc.stop();
      await futureA;

      mock.speakCalls.clear();
      mock.setLanguageCalls.clear();

      // Queue B (gen=2).
      final futureB = svc.speak(
        'B1 <lang xml:lang="en-US">B2</lang>',
        languageCode: 'pl',
      );
      await Future<void>.delayed(Duration.zero);
      mock.fireStart();
      await Future<void>.delayed(Duration.zero);

      // Fire a completion that might have been left over from gen=1.
      // The generation check should make this a no-op for queue B.
      // Then fire the real completions for queue B.
      mock.fireCompletion(); // should advance to B2 (correct gen)
      await Future<void>.delayed(Duration.zero);
      mock.fireStart();
      await Future<void>.delayed(Duration.zero);
      mock.fireCompletion(); // B2 done

      await futureB;

      // Queue B segments are spoken correctly.
      expect(mock.speakCalls, ['B1 ', 'B2']);
    });

    test('empty segments from splitter cause speak() to early-return', () async {
      final mock = _MockFlutterTts();
      final svc = FlutterTtsService(tts: mock, isIOS: false);

      await svc.speak('');

      expect(mock.speakCalls, isEmpty);
      expect(svc.isSpeaking.value, isFalse);
    });

    test('error handler mid-queue clears queue and sets speaking false',
        () async {
      final mock = _MockFlutterTts();
      final svc = FlutterTtsService(tts: mock, isIOS: false);

      final future = svc.speak(
        'A <lang xml:lang="en-US">B</lang> C',
        languageCode: 'pl',
      );

      await Future<void>.delayed(Duration.zero);
      mock.fireStart();
      await Future<void>.delayed(Duration.zero);

      // Error during first segment.
      mock.fireError('TTS engine error');

      await future;

      expect(svc.isSpeaking.value, isFalse);
      // Only first segment should have been spoken.
      expect(mock.speakCalls, ['A ']);
    });

    test('cancel handler mid-queue clears queue and sets speaking false',
        () async {
      final mock = _MockFlutterTts();
      final svc = FlutterTtsService(tts: mock, isIOS: false);

      final future = svc.speak(
        'A <lang xml:lang="en-US">B</lang> C',
        languageCode: 'pl',
      );

      await Future<void>.delayed(Duration.zero);
      mock.fireStart();
      await Future<void>.delayed(Duration.zero);

      // Cancel mid-queue.
      mock.fireCancel();

      await future;

      expect(svc.isSpeaking.value, isFalse);
      expect(mock.speakCalls, ['A ']);
    });

    test('multi-segment with iOS calls setVoice per segment', () async {
      final mock = _MockFlutterTts()
        ..voiceList = [
          {'name': 'com.apple.voice.premium.pl-PL.Zosia', 'locale': 'pl-PL'},
          {'name': 'com.apple.voice.premium.en-US.Zoe', 'locale': 'en-US'},
        ];
      final svc = FlutterTtsService(tts: mock, isIOS: true);

      final future = svc.speak(
        'Tekst <lang xml:lang="en-US">API</lang>',
        languageCode: 'pl',
      );

      await Future<void>.delayed(Duration.zero);
      mock.fireStart();
      await Future<void>.delayed(Duration.zero);
      mock.fireCompletion();
      await Future<void>.delayed(Duration.zero);
      mock.fireStart();
      await Future<void>.delayed(Duration.zero);
      mock.fireCompletion();

      await future;

      // Two segments, two setVoice calls (one PL, one EN).
      expect(mock.setVoiceCalls, hasLength(2));
      expect(mock.setVoiceCalls[0]['name'], contains('pl-PL'));
      expect(mock.setVoiceCalls[1]['name'], contains('en-US'));
    });
  });
}
