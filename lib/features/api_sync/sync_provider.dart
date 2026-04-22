import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/core/audio/audio_feedback_provider.dart';
import 'package:voice_agent/core/config/app_config_provider.dart';
import 'package:voice_agent/core/network/connectivity_service.dart';
import 'package:voice_agent/core/providers/agent_reply_provider.dart';
import 'package:voice_agent/core/providers/api_client_provider.dart';
import 'package:voice_agent/core/providers/app_foreground_provider.dart';
import 'package:voice_agent/core/providers/session_active_provider.dart';
import 'package:voice_agent/core/storage/storage_provider.dart';
import 'package:voice_agent/core/tts/tts_provider.dart';
import 'package:voice_agent/features/api_sync/api_config.dart';
import 'package:voice_agent/features/api_sync/sync_worker.dart';

final connectivityServiceProvider = Provider<ConnectivityService>((ref) {
  return ConnectivityService();
});

final connectivityStatusProvider = StreamProvider<ConnectivityStatus>((ref) {
  return ref.watch(connectivityServiceProvider).statusStream;
});

final syncWorkerProvider = Provider<SyncWorker>((ref) {
  final worker = SyncWorker(
    storageService: ref.watch(storageServiceProvider),
    apiClient: ref.watch(apiClientProvider),
    apiConfig: ref.watch(apiConfigProvider),
    connectivityService: ref.watch(connectivityServiceProvider),
    ttsService: ref.watch(ttsServiceProvider),
    getTtsEnabled: () => ref.read(appConfigProvider).ttsEnabled,
    audioFeedbackService: ref.watch(audioFeedbackServiceProvider),
    // P027 / ADR-NET-002: drain while foregrounded OR while a hands-free
    // session is active. P028: TTS no longer needs a separate foreground
    // gate — Android mediaPlayback FG service type + iOS playAndRecord
    // cover background TTS.
    shouldProcessQueue: () =>
        ref.read(appForegroundedProvider) || ref.read(sessionActiveProvider),
    onAgentReply: (reply) {
      ref.read(latestAgentReplyProvider.notifier).state = reply;
    },
  );

  worker.start();

  // P027: on idle→active session transition, kick an immediate drain so the
  // first utterance does not wait for the next 5 s poll tick.
  ref.listen<bool>(sessionActiveProvider, (prev, next) {
    if (next == true && prev != true) {
      worker.kickDrain();
    }
  });

  ref.onDispose(() => worker.stop());

  return worker;
});
