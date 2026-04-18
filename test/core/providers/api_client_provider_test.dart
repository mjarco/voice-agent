import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/providers/api_client_provider.dart';

void main() {
  group('deriveBaseUrl', () {
    test('extracts base URL from voice transcript endpoint', () {
      expect(
        deriveBaseUrl('https://agent.jarco.casa/api/v1/voice/transcript'),
        'https://agent.jarco.casa/api/v1',
      );
    });

    test('extracts base URL with port', () {
      expect(
        deriveBaseUrl('http://localhost:8888/api/v1/voice/transcript'),
        'http://localhost:8888/api/v1',
      );
    });

    test('handles URL with only /api/v1', () {
      expect(
        deriveBaseUrl('https://example.com/api/v1'),
        'https://example.com/api/v1',
      );
    });

    test('handles URL with trailing slash after /api/v1/', () {
      expect(
        deriveBaseUrl('https://example.com/api/v1/'),
        'https://example.com/api/v1',
      );
    });

    test('returns null for null input', () {
      expect(deriveBaseUrl(null), isNull);
    });

    test('returns null for empty input', () {
      expect(deriveBaseUrl(''), isNull);
    });

    test('returns null for URL without /api segment', () {
      expect(deriveBaseUrl('https://example.com/other/path'), isNull);
    });

    test('returns null for URL with /api but no version segment', () {
      expect(deriveBaseUrl('https://example.com/api'), isNull);
    });

    test('returns null for invalid URL', () {
      expect(deriveBaseUrl('not a url'), isNull);
    });

    test('handles different API versions', () {
      expect(
        deriveBaseUrl('https://example.com/api/v2/voice/transcript'),
        'https://example.com/api/v2',
      );
    });

    test('result never ends with slash', () {
      final result =
          deriveBaseUrl('https://example.com/api/v1/voice/transcript');
      expect(result, isNotNull);
      expect(result!.endsWith('/'), isFalse);
    });
  });
}
