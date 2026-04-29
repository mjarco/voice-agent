import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/tts/tts_reply_buffer.dart';

void main() {
  group('InMemoryTtsReplyBuffer', () {
    test('last() on empty buffer returns null', () {
      final buffer = InMemoryTtsReplyBuffer();
      expect(buffer.last(), isNull);
    });

    test('record() then last() returns the recorded entry', () {
      final buffer = InMemoryTtsReplyBuffer();
      buffer.record('hello', languageCode: 'en');
      expect(
        buffer.last(),
        const TtsReplyEntry(text: 'hello', languageCode: 'en'),
      );
    });

    test('record() with no languageCode is preserved as null', () {
      final buffer = InMemoryTtsReplyBuffer();
      buffer.record('hi');
      expect(buffer.last(), const TtsReplyEntry(text: 'hi'));
    });

    test('successive records overwrite (n=1 LRU)', () {
      final buffer = InMemoryTtsReplyBuffer();
      buffer.record('first', languageCode: 'pl');
      buffer.record('second', languageCode: 'en');
      expect(
        buffer.last(),
        const TtsReplyEntry(text: 'second', languageCode: 'en'),
      );
    });

    test('clear() empties the buffer', () {
      final buffer = InMemoryTtsReplyBuffer();
      buffer.record('hello', languageCode: 'en');
      buffer.clear();
      expect(buffer.last(), isNull);
    });

    test('clear() on empty buffer is a no-op', () {
      final buffer = InMemoryTtsReplyBuffer();
      buffer.clear();
      expect(buffer.last(), isNull);
    });
  });

  group('TtsReplyEntry equality', () {
    test('equal when text and languageCode match', () {
      expect(
        const TtsReplyEntry(text: 'a', languageCode: 'en'),
        const TtsReplyEntry(text: 'a', languageCode: 'en'),
      );
    });

    test('different text → not equal', () {
      expect(
        const TtsReplyEntry(text: 'a', languageCode: 'en'),
        isNot(const TtsReplyEntry(text: 'b', languageCode: 'en')),
      );
    });

    test('different languageCode → not equal', () {
      expect(
        const TtsReplyEntry(text: 'a', languageCode: 'en'),
        isNot(const TtsReplyEntry(text: 'a', languageCode: 'pl')),
      );
    });
  });
}
