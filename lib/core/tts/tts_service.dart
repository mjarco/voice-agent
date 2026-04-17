import 'package:flutter/foundation.dart';

abstract class TtsService {
  Future<void> speak(String text, {String? languageCode});
  Future<void> stop();
  void dispose();

  /// Whether TTS is currently playing audio.
  ValueListenable<bool> get isSpeaking;
}
