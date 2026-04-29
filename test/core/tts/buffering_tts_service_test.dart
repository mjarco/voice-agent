import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/tts/buffering_tts_service.dart';
import 'package:voice_agent/core/tts/tts_reply_buffer.dart';
import 'package:voice_agent/core/tts/tts_service.dart';

class _SpyTts implements TtsService {
  final List<String> log = [];
  bool throwOnSpeak = false;
  final ValueNotifier<bool> _speaking = ValueNotifier(false);

  @override
  ValueListenable<bool> get isSpeaking => _speaking;

  @override
  Future<void> speak(String text, {String? languageCode}) async {
    log.add('speak:$text:$languageCode');
    if (throwOnSpeak) throw StateError('boom');
  }

  @override
  Future<void> stop() async {
    log.add('stop');
  }

  @override
  void dispose() {
    log.add('dispose');
  }
}

void main() {
  group('BufferingTtsService', () {
    late _SpyTts inner;
    late InMemoryTtsReplyBuffer buffer;
    late BufferingTtsService service;

    setUp(() {
      inner = _SpyTts();
      buffer = InMemoryTtsReplyBuffer();
      service = BufferingTtsService(inner: inner, buffer: buffer);
    });

    test('successful speak forwards to inner and records in buffer', () async {
      await service.speak('hello', languageCode: 'en');

      expect(inner.log, ['speak:hello:en']);
      expect(
        buffer.last(),
        const TtsReplyEntry(text: 'hello', languageCode: 'en'),
      );
    });

    test('speak without languageCode records null languageCode', () async {
      await service.speak('plain');
      expect(buffer.last(), const TtsReplyEntry(text: 'plain'));
    });

    test('thrown speak does NOT record in buffer', () async {
      inner.throwOnSpeak = true;
      await expectLater(
        () => service.speak('boom', languageCode: 'en'),
        throwsStateError,
      );
      expect(buffer.last(), isNull);
    });

    test('stop() does not record', () async {
      await service.stop();
      expect(inner.log, ['stop']);
      expect(buffer.last(), isNull);
    });

    test('dispose() does not record', () {
      service.dispose();
      expect(inner.log, ['dispose']);
      expect(buffer.last(), isNull);
    });

    test('isSpeaking is delegated to inner', () {
      expect(service.isSpeaking, same(inner.isSpeaking));
    });

    test('successive successful speaks overwrite (n=1 LRU)', () async {
      await service.speak('first', languageCode: 'pl');
      await service.speak('second', languageCode: 'en');
      expect(
        buffer.last(),
        const TtsReplyEntry(text: 'second', languageCode: 'en'),
      );
    });
  });
}
