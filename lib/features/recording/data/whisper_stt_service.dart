import 'dart:io';

import 'package:whisper_flutter_new/whisper_flutter_new.dart';
import 'package:voice_agent/features/recording/domain/stt_exception.dart';
import 'package:voice_agent/features/recording/domain/stt_service.dart';
import 'package:voice_agent/features/recording/domain/transcript_result.dart';

class WhisperSttService implements SttService {
  Whisper? _whisper;

  @override
  Future<bool> isModelLoaded() async => _whisper != null;

  @override
  Future<void> loadModel() async {
    _whisper = Whisper(
      model: WhisperModel.base,
      downloadHost:
          'https://huggingface.co/ggerganov/whisper.cpp/resolve/main',
    );
  }

  @override
  Future<TranscriptResult> transcribe(
    String audioFilePath, {
    String? languageCode,
  }) async {
    if (_whisper == null) {
      throw const SttException('Model not loaded. Call loadModel() first.');
    }

    final file = File(audioFilePath);
    if (!await file.exists()) {
      throw SttException('Audio file not found: $audioFilePath');
    }

    try {
      final result = await _whisper!.transcribe(
        transcribeRequest: TranscribeRequest(
          audio: audioFilePath,
          language: languageCode ?? 'auto',
        ),
      );

      final rawSegments = result.segments ?? [];
      final segments = rawSegments.map((s) {
        return TranscriptSegment(
          text: s.text.trim(),
          startMs: s.fromTs.inMilliseconds,
          endMs: s.toTs.inMilliseconds,
        );
      }).toList();

      return TranscriptResult(
        text: result.text.trim(),
        segments: segments,
        detectedLanguage: languageCode ?? 'auto',
        audioDurationMs: segments.isNotEmpty ? segments.last.endMs : 0,
      );
    } catch (e) {
      if (e is SttException) rethrow;
      throw SttException('Transcription failed: $e');
    }
  }
}
