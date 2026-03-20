import 'dart:io';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:voice_agent/core/tts/tts_service.dart';

class FlutterTtsService implements TtsService {
  FlutterTtsService({FlutterTts? tts}) : _tts = tts ?? FlutterTts();

  final FlutterTts _tts;

  @override
  Future<void> speak(String text, {String? languageCode}) async {
    final lang = _resolveLanguage(languageCode);
    await _tts.setLanguage(lang);
    await _tts.speak(text);
  }

  @override
  Future<void> stop() async {
    await _tts.stop();
  }

  @override
  void dispose() {
    _tts.stop();
  }

  String _resolveLanguage(String? code) {
    if (code == null || code == 'auto') {
      // Use full device locale (e.g. "pl_PL") so AVSpeechSynthesizer on iOS
      // can select the correct voice. Never pass bare two-letter code for auto.
      return Platform.localeName;
    }
    // Explicit code (e.g. "pl", "en") — passed as-is; best-effort on iOS.
    return code;
  }
}
