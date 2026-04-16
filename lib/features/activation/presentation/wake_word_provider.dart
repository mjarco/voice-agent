import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/features/activation/data/porcupine_wake_word_service.dart';
import 'package:voice_agent/features/activation/domain/wake_word_service.dart';

final wakeWordServiceProvider = Provider<WakeWordService>((ref) {
  final service = PorcupineWakeWordService();
  ref.onDispose(service.dispose);
  return service;
});
