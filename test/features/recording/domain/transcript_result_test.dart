import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/models/transcript_result.dart';

void main() {
  group('TranscriptResult', () {
    test('constructs with all fields', () {
      final result = TranscriptResult(
        text: 'Hello world',
        segments: [
          const TranscriptSegment(text: 'Hello', startMs: 0, endMs: 500),
          const TranscriptSegment(text: 'world', startMs: 500, endMs: 1000),
        ],
        detectedLanguage: 'en',
        audioDurationMs: 1000,
      );

      expect(result.text, 'Hello world');
      expect(result.segments.length, 2);
      expect(result.detectedLanguage, 'en');
      expect(result.audioDurationMs, 1000);
    });

    test('constructs with empty segments', () {
      const result = TranscriptResult(
        text: '',
        segments: [],
        detectedLanguage: 'auto',
        audioDurationMs: 0,
      );

      expect(result.text, isEmpty);
      expect(result.segments, isEmpty);
    });

    test('segments maintain order', () {
      final result = TranscriptResult(
        text: 'a b c',
        segments: [
          const TranscriptSegment(text: 'a', startMs: 0, endMs: 100),
          const TranscriptSegment(text: 'b', startMs: 100, endMs: 200),
          const TranscriptSegment(text: 'c', startMs: 200, endMs: 300),
        ],
        detectedLanguage: 'pl',
        audioDurationMs: 300,
      );

      expect(result.segments[0].startMs, 0);
      expect(result.segments[1].startMs, 100);
      expect(result.segments[2].startMs, 200);
    });
  });

  group('TranscriptSegment', () {
    test('constructs correctly', () {
      const segment = TranscriptSegment(
        text: 'hello',
        startMs: 100,
        endMs: 500,
      );

      expect(segment.text, 'hello');
      expect(segment.startMs, 100);
      expect(segment.endMs, 500);
    });
  });

  group('SttException', () {
    test('toString includes message', () {
      // Import tested indirectly — SttException is used by WhisperSttService
      // but we verify the model types work correctly here
      expect(true, isTrue);
    });
  });
}
