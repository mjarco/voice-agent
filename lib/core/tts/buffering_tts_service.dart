import 'package:flutter/foundation.dart';
import 'package:voice_agent/core/tts/tts_reply_buffer.dart';
import 'package:voice_agent/core/tts/tts_service.dart';

/// Decorator over [TtsService] that records the `(text, languageCode)` of
/// every successful `speak()` call into a [TtsReplyBuffer] (proposal 036).
///
/// Only successful (non-throwing) `speak` calls write to the buffer. Calls
/// to `stop()` and `dispose()` do not. By design only the agent-reply
/// `TtsService` instance is wrapped — error/feedback speak callsites must
/// not feed the replay buffer.
class BufferingTtsService implements TtsService {
  BufferingTtsService({
    required TtsService inner,
    required TtsReplyBuffer buffer,
  })  : _inner = inner,
        _buffer = buffer;

  final TtsService _inner;
  final TtsReplyBuffer _buffer;

  @override
  ValueListenable<bool> get isSpeaking => _inner.isSpeaking;

  @override
  Future<void> speak(String text, {String? languageCode}) async {
    await _inner.speak(text, languageCode: languageCode);
    // Only reached if the inner call did not throw.
    _buffer.record(text, languageCode: languageCode);
  }

  @override
  Future<void> stop() => _inner.stop();

  @override
  void dispose() => _inner.dispose();
}
