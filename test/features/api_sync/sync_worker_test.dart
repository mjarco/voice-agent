import 'package:flutter/foundation.dart';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/models/sync_queue_item.dart';
import 'package:voice_agent/core/models/sync_status.dart';
import 'package:voice_agent/core/models/transcript.dart';
import 'package:voice_agent/core/models/transcript_with_status.dart';
import 'package:voice_agent/core/network/api_client.dart';
import 'package:voice_agent/core/audio/audio_feedback_service.dart';
import 'package:voice_agent/core/network/connectivity_service.dart';
import 'package:voice_agent/core/storage/storage_service.dart';
import 'package:voice_agent/core/tts/tts_service.dart';
import 'package:voice_agent/features/api_sync/api_config.dart';
import 'package:voice_agent/features/api_sync/sync_worker.dart';

class FakeStorageService implements StorageService {
  final List<Transcript> transcripts = [];
  final List<SyncQueueItem> queueItems = [];
  final List<String> calls = [];

  @override
  Future<void> saveTranscript(Transcript t) async {
    transcripts.add(t);
  }

  @override
  Future<Transcript?> getTranscript(String id) async {
    return transcripts.where((t) => t.id == id).firstOrNull;
  }

  @override
  Future<List<Transcript>> getTranscripts({int limit = 50, int offset = 0}) async {
    return transcripts;
  }

  @override
  Future<void> deleteTranscript(String id) async {
    transcripts.removeWhere((t) => t.id == id);
  }

  @override
  Future<void> enqueue(String transcriptId) async {
    queueItems.add(SyncQueueItem(
      id: 'q-${queueItems.length}',
      transcriptId: transcriptId,
      status: SyncStatus.pending,
      attempts: 0,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    ));
  }

  @override
  Future<List<SyncQueueItem>> getPendingItems() async {
    return queueItems
        .where((i) => i.status == SyncStatus.pending)
        .toList();
  }

  @override
  Future<void> markSending(String id) async {
    calls.add('markSending:$id');
    final idx = queueItems.indexWhere((i) => i.id == id);
    if (idx >= 0) {
      final item = queueItems[idx];
      queueItems[idx] = SyncQueueItem(
        id: item.id,
        transcriptId: item.transcriptId,
        status: SyncStatus.sending,
        attempts: item.attempts + 1,
        lastAttemptAt: DateTime.now().millisecondsSinceEpoch,
        createdAt: item.createdAt,
      );
    }
  }

  @override
  Future<void> markSent(String id) async {
    calls.add('markSent:$id');
    queueItems.removeWhere((i) => i.id == id);
  }

  @override
  Future<void> markFailed(String id, String error, {int? overrideAttempts}) async {
    calls.add('markFailed:$id:$error${overrideAttempts != null ? ':override=$overrideAttempts' : ''}');
    final idx = queueItems.indexWhere((i) => i.id == id);
    if (idx >= 0) {
      final item = queueItems[idx];
      queueItems[idx] = SyncQueueItem(
        id: item.id,
        transcriptId: item.transcriptId,
        status: SyncStatus.failed,
        attempts: overrideAttempts ?? item.attempts,
        lastAttemptAt: item.lastAttemptAt,
        errorMessage: error,
        createdAt: item.createdAt,
      );
    }
  }

  @override
  Future<void> markPendingForRetry(String id) async {
    calls.add('markPendingForRetry:$id');
    final idx = queueItems.indexWhere((i) => i.id == id);
    if (idx >= 0) {
      final item = queueItems[idx];
      queueItems[idx] = SyncQueueItem(
        id: item.id,
        transcriptId: item.transcriptId,
        status: SyncStatus.pending,
        attempts: item.attempts,
        lastAttemptAt: item.lastAttemptAt,
        errorMessage: null,
        createdAt: item.createdAt,
      );
    }
  }

  @override
  Future<List<SyncQueueItem>> getFailedItems({int? maxAttempts}) async {
    return queueItems.where((i) {
      if (i.status != SyncStatus.failed) return false;
      if (maxAttempts != null && i.attempts >= maxAttempts) return false;
      return true;
    }).toList();
  }

  @override
  Future<String> getDeviceId() async => 'test-device';

  @override
  Future<List<TranscriptWithStatus>> getTranscriptsWithStatus({
    int limit = 20,
    int offset = 0,
  }) async => [];

  @override
  Future<void> reactivateForResend(String transcriptId) async {}

  @override
  Future<int> recoverStaleSending() async => 0;
}

class FakeApiClient extends ApiClient {
  ApiResult nextResult = const ApiSuccess();
  String? nextBody;

  @override
  Future<ApiResult> post(
    Transcript transcript, {
    required String url,
    String? token,
  }) async {
    if (nextResult is ApiSuccess) return ApiSuccess(body: nextBody);
    return nextResult;
  }
}

class _SpyTtsService implements TtsService {
  @override ValueListenable<bool> get isSpeaking => ValueNotifier(false);
  final List<String> log = [];

  @override
  Future<void> speak(String text, {String? languageCode}) async {
    log.add('speak:$text:$languageCode');
  }

  @override
  Future<void> stop() async {
    log.add('stop');
  }

  @override
  void dispose() {}
}

class _StubAudioFeedbackService implements AudioFeedbackService {
  @override Future<void> startProcessingFeedback() async {}
  @override Future<void> stopLoop() async {}
  @override Future<void> playSuccess() async {}
  @override Future<void> playError() async {}
  @override Future<void> playWakeWordAcknowledgment() async {}
  @override void dispose() {}
}

class FakeConnectivityService extends ConnectivityService {
  final _controller = StreamController<ConnectivityStatus>.broadcast();

  @override
  Stream<ConnectivityStatus> get statusStream => _controller.stream;

  @override
  Future<ConnectivityStatus> get currentStatus async =>
      ConnectivityStatus.online;

  void emitStatus(ConnectivityStatus status) {
    _controller.add(status);
  }
}

void main() {
  late FakeStorageService storage;
  late FakeApiClient apiClient;
  late FakeConnectivityService connectivity;
  late _SpyTtsService tts;
  late bool ttsEnabled;
  late SyncWorker worker;

  final transcript = Transcript(
    id: 'tx-1',
    text: 'Hello',
    language: 'en',
    deviceId: 'dev',
    createdAt: 1000,
  );

  setUp(() {
    storage = FakeStorageService();
    apiClient = FakeApiClient();
    connectivity = FakeConnectivityService();
    tts = _SpyTtsService();
    ttsEnabled = true;
    worker = SyncWorker(
      storageService: storage,
      apiClient: apiClient,
      apiConfig: const ApiConfig(url: 'https://example.com/api', token: 'tok'),
      connectivityService: connectivity,
      ttsService: tts,
      getTtsEnabled: () => ttsEnabled,
      audioFeedbackService: _StubAudioFeedbackService(),
      isAppForegrounded: () => true,
    );
  });

  tearDown(() {
    worker.stop();
  });

  group('SyncWorker', () {
    test('initial state is idle', () {
      expect(worker.state, SyncWorkerState.idle);
    });

    test('start transitions to running', () {
      worker.start();
      expect(worker.state, SyncWorkerState.running);
    });

    test('pause transitions to paused', () {
      worker.start();
      worker.pause();
      expect(worker.state, SyncWorkerState.paused);
    });

    test('resume transitions from paused to running', () {
      worker.start();
      worker.pause();
      worker.resume();
      expect(worker.state, SyncWorkerState.running);
    });

    test('stop transitions to stopped', () {
      worker.start();
      worker.stop();
      expect(worker.state, SyncWorkerState.stopped);
    });

    test('drains pending item and marks sent on success', () async {
      await storage.saveTranscript(transcript);
      await storage.enqueue('tx-1');
      apiClient.nextResult = const ApiSuccess();

      worker.start();
      await Future.delayed(const Duration(milliseconds: 100));
      worker.stop();

      expect(storage.queueItems, isEmpty);
      expect(storage.calls, contains('markSent:q-0'));
    });

    test('marks failed on permanent failure', () async {
      await storage.saveTranscript(transcript);
      await storage.enqueue('tx-1');
      apiClient.nextResult = const ApiPermanentFailure(
        statusCode: 400,
        message: 'Bad request',
      );

      worker.start();
      await Future.delayed(const Duration(milliseconds: 100));
      worker.stop();

      expect(storage.calls.any((c) => c.startsWith('markFailed:q-0')), isTrue);
      expect(storage.queueItems.first.status, SyncStatus.failed);
    });

    test('marks failed on transient failure', () async {
      await storage.saveTranscript(transcript);
      await storage.enqueue('tx-1');
      apiClient.nextResult = const ApiTransientFailure(reason: 'timeout');

      worker.start();
      await Future.delayed(const Duration(milliseconds: 100));
      worker.stop();

      expect(storage.calls.any((c) => c.startsWith('markFailed:q-0')), isTrue);
    });

    test('skips drain when API URL is null', () async {
      worker = SyncWorker(
        storageService: storage,
        apiClient: apiClient,
        apiConfig: const ApiConfig(), // url is null
        connectivityService: connectivity,
        ttsService: tts,
        getTtsEnabled: () => ttsEnabled,
        audioFeedbackService: _StubAudioFeedbackService(),
        isAppForegrounded: () => true,
      );

      await storage.saveTranscript(transcript);
      await storage.enqueue('tx-1');

      worker.start();
      await Future.delayed(const Duration(milliseconds: 100));
      worker.stop();

      // Nothing should have been processed
      expect(storage.calls, isEmpty);
      expect(storage.queueItems.length, 1);
    });

    test('pauses on offline connectivity', () async {
      worker.start();
      expect(worker.state, SyncWorkerState.running);

      connectivity.emitStatus(ConnectivityStatus.offline);
      await Future.delayed(const Duration(milliseconds: 50));

      expect(worker.state, SyncWorkerState.paused);
    });

    test('resumes on online connectivity after pause', () async {
      worker.start();
      connectivity.emitStatus(ConnectivityStatus.offline);
      await Future.delayed(const Duration(milliseconds: 50));
      expect(worker.state, SyncWorkerState.paused);

      connectivity.emitStatus(ConnectivityStatus.online);
      await Future.delayed(const Duration(milliseconds: 50));
      expect(worker.state, SyncWorkerState.running);
    });

    group('TTS playback', () {
      test('parses message+language → stop() then speak()', () async {
        await storage.saveTranscript(transcript);
        await storage.enqueue('tx-1');
        apiClient.nextBody = '{"message": "Understood", "language": "pl"}';

        worker.start();
        await Future.delayed(const Duration(milliseconds: 100));
        worker.stop();

        expect(tts.log, ['stop', 'speak:Understood:pl']);
      });

      test('stop() is called before speak()', () async {
        await storage.saveTranscript(transcript);
        await storage.enqueue('tx-1');
        apiClient.nextBody = '{"message": "ok", "language": "en"}';

        worker.start();
        await Future.delayed(const Duration(milliseconds: 100));
        worker.stop();

        final stopIdx = tts.log.indexOf('stop');
        final speakIdx = tts.log.indexWhere((e) => e.startsWith('speak:'));
        expect(stopIdx, lessThan(speakIdx));
      });

      test('ignores non-JSON body', () async {
        await storage.saveTranscript(transcript);
        await storage.enqueue('tx-1');
        apiClient.nextBody = 'not json at all';

        worker.start();
        await Future.delayed(const Duration(milliseconds: 100));
        worker.stop();

        expect(tts.log, isEmpty);
      });

      test('ignores JSON with no message field', () async {
        await storage.saveTranscript(transcript);
        await storage.enqueue('tx-1');
        apiClient.nextBody = '{"status": "ok"}';

        worker.start();
        await Future.delayed(const Duration(milliseconds: 100));
        worker.stop();

        expect(tts.log, isEmpty);
      });

      test('does not speak when ttsEnabled is false', () async {
        await storage.saveTranscript(transcript);
        await storage.enqueue('tx-1');
        apiClient.nextBody = '{"message": "hello"}';
        ttsEnabled = false;

        worker.start();
        await Future.delayed(const Duration(milliseconds: 100));
        worker.stop();

        expect(tts.log, isEmpty);
      });
    });
  });

  group('onAgentReply callback', () {
    test('is called with message on ApiSuccess', () async {
      String? receivedReply;
      worker = SyncWorker(
        storageService: storage,
        apiClient: apiClient,
        apiConfig: const ApiConfig(url: 'https://example.com/api', token: 'tok'),
        connectivityService: connectivity,
        ttsService: tts,
        getTtsEnabled: () => ttsEnabled,
        audioFeedbackService: _StubAudioFeedbackService(),
        isAppForegrounded: () => true,
        onAgentReply: (reply) => receivedReply = reply,
      );

      await storage.saveTranscript(transcript);
      await storage.enqueue('tx-1');
      apiClient.nextBody = '{"message": "hello"}';

      worker.start();
      await Future.delayed(const Duration(milliseconds: 100));
      worker.stop();

      expect(receivedReply, 'hello');
    });

    test('is called even when ttsEnabled is false', () async {
      String? receivedReply;
      ttsEnabled = false;
      worker = SyncWorker(
        storageService: storage,
        apiClient: apiClient,
        apiConfig: const ApiConfig(url: 'https://example.com/api', token: 'tok'),
        connectivityService: connectivity,
        ttsService: tts,
        getTtsEnabled: () => ttsEnabled,
        audioFeedbackService: _StubAudioFeedbackService(),
        isAppForegrounded: () => true,
        onAgentReply: (reply) => receivedReply = reply,
      );

      await storage.saveTranscript(transcript);
      await storage.enqueue('tx-1');
      apiClient.nextBody = '{"message": "hello"}';

      worker.start();
      await Future.delayed(const Duration(milliseconds: 100));
      worker.stop();

      expect(receivedReply, 'hello');
      expect(tts.log, isEmpty); // TTS not called
    });

    test('is NOT called on ApiPermanentFailure', () async {
      String? receivedReply;
      worker = SyncWorker(
        storageService: storage,
        apiClient: apiClient,
        apiConfig: const ApiConfig(url: 'https://example.com/api', token: 'tok'),
        connectivityService: connectivity,
        ttsService: tts,
        getTtsEnabled: () => ttsEnabled,
        audioFeedbackService: _StubAudioFeedbackService(),
        isAppForegrounded: () => true,
        onAgentReply: (reply) => receivedReply = reply,
      );

      await storage.saveTranscript(transcript);
      await storage.enqueue('tx-1');
      apiClient.nextResult = const ApiPermanentFailure(statusCode: 400, message: 'Bad');

      worker.start();
      await Future.delayed(const Duration(milliseconds: 100));
      worker.stop();

      expect(receivedReply, isNull);
    });

    test('is NOT called when success body has no message field', () async {
      String? receivedReply;
      worker = SyncWorker(
        storageService: storage,
        apiClient: apiClient,
        apiConfig: const ApiConfig(url: 'https://example.com/api', token: 'tok'),
        connectivityService: connectivity,
        ttsService: tts,
        getTtsEnabled: () => ttsEnabled,
        audioFeedbackService: _StubAudioFeedbackService(),
        isAppForegrounded: () => true,
        onAgentReply: (reply) => receivedReply = reply,
      );

      await storage.saveTranscript(transcript);
      await storage.enqueue('tx-1');
      apiClient.nextBody = '{"status": "ok"}';

      worker.start();
      await Future.delayed(const Duration(milliseconds: 100));
      worker.stop();

      expect(receivedReply, isNull);
    });
  });

  group('permanent failure discrimination', () {
    test('permanent failure sets overrideAttempts to exhaust budget', () async {
      await storage.saveTranscript(transcript);
      await storage.enqueue('tx-1');
      apiClient.nextResult = const ApiPermanentFailure(
        statusCode: 400,
        message: 'Validation error',
      );

      worker.start();
      await Future.delayed(const Duration(milliseconds: 100));
      worker.stop();

      // Verify markFailed was called with overrideAttempts
      expect(
        storage.calls.any((c) => c.contains('override=10')),
        isTrue,
      );
      // Item should have attempts=10
      expect(storage.queueItems.first.attempts, 10);
    });

    test('permanent failure is excluded from retry promotion', () async {
      await storage.saveTranscript(transcript);
      await storage.enqueue('tx-1');
      apiClient.nextResult = const ApiPermanentFailure(
        statusCode: 400,
        message: 'Bad request',
      );

      worker.start();
      await Future.delayed(const Duration(milliseconds: 200));

      // After drain, item is failed with attempts=10
      expect(storage.queueItems.first.status, SyncStatus.failed);
      expect(storage.queueItems.first.attempts, 10);

      // getFailedItems with maxAttempts=10 should exclude it
      final retryable = await storage.getFailedItems(maxAttempts: 10);
      expect(retryable, isEmpty);

      worker.stop();
    });

    test('transient failure without overrideAttempts leaves retry budget intact', () async {
      await storage.saveTranscript(transcript);
      await storage.enqueue('tx-1');
      apiClient.nextResult = const ApiTransientFailure(reason: 'timeout');

      worker.start();
      await Future.delayed(const Duration(milliseconds: 100));
      worker.stop();

      // Should NOT have overrideAttempts in the call
      expect(
        storage.calls.any((c) => c.contains('override=')),
        isFalse,
      );
      // Attempts = 1 (from markSending increment)
      expect(storage.queueItems.first.attempts, 1);
    });
  });

  group('retry promotion (_promoteEligibleRetries)', () {
    test('promotes failed item whose backoff has elapsed', () async {
      await storage.saveTranscript(transcript);
      await storage.enqueue('tx-1');

      // Manually simulate a failed item with old lastAttemptAt
      final idx = storage.queueItems.indexWhere((i) => i.transcriptId == 'tx-1');
      storage.queueItems[idx] = SyncQueueItem(
        id: storage.queueItems[idx].id,
        transcriptId: 'tx-1',
        status: SyncStatus.failed,
        attempts: 1,
        lastAttemptAt: DateTime.now().millisecondsSinceEpoch - 60000, // 60s ago
        errorMessage: 'timeout',
        createdAt: 1000,
      );

      // Don't let drain actually re-process it — just check promotion
      apiClient.nextResult = const ApiSuccess();
      worker.start();
      await Future.delayed(const Duration(milliseconds: 100));
      worker.stop();

      // Should have been promoted to pending
      expect(
        storage.calls.any((c) => c.startsWith('markPendingForRetry:')),
        isTrue,
      );
    });

    test('does not promote item whose backoff has not elapsed', () async {
      await storage.saveTranscript(transcript);
      await storage.enqueue('tx-1');

      // Simulate failed item with very recent lastAttemptAt
      final idx = storage.queueItems.indexWhere((i) => i.transcriptId == 'tx-1');
      storage.queueItems[idx] = SyncQueueItem(
        id: storage.queueItems[idx].id,
        transcriptId: 'tx-1',
        status: SyncStatus.failed,
        attempts: 1,
        lastAttemptAt: DateTime.now().millisecondsSinceEpoch, // just now
        errorMessage: 'timeout',
        createdAt: 1000,
      );

      worker.start();
      await Future.delayed(const Duration(milliseconds: 100));
      worker.stop();

      // Should NOT have been promoted
      expect(
        storage.calls.any((c) => c.startsWith('markPendingForRetry:')),
        isFalse,
      );
    });
  });

  group('foreground gating', () {
    test('drain skips processing when app is backgrounded', () async {
      bool foregrounded = false;
      worker = SyncWorker(
        storageService: storage,
        apiClient: apiClient,
        apiConfig: const ApiConfig(url: 'https://example.com/api', token: 'tok'),
        connectivityService: connectivity,
        ttsService: tts,
        getTtsEnabled: () => ttsEnabled,
        audioFeedbackService: _StubAudioFeedbackService(),
        isAppForegrounded: () => foregrounded,
      );

      await storage.saveTranscript(transcript);
      await storage.enqueue('tx-1');

      worker.start();
      await Future.delayed(const Duration(milliseconds: 100));

      // Item should still be pending — drain was gated
      expect(storage.queueItems.first.status, SyncStatus.pending);
      expect(
        storage.calls.any((c) => c.startsWith('markSending:')),
        isFalse,
      );

      worker.stop();
    });

    test('drain processes items when app returns to foreground', () async {
      bool foregrounded = false;
      worker = SyncWorker(
        storageService: storage,
        apiClient: apiClient,
        apiConfig: const ApiConfig(url: 'https://example.com/api', token: 'tok'),
        connectivityService: connectivity,
        ttsService: tts,
        getTtsEnabled: () => ttsEnabled,
        audioFeedbackService: _StubAudioFeedbackService(),
        isAppForegrounded: () => foregrounded,
      );

      await storage.saveTranscript(transcript);
      await storage.enqueue('tx-1');
      apiClient.nextResult = const ApiSuccess();

      worker.start();
      await Future.delayed(const Duration(milliseconds: 100));

      // Still pending
      expect(storage.queueItems.first.status, SyncStatus.pending);

      // Simulate foreground
      foregrounded = true;
      await Future.delayed(const Duration(seconds: 6));

      // Now processed
      expect(
        storage.calls.any((c) => c.startsWith('markSent:')),
        isTrue,
      );

      worker.stop();
    });
  });

  group('backoffForAttempt', () {
    test('attempt 0 returns zero', () {
      expect(SyncWorker.backoffForAttempt(0), Duration.zero);
    });

    test('attempt 1 returns 30 seconds', () {
      expect(SyncWorker.backoffForAttempt(1), const Duration(seconds: 30));
    });

    test('attempt 3 returns 5 minutes', () {
      expect(SyncWorker.backoffForAttempt(3), const Duration(minutes: 5));
    });

    test('attempt 10 returns 1 hour (capped)', () {
      expect(SyncWorker.backoffForAttempt(10), const Duration(hours: 1));
    });
  });
}
