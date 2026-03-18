import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/features/recording/data/groq_stt_service.dart';
import 'package:voice_agent/features/recording/data/recording_service_impl.dart';
import 'package:voice_agent/features/recording/domain/recording_service.dart';
import 'package:voice_agent/features/recording/domain/recording_state.dart';
import 'package:voice_agent/features/recording/domain/stt_service.dart';
import 'package:voice_agent/features/recording/presentation/recording_controller.dart';

final recordingServiceProvider = Provider<RecordingService>((ref) {
  return RecordingServiceImpl();
});

final sttServiceProvider = Provider<SttService>((ref) {
  return GroqSttService(ref);
});

final recordingControllerProvider =
    StateNotifierProvider<RecordingController, RecordingState>((ref) {
  return RecordingController(
    ref.watch(recordingServiceProvider),
    ref.watch(sttServiceProvider),
  );
});
