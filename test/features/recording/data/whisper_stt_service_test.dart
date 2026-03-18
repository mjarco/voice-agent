import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/features/recording/domain/stt_exception.dart';
import 'package:voice_agent/features/recording/domain/stt_service.dart';
import 'package:voice_agent/features/recording/domain/transcript_result.dart';

/// Fake SttService for testing code that depends on the SttService interface
/// without requiring Whisper native binaries.
class FakeSttService implements SttService {
  bool _loaded = false;
  TranscriptResult? nextResult;
  SttException? shouldThrow;

  @override
  Future<bool> isModelLoaded() async => _loaded;

  @override
  Future<void> loadModel() async {
    _loaded = true;
  }

  @override
  Future<TranscriptResult> transcribe(
    String audioFilePath, {
    String? languageCode,
  }) async {
    if (!_loaded) {
      throw const SttException('Model not loaded. Call loadModel() first.');
    }
    if (shouldThrow != null) {
      throw shouldThrow!;
    }
    return nextResult ??
        TranscriptResult(
          text: 'Transcribed: $audioFilePath',
          segments: [
            TranscriptSegment(
              text: 'Transcribed: $audioFilePath',
              startMs: 0,
              endMs: 5000,
            ),
          ],
          detectedLanguage: languageCode ?? 'auto',
          audioDurationMs: 5000,
        );
  }
}

void main() {
  late FakeSttService service;

  setUp(() {
    service = FakeSttService();
  });

  group('SttService (via FakeSttService)', () {
    test('isModelLoaded returns false before loadModel', () async {
      expect(await service.isModelLoaded(), isFalse);
    });

    test('isModelLoaded returns true after loadModel', () async {
      await service.loadModel();
      expect(await service.isModelLoaded(), isTrue);
    });

    test('transcribe throws SttException when model not loaded', () async {
      expect(
        () => service.transcribe('/tmp/test.wav'),
        throwsA(isA<SttException>()),
      );
    });

    test('transcribe returns TranscriptResult on success', () async {
      await service.loadModel();
      final result = await service.transcribe('/tmp/test.wav');

      expect(result.text, contains('Transcribed'));
      expect(result.segments, isNotEmpty);
      expect(result.audioDurationMs, 5000);
    });

    test('transcribe passes languageCode through', () async {
      await service.loadModel();
      final result = await service.transcribe(
        '/tmp/test.wav',
        languageCode: 'pl',
      );

      expect(result.detectedLanguage, 'pl');
    });

    test('transcribe with custom result', () async {
      await service.loadModel();
      service.nextResult = const TranscriptResult(
        text: 'Custom result',
        segments: [],
        detectedLanguage: 'en',
        audioDurationMs: 3000,
      );

      final result = await service.transcribe('/tmp/test.wav');
      expect(result.text, 'Custom result');
      expect(result.audioDurationMs, 3000);
    });

    test('transcribe throws configured SttException', () async {
      await service.loadModel();
      service.shouldThrow = const SttException('Invalid audio format');

      expect(
        () => service.transcribe('/tmp/test.wav'),
        throwsA(
          isA<SttException>().having(
            (e) => e.message,
            'message',
            'Invalid audio format',
          ),
        ),
      );
    });
  });
}
