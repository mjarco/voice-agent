import 'dart:async';
import 'dart:convert';

import 'package:voice_agent/core/audio/audio_feedback_service.dart';
import 'package:voice_agent/core/network/api_client.dart';
import 'package:voice_agent/core/network/connectivity_service.dart';
import 'package:voice_agent/core/storage/storage_service.dart';
import 'package:voice_agent/core/tts/tts_service.dart';
import 'package:voice_agent/features/api_sync/api_config.dart';

enum SyncWorkerState { idle, running, paused, stopped }

class SyncWorker {
  SyncWorker({
    required this.storageService,
    required this.apiClient,
    required this.apiConfig,
    required this.connectivityService,
    required this.ttsService,
    required this.getTtsEnabled,
    required this.audioFeedbackService,
    this.onAgentReply,
  });

  final StorageService storageService;
  final ApiClient apiClient;
  final ApiConfig apiConfig;
  final ConnectivityService connectivityService;
  final TtsService ttsService;
  final bool Function() getTtsEnabled;
  final AudioFeedbackService audioFeedbackService;
  final void Function(String reply)? onAgentReply;

  SyncWorkerState _state = SyncWorkerState.idle;
  SyncWorkerState get state => _state;

  StreamSubscription<ConnectivityStatus>? _connectivitySub;
  Timer? _pollTimer;

  static const _pollInterval = Duration(seconds: 5);
  static const _maxRetries = 10;

  /// Backoff delays indexed by attempt number (0-based).
  static const _backoffDelays = [
    Duration(seconds: 30), // attempt 1
    Duration(minutes: 1), // attempt 2
    Duration(minutes: 5), // attempt 3
    Duration(minutes: 15), // attempt 4
    Duration(hours: 1), // attempt 5
    Duration(hours: 1), // attempt 6
    Duration(hours: 1), // attempt 7
    Duration(hours: 1), // attempt 8
    Duration(hours: 1), // attempt 9
  ];

  void start() {
    if (_state == SyncWorkerState.running) return;
    _state = SyncWorkerState.running;

    _connectivitySub = connectivityService.statusStream.listen((status) {
      if (status == ConnectivityStatus.offline) {
        pause();
      } else if (_state == SyncWorkerState.paused) {
        resume();
      }
    });

    _scheduleDrain();
  }

  void pause() {
    if (_state != SyncWorkerState.running) return;
    _state = SyncWorkerState.paused;
    _pollTimer?.cancel();
  }

  void resume() {
    if (_state != SyncWorkerState.paused) return;
    _state = SyncWorkerState.running;
    _scheduleDrain();
  }

  void stop() {
    _state = SyncWorkerState.stopped;
    _pollTimer?.cancel();
    _connectivitySub?.cancel();
  }

  void _scheduleDrain() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _drain());
    // Also drain immediately
    _drain();
  }

  Future<void> _drain() async {
    if (_state != SyncWorkerState.running) return;

    // Check if API URL is configured
    final url = apiConfig.url;
    if (url == null || url.isEmpty) return;

    // Promote eligible retries
    await _promoteEligibleRetries();

    // Get pending items
    final items = await storageService.getPendingItems();
    if (items.isEmpty) return;

    // Process first item (FIFO)
    final item = items.first;

    await storageService.markSending(item.id);

    final transcript = await storageService.getTranscript(item.transcriptId);
    if (transcript == null) {
      // Orphaned queue item — remove it
      await storageService.markSent(item.id);
      unawaited(audioFeedbackService.playError());
      return;
    }

    final result = await apiClient.post(
      transcript,
      url: url,
      token: apiConfig.token,
    );

    switch (result) {
      case ApiSuccess(:final body):
        await storageService.markSent(item.id);
        unawaited(audioFeedbackService.playSuccess());
        _handleReply(body);
      case ApiPermanentFailure(:final message):
        await storageService.markFailed(item.id, message);
        unawaited(audioFeedbackService.playError());
      case ApiTransientFailure(:final reason):
        final attempts = item.attempts + 1; // markSending already incremented
        if (attempts >= _maxRetries) {
          await storageService.markFailed(
            item.id,
            'Max retries exceeded ($attempts attempts). Last error: $reason',
          );
        } else {
          await storageService.markFailed(item.id, reason);
        }
        unawaited(audioFeedbackService.playError());
    }
  }

  void _handleReply(String? body) {
    if (body == null) return;
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      final message = json['message'] as String?;
      if (message == null || message.isEmpty) return;
      final language = json['language'] as String?;
      if (getTtsEnabled()) {
        unawaited(ttsService.stop().then((_) => ttsService.speak(message, languageCode: language)));
      }
      onAgentReply?.call(message);
    } catch (_) {
      // Non-JSON or unexpected shape — stay silent.
    }
  }

  Future<void> _promoteEligibleRetries() async {
    // Query failed items and check backoff eligibility
    // For simplicity, we get all failed items via a raw approach:
    // getPendingItems only returns pending, so we need to check failed items
    // through the storage service. Since StorageService doesn't expose
    // getFailedItems(), we rely on the fact that markPendingForRetry
    // only transitions failed items. We call it for items we know failed
    // from previous drain cycles.
    //
    // In practice, the worker tracks which items it failed and when,
    // but for MVP we skip the promotion step and let failed items stay
    // failed until an external trigger (e.g., user resend from history).
    //
    // TODO: Add getFailedItems() to StorageService for proper backoff promotion
  }

  static Duration backoffForAttempt(int attempt) {
    if (attempt <= 0) return Duration.zero;
    if (attempt > _backoffDelays.length) return _backoffDelays.last;
    return _backoffDelays[attempt - 1];
  }
}
