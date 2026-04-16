import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/core/audio/audio_feedback_provider.dart';
import 'package:voice_agent/core/providers/activation_providers.dart';
import 'package:voice_agent/features/activation/data/platform_channel_bridge.dart';
import 'package:voice_agent/features/activation/domain/activation_state.dart';
import 'package:voice_agent/features/activation/presentation/activation_controller.dart';
import 'package:voice_agent/features/activation/presentation/wake_word_provider.dart';

/// Overridable store for [PlatformChannelBridge]. Tests override this with
/// an in-memory implementation to avoid [SharedPreferencesAsync] platform
/// dependency.
final bridgeStoreProvider = Provider<BridgeStore>((ref) {
  return SharedPreferencesBridgeStore();
});

final activationControllerProvider =
    StateNotifierProvider<ActivationController, ActivationState>((ref) {
  final controller = ActivationController(
    wakeWordService: ref.watch(wakeWordServiceProvider),
    audioFeedback: ref.watch(audioFeedbackServiceProvider),
    ref: ref,
  );

  // Watch session status changes and forward to controller.
  ref.listen(handsFreeSessionStatusProvider, (_, next) {
    controller.onSessionStatusChanged(next);
  });

  // Watch pause requests from manual recording.
  ref.listen(wakeWordPauseRequestProvider, (_, next) {
    controller.onPauseRequest(next);
  });

  // Wire PlatformChannelBridge for native tile/control communication.
  final bridge = PlatformChannelBridge(
    onToggleRequested: () => controller.toggle(),
    onStopRequested: () => controller.stopListening(),
    store: ref.watch(bridgeStoreProvider),
  );
  bridge.start();
  ref.onDispose(bridge.stop);

  // Write activation state to shared preferences for native tiles.
  final removeListener = controller.addListener((state) {
    final stateStr = switch (state) {
      ActivationListening() => 'listening',
      ActivationHandsFreeActive() => 'active',
      ActivationIdle() => 'idle',
      ActivationError() => 'error',
    };
    bridge.writeActivationState(stateStr);
  });
  ref.onDispose(removeListener);

  return controller;
});
