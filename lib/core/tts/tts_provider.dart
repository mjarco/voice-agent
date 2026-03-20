import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/core/tts/flutter_tts_service.dart';
import 'package:voice_agent/core/tts/tts_service.dart';

final ttsServiceProvider = Provider<TtsService>((ref) {
  final tts = FlutterTtsService();
  ref.onDispose(tts.dispose);
  return tts;
});
