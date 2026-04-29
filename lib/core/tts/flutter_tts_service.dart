import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:voice_agent/core/tts/ssml_lang_splitter.dart';
import 'package:voice_agent/core/tts/tts_service.dart';

class FlutterTtsService implements TtsService {
  FlutterTtsService({FlutterTts? tts, bool? isIOS})
      : _tts = tts ?? FlutterTts(),
        _isIOS = isIOS ?? Platform.isIOS {
    _tts.setStartHandler(_onStart);
    _tts.setCompletionHandler(_onCompletion);
    _tts.setCancelHandler(_onCancel);
    _tts.setErrorHandler(_onError);
  }

  final FlutterTts _tts;
  final bool _isIOS;
  final ValueNotifier<bool> _speaking = ValueNotifier(false);

  @override
  ValueListenable<bool> get isSpeaking => _speaking;

  // Cache best voice per resolved language string to avoid repeated getVoices()
  // calls. null value means "looked up, nothing better than system default".
  final Map<String, Map<String, String>?> _voiceCache = {};

  // ── Per-segment queue state ─────────────────────────────────────────────

  _SegmentQueue? _activeQueue;
  int _queueGeneration = 0;

  @override
  Future<void> speak(String text, {String? languageCode}) async {
    final segments = SsmlLangSplitter.split(text);
    if (segments.isEmpty) return;

    // Single segment with no explicit language override: follow the original
    // path exactly (zero behavior change for untagged replies).
    if (segments.length == 1 && segments.first.languageCode == null) {
      return _speakSingle(segments.first.text, languageCode);
    }

    // Multi-segment (or single segment with explicit language): queue path.
    final generation = ++_queueGeneration;
    final queue = _SegmentQueue(
      segments: segments,
      defaultLanguageCode: languageCode,
      generation: generation,
      doneCompleter: Completer<void>(),
    );

    _activeQueue = queue;

    try {
      await _speakSegment(queue, 0);
      await queue.doneCompleter.future;
    } finally {
      // Invariant: _speaking transitions true -> false exactly once here.
      if (_activeQueue?.generation == generation) {
        _activeQueue = null;
      }
      if (_speaking.value) _speaking.value = false;
    }
  }

  /// The original single-utterance path, unchanged from pre-P030 behavior.
  Future<void> _speakSingle(String text, String? languageCode) async {
    final lang = _resolveLanguage(languageCode);
    await _tts.setLanguage(lang);
    if (_isIOS) {
      final voice = await _bestVoice(lang);
      if (voice != null) await _tts.setVoice(voice);
    }
    await _tts.speak(text);
  }

  /// Set language/voice and speak segment at [index] in [queue].
  Future<void> _speakSegment(_SegmentQueue queue, int index) async {
    queue.currentIndex = index;
    final segment = queue.segments[index];

    final lang = segment.languageCode ??
        _resolveLanguage(queue.defaultLanguageCode);
    await _tts.setLanguage(lang);
    if (_isIOS) {
      final voice = await _bestVoice(lang);
      if (voice != null) await _tts.setVoice(voice);
    }
    await _tts.speak(segment.text);
  }

  // ── Handler callbacks ───────────────────────────────────────────────────

  void _onStart() {
    debugPrint('[TtsDbg] _onStart speakingWas=${_speaking.value}');
    if (!_speaking.value) _speaking.value = true;
  }

  void _onCompletion() {
    debugPrint('[TtsDbg] _onCompletion activeQueue=${_activeQueue != null} speaking=${_speaking.value}');
    final queue = _activeQueue;
    if (queue == null) {
      // No active queue — single-utterance path or already cleared.
      _speaking.value = false;
      return;
    }

    // Stale handler from a previous generation — ignore.
    if (queue.generation != _queueGeneration) return;

    final nextIndex = queue.currentIndex + 1;
    if (nextIndex < queue.segments.length) {
      // Advance to the next segment. Do NOT touch _speaking.
      _speakSegment(queue, nextIndex);
    } else {
      // Queue drained.
      _activeQueue = null;
      if (!queue.doneCompleter.isCompleted) {
        queue.doneCompleter.complete();
      }
      // _speaking will be set false in the finally block of speak().
    }
  }

  void _onCancel() {
    debugPrint('[TtsDbg] _onCancel speakingWas=${_speaking.value}');
    final queue = _activeQueue;
    _activeQueue = null;
    if (queue != null && !queue.doneCompleter.isCompleted) {
      queue.doneCompleter.complete();
    }
    _speaking.value = false;
  }

  void _onError(dynamic error) {
    debugPrint('[TtsDbg] _onError error=$error speakingWas=${_speaking.value}');
    final queue = _activeQueue;
    _activeQueue = null;
    if (queue != null && !queue.doneCompleter.isCompleted) {
      queue.doneCompleter.complete();
    }
    _speaking.value = false;
  }

  @override
  Future<void> stop() async {
    debugPrint('[TtsDbg] stop() called speaking=${_speaking.value} hasActiveQueue=${_activeQueue != null}');
    // (1) Clear the queue so any racing completion handler sees null.
    final queue = _activeQueue;
    _activeQueue = null;

    // (2) Wait for the native-side cancel to complete.
    await _tts.stop();
    debugPrint('[TtsDbg] stop() native _tts.stop() returned');

    // (3) Complete any pending doneCompleter.
    if (queue != null && !queue.doneCompleter.isCompleted) {
      queue.doneCompleter.complete();
    }

    // (4) Ensure _speaking is false.
    if (_speaking.value) _speaking.value = false;
    debugPrint('[TtsDbg] stop() done speaking=${_speaking.value}');
  }

  @override
  void dispose() {
    final queue = _activeQueue;
    _activeQueue = null;
    if (queue != null && !queue.doneCompleter.isCompleted) {
      queue.doneCompleter.completeError(
        StateError('FlutterTtsService disposed'),
      );
    }
    _tts.stop();
    _speaking.dispose();
  }

  static final _langNameToCode = <String, String>{
    'afrikaans': 'af', 'arabic': 'ar', 'armenian': 'hy', 'azerbaijani': 'az',
    'belarusian': 'be', 'bosnian': 'bs', 'bulgarian': 'bg', 'catalan': 'ca',
    'chinese': 'zh', 'croatian': 'hr', 'czech': 'cs', 'danish': 'da',
    'dutch': 'nl', 'english': 'en', 'estonian': 'et', 'finnish': 'fi',
    'french': 'fr', 'galician': 'gl', 'german': 'de', 'greek': 'el',
    'hebrew': 'he', 'hindi': 'hi', 'hungarian': 'hu', 'icelandic': 'is',
    'indonesian': 'id', 'italian': 'it', 'japanese': 'ja', 'kannada': 'kn',
    'kazakh': 'kk', 'korean': 'ko', 'latvian': 'lv', 'lithuanian': 'lt',
    'macedonian': 'mk', 'malay': 'ms', 'marathi': 'mr', 'maori': 'mi',
    'nepali': 'ne', 'norwegian': 'no', 'persian': 'fa', 'polish': 'pl',
    'portuguese': 'pt', 'romanian': 'ro', 'russian': 'ru', 'serbian': 'sr',
    'slovak': 'sk', 'slovenian': 'sl', 'spanish': 'es', 'swahili': 'sw',
    'swedish': 'sv', 'tagalog': 'tl', 'tamil': 'ta', 'thai': 'th',
    'turkish': 'tr', 'ukrainian': 'uk', 'urdu': 'ur', 'vietnamese': 'vi',
    'welsh': 'cy',
  };

  String _resolveLanguage(String? code) {
    if (code == null || code == 'auto') {
      return Platform.localeName;
    }
    final normalized = _langNameToCode[code.toLowerCase()];
    if (normalized != null) return normalized;
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

class _SegmentQueue {
  _SegmentQueue({
    required this.segments,
    required this.defaultLanguageCode,
    required this.generation,
    required this.doneCompleter,
  });

  final List<TtsSegment> segments;
  final String? defaultLanguageCode;
  final int generation;
  final Completer<void> doneCompleter;
  int currentIndex = 0;
}
