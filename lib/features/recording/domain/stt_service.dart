import 'package:voice_agent/features/recording/domain/transcript_result.dart';

abstract class SttService {
  Future<TranscriptResult> transcribe(
    String audioFilePath, {
    String? languageCode,
  });

  Future<bool> isModelLoaded();
  Future<void> loadModel();
}
