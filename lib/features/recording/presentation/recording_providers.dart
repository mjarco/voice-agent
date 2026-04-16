import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';
import 'package:voice_agent/core/providers/activation_providers.dart';
import 'package:voice_agent/features/recording/data/groq_stt_service.dart';
import 'package:voice_agent/features/recording/data/hands_free_orchestrator.dart';
import 'package:voice_agent/features/recording/data/recording_service_impl.dart';
import 'package:voice_agent/features/recording/data/vad_service_impl.dart';
import 'package:voice_agent/features/recording/domain/hands_free_engine.dart';
import 'package:voice_agent/features/recording/domain/recording_service.dart';
import 'package:voice_agent/features/recording/domain/hands_free_session_state.dart';
import 'package:voice_agent/features/recording/domain/recording_state.dart';
import 'package:voice_agent/features/recording/domain/stt_service.dart';
import 'package:voice_agent/features/recording/domain/vad_service.dart';
import 'package:voice_agent/features/recording/presentation/hands_free_controller.dart';
import 'package:voice_agent/features/recording/presentation/recording_controller.dart';

final recordingServiceProvider = Provider<RecordingService>((ref) {
  return RecordingServiceImpl();
});

final sttServiceProvider = Provider<SttService>((ref) {
  return GroqSttService(ref);
});

final vadServiceProvider = Provider<VadService>((ref) {
  return VadServiceImpl();
});

final handsFreeEngineProvider = Provider<HandsFreeEngine>((ref) {
  return HandsFreeOrchestrator(
    AudioRecorder(),
    ref.watch(vadServiceProvider),
  );
});

final handsFreeControllerProvider =
    StateNotifierProvider<HandsFreeController, HandsFreeSessionState>((ref) {
  final controller = HandsFreeController(ref);

  // Watch activation events from wake word / shortcut and trigger a session.
  ref.listen(activationEventProvider, (_, event) {
    if (event != null) {
      controller.startSession(triggeredByActivation: true);
      // Clear the event after consuming it.
      ref.read(activationEventProvider.notifier).state = null;
    }
  });

  return controller;
});

final recordingControllerProvider =
    StateNotifierProvider<RecordingController, RecordingState>((ref) {
  return RecordingController(
    ref.watch(recordingServiceProvider),
    ref.watch(sttServiceProvider),
    ref,
  );
});
