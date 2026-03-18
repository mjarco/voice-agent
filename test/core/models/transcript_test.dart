import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/models/transcript.dart';

void main() {
  group('Transcript', () {
    test('fromMap/toMap round-trip with all fields', () {
      final transcript = Transcript(
        id: 'abc-123',
        text: 'Hello world',
        language: 'en',
        audioDurationMs: 5000,
        deviceId: 'device-1',
        createdAt: 1710000000000,
      );

      final map = transcript.toMap();
      final restored = Transcript.fromMap(map);

      expect(restored, equals(transcript));
    });

    test('fromMap/toMap round-trip with nullable fields null', () {
      final transcript = Transcript(
        id: 'abc-456',
        text: 'Cześć świecie',
        language: null,
        audioDurationMs: null,
        deviceId: 'device-2',
        createdAt: 1710000001000,
      );

      final map = transcript.toMap();
      final restored = Transcript.fromMap(map);

      expect(restored, equals(transcript));
      expect(restored.language, isNull);
      expect(restored.audioDurationMs, isNull);
    });

    test('toMap produces correct keys', () {
      final transcript = Transcript(
        id: 'id-1',
        text: 'test',
        language: 'pl',
        audioDurationMs: 3000,
        deviceId: 'dev-1',
        createdAt: 100,
      );

      final map = transcript.toMap();

      expect(map['id'], 'id-1');
      expect(map['text'], 'test');
      expect(map['language'], 'pl');
      expect(map['audio_duration_ms'], 3000);
      expect(map['device_id'], 'dev-1');
      expect(map['created_at'], 100);
    });
  });
}
