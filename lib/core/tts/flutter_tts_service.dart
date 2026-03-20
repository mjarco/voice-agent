import 'dart:io';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:voice_agent/core/tts/tts_service.dart';

class FlutterTtsService implements TtsService {
  FlutterTtsService({FlutterTts? tts, bool? isIOS})
      : _tts = tts ?? FlutterTts(),
        _isIOS = isIOS ?? Platform.isIOS;

  final FlutterTts _tts;
  final bool _isIOS;

  // Cache best voice per resolved language string to avoid repeated getVoices()
  // calls. null value means "looked up, nothing better than system default".
  final Map<String, Map<String, String>?> _voiceCache = {};

  @override
  Future<void> speak(String text, {String? languageCode}) async {
    final lang = _resolveLanguage(languageCode);
    await _tts.setLanguage(lang);
    if (_isIOS) {
      final voice = await _bestVoice(lang);
      if (voice != null) await _tts.setVoice(voice);
    }
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

  /// Returns the best available iOS voice for [lang], preferring premium >
  /// enhanced > normal quality. Returns null when no voice matches or voices
  /// cannot be listed (falls back to AVSpeechSynthesizer default selection).
  Future<Map<String, String>?> _bestVoice(String lang) async {
    if (_voiceCache.containsKey(lang)) return _voiceCache[lang];

    try {
      // Match on the primary language tag (e.g. "pl" from "pl_PL" or "pl-PL").
      final langPrefix = lang.split(RegExp(r'[_\-]')).first.toLowerCase();

      final dynamic raw = await _tts.getVoices;
      final voices = raw as List?;
      if (voices == null) {
        _voiceCache[lang] = null;
        return null;
      }

      Map<String, String>? premium;
      Map<String, String>? enhanced;
      Map<String, String>? normal;

      for (final entry in voices) {
        final voice = Map<String, String>.from(entry as Map);
        final name = (voice['name'] ?? '').toLowerCase();
        final locale = (voice['locale'] ?? '').toLowerCase();

        if (!locale.startsWith(langPrefix)) continue;

        if (name.contains('premium')) {
          premium ??= voice;
        } else if (name.contains('enhanced')) {
          enhanced ??= voice;
        } else {
          normal ??= voice;
        }
      }

      final best = premium ?? enhanced ?? normal;
      _voiceCache[lang] = best;
      return best;
    } catch (_) {
      // Platform call failed — fall back to AVSpeechSynthesizer default.
      _voiceCache[lang] = null;
      return null;
    }
  }
}
