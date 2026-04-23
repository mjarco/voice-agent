import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/tts/ssml_lang_splitter.dart';

void main() {
  group('SsmlLangSplitter', () {
    test('empty input returns zero segments', () {
      expect(SsmlLangSplitter.split(''), isEmpty);
    });

    test('whitespace-only input returns zero segments', () {
      expect(SsmlLangSplitter.split('   '), isEmpty);
    });

    test('untagged text returns one default segment', () {
      final result = SsmlLangSplitter.split('Hello world');
      expect(result, [const TtsSegment('Hello world')]);
      expect(result.first.languageCode, isNull);
    });

    test('single tag produces segments with empty ones elided', () {
      final result = SsmlLangSplitter.split(
        'Ustaw <lang xml:lang="en-US">hangover</lang> na 800 ms.',
      );

      expect(result, [
        const TtsSegment('Ustaw '),
        const TtsSegment('hangover', languageCode: 'en-US'),
        const TtsSegment(' na 800 ms.'),
      ]);
    });

    test('tag at start elides leading empty default segment', () {
      final result = SsmlLangSplitter.split(
        '<lang xml:lang="en-US">API</lang> jest gotowe.',
      );

      expect(result, [
        const TtsSegment('API', languageCode: 'en-US'),
        const TtsSegment(' jest gotowe.'),
      ]);
    });

    test('tag at end elides trailing empty default segment', () {
      final result = SsmlLangSplitter.split(
        'Sprawdz <lang xml:lang="en-US">API</lang>',
      );

      expect(result, [
        const TtsSegment('Sprawdz '),
        const TtsSegment('API', languageCode: 'en-US'),
      ]);
    });

    test('multiple adjacent tags with different languages', () {
      final result = SsmlLangSplitter.split(
        '<lang xml:lang="en-US">Hello</lang> '
        '<lang xml:lang="pl-PL">Czesc</lang> '
        '<lang xml:lang="en-US">world</lang>',
      );

      expect(result, [
        const TtsSegment('Hello', languageCode: 'en-US'),
        const TtsSegment(' '),
        const TtsSegment('Czesc', languageCode: 'pl-PL'),
        const TtsSegment(' '),
        const TtsSegment('world', languageCode: 'en-US'),
      ]);
    });

    test('unclosed tag returns full string as one default segment', () {
      const input = 'Ustaw <lang xml:lang="en-US">hangover na 800 ms.';
      final result = SsmlLangSplitter.split(input);

      expect(result, [const TtsSegment(input)]);
      expect(result.first.languageCode, isNull);
    });

    test('unmatched </lang> returns full string as one default segment', () {
      const input = 'Some text</lang> more text';
      final result = SsmlLangSplitter.split(input);

      expect(result, [const TtsSegment(input)]);
      expect(result.first.languageCode, isNull);
    });

    test('nested tags: inner wins, outer text emitted with outer language', () {
      final result = SsmlLangSplitter.split(
        '<lang xml:lang="en-US">Check the '
        '<lang xml:lang="pl-PL">polityka</lang>'
        ' API</lang>',
      );

      expect(result, [
        const TtsSegment('Check the ', languageCode: 'en-US'),
        const TtsSegment('polityka', languageCode: 'pl-PL'),
        const TtsSegment(' API', languageCode: 'en-US'),
      ]);
    });

    test('mixed-case element <Lang> treated as malformed plain text', () {
      const input = 'Text <Lang xml:lang="en-US">API</Lang> more';
      final result = SsmlLangSplitter.split(input);

      // Not recognized as a tag — the whole thing is one default segment.
      expect(result, hasLength(1));
      expect(result.first.languageCode, isNull);
      expect(result.first.text, contains('<Lang'));
    });

    test('mixed-case attribute XML:LANG treated as malformed plain text', () {
      const input = 'Text <lang XML:LANG="en-US">API</lang> more';
      final result = SsmlLangSplitter.split(input);

      // The open tag is not recognized. The closing </lang> is unmatched,
      // so the fallback produces the full input.
      expect(result, hasLength(1));
      expect(result.first.languageCode, isNull);
      expect(result.first.text, contains('XML:LANG'));
    });

    test('single-quoted attribute treated as malformed', () {
      const input = "Text <lang xml:lang='en-US'>API</lang> more";
      final result = SsmlLangSplitter.split(input);

      expect(result, hasLength(1));
      expect(result.first.languageCode, isNull);
    });

    test('missing attribute treated as malformed', () {
      const input = 'Text <lang>API</lang> more';
      final result = SsmlLangSplitter.split(input);

      expect(result, hasLength(1));
      expect(result.first.languageCode, isNull);
    });

    test('bad BCP-47 value (all lowercase region) treated as malformed', () {
      const input = 'Text <lang xml:lang="en-us">API</lang> more';
      final result = SsmlLangSplitter.split(input);

      // "en-us" does not match xx-YY pattern, so the opening tag is not
      // recognized, but the closing </lang> is unmatched, causing fallback.
      expect(result, hasLength(1));
      expect(result.first.languageCode, isNull);
    });

    test('whitespace adjacent to tags is preserved', () {
      final result = SsmlLangSplitter.split(
        '  Ustaw  <lang xml:lang="en-US"> hangover </lang>  teraz  ',
      );

      expect(result, [
        const TtsSegment('  Ustaw  '),
        const TtsSegment(' hangover ', languageCode: 'en-US'),
        const TtsSegment('  teraz  '),
      ]);
    });

    test('<speak> envelope is stripped, contents parsed normally', () {
      final result = SsmlLangSplitter.split(
        '<speak>Ustaw <lang xml:lang="en-US">API</lang> teraz</speak>',
      );

      expect(result, [
        const TtsSegment('Ustaw '),
        const TtsSegment('API', languageCode: 'en-US'),
        const TtsSegment(' teraz'),
      ]);
    });

    test('<speak> envelope with only plain text', () {
      final result = SsmlLangSplitter.split('<speak>Just text</speak>');

      expect(result, [const TtsSegment('Just text')]);
    });

    test('empty <speak> envelope returns zero segments', () {
      expect(SsmlLangSplitter.split('<speak></speak>'), isEmpty);
    });

    test('TtsSegment equality', () {
      const a = TtsSegment('hello', languageCode: 'en-US');
      const b = TtsSegment('hello', languageCode: 'en-US');
      const c = TtsSegment('hello');

      expect(a, equals(b));
      expect(a, isNot(equals(c)));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('only tag with no surrounding text', () {
      final result = SsmlLangSplitter.split(
        '<lang xml:lang="en-US">API</lang>',
      );

      expect(result, [const TtsSegment('API', languageCode: 'en-US')]);
    });

    test('three-letter language code is accepted', () {
      final result = SsmlLangSplitter.split(
        'Text <lang xml:lang="cmn-CN">hello</lang> more',
      );

      expect(result, [
        const TtsSegment('Text '),
        const TtsSegment('hello', languageCode: 'cmn-CN'),
        const TtsSegment(' more'),
      ]);
    });

    test('extra attributes before xml:lang treated as malformed', () {
      const input =
          'Text <lang foo="bar" xml:lang="en-US">API</lang> more';
      final result = SsmlLangSplitter.split(input);

      expect(result, hasLength(1));
      expect(result.first.languageCode, isNull);
    });
  });
}
