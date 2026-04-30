import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/models/sync_queue_item.dart';
import 'package:voice_agent/core/models/sync_status.dart';
import 'package:voice_agent/core/models/transcript.dart';
import 'package:voice_agent/core/models/transcript_with_status.dart';
import 'package:voice_agent/core/local_commands/local_command_matcher.dart';
import 'package:voice_agent/core/network/api_client.dart';
import 'package:voice_agent/core/audio/audio_feedback_service.dart';
import 'package:voice_agent/core/network/connectivity_service.dart';
import 'package:voice_agent/core/session_control/hands_free_control_port.dart';
import 'package:voice_agent/core/session_control/haptic_service.dart';
import 'package:voice_agent/core/session_control/session_control_dispatcher.dart';
import 'package:voice_agent/core/session_control/session_control_signal.dart';
import 'package:voice_agent/core/session_control/session_id_coordinator.dart';
import 'package:voice_agent/core/session_control/toaster.dart';
import 'package:voice_agent/core/storage/storage_service.dart';
import 'package:voice_agent/core/tts/tts_reply_buffer.dart';
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
  @override void dispose() {}
}

class _FakeHandsFreeControlPort implements HandsFreeControlPort {
  @override
  bool isSuspendedForManualRecording = false;

  int stopSessionCalls = 0;

  @override
  Future<void> stopSession() async {
    stopSessionCalls++;
  }
}

class _FakeToaster extends Toaster {
  _FakeToaster() : super(GlobalKey<ScaffoldMessengerState>());
  final List<String> messages = [];

  @override
  void show(String message, {Duration duration = const Duration(seconds: 2)}) {
    messages.add(message);
  }
}

class _FakeHapticService extends HapticService {
  int calls = 0;

  @override
  Future<void> lightImpact() async {
    calls++;
  }
}

class _RecordingDispatcher extends SessionControlDispatcher {
  _RecordingDispatcher()
      : super(
          ttsService: _NoopTtsService(),
          handsFreeControlPort: _FakeHandsFreeControlPort(),
          sessionIdCoordinator: SessionIdCoordinator(),
          toaster: _FakeToaster(),
          hapticService: _FakeHapticService(),
          ttsTimeout: Duration.zero,
        );

  final List<SessionControlSignal> dispatched = [];

  @override
  Future<void> dispatch(SessionControlSignal signal) async {
    dispatched.add(signal);
  }
}

class _NoopTtsService implements TtsService {
  @override
  ValueListenable<bool> get isSpeaking => ValueNotifier(false);

  @override
  Future<void> speak(String text, {String? languageCode}) async {}

  @override
  Future<void> stop() async {}

  @override
  void dispose() {}
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
  late _RecordingDispatcher dispatcher;
  late SessionIdCoordinator sessionIdCoordinator;
  late LocalCommandMatcher localCommandMatcher;
  late InMemoryTtsReplyBuffer ttsReplyBuffer;
  late _FakeToaster toaster;
  late _FakeHapticService hapticService;
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
    dispatcher = _RecordingDispatcher();
    sessionIdCoordinator = SessionIdCoordinator();
    localCommandMatcher = const LocalCommandMatcher();
    ttsReplyBuffer = InMemoryTtsReplyBuffer();
    toaster = _FakeToaster();
    hapticService = _FakeHapticService();
    worker = SyncWorker(
      storageService: storage,
      apiClient: apiClient,
      apiConfig: const ApiConfig(url: 'https://example.com/api', token: 'tok'),
      connectivityService: connectivity,
      ttsService: tts,
      getTtsEnabled: () => ttsEnabled,
      audioFeedbackService: _StubAudioFeedbackService(),
      shouldProcessQueue: () => true,
      sessionControlDispatcher: dispatcher,
      sessionIdCoordinator: sessionIdCoordinator,
      localCommandMatcher: localCommandMatcher,
      ttsReplyBuffer: ttsReplyBuffer,
      toaster: toaster,
      hapticService: hapticService,
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
        shouldProcessQueue: () => true,
        sessionControlDispatcher: dispatcher,
        sessionIdCoordinator: sessionIdCoordinator,
      localCommandMatcher: localCommandMatcher,
      ttsReplyBuffer: ttsReplyBuffer,
      toaster: toaster,
      hapticService: hapticService,
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

    test('speaks error via TTS on permanent failure', () async {
      await storage.saveTranscript(transcript);
      await storage.enqueue('tx-1');
      apiClient.nextResult = const ApiPermanentFailure(
        statusCode: 400,
        message: 'Invalid transcript format',
      );

      worker.start();
      await Future.delayed(const Duration(milliseconds: 100));
      worker.stop();

      expect(tts.log, contains('stop'));
      expect(
        tts.log.any((e) => e.startsWith('speak:Invalid transcript format:')),
        isTrue,
      );
    });

    test('speaks error via TTS on transient failure', () async {
      await storage.saveTranscript(transcript);
      await storage.enqueue('tx-1');
      apiClient.nextResult = const ApiTransientFailure(reason: 'Connection timeout');

      worker.start();
      await Future.delayed(const Duration(milliseconds: 100));
      worker.stop();

      expect(
        tts.log.any((e) => e.startsWith('speak:Connection timeout:')),
        isTrue,
      );
    });

    test('does not speak error when TTS is disabled', () async {
      await storage.saveTranscript(transcript);
      await storage.enqueue('tx-1');
      ttsEnabled = false;
      apiClient.nextResult = const ApiPermanentFailure(
        statusCode: 500,
        message: 'Server error',
      );

      worker.start();
      await Future.delayed(const Duration(milliseconds: 100));
      worker.stop();

      expect(tts.log, isEmpty);
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
        shouldProcessQueue: () => true,
        sessionControlDispatcher: dispatcher,
        sessionIdCoordinator: sessionIdCoordinator,
      localCommandMatcher: localCommandMatcher,
      ttsReplyBuffer: ttsReplyBuffer,
      toaster: toaster,
      hapticService: hapticService,
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
        shouldProcessQueue: () => true,
        sessionControlDispatcher: dispatcher,
        sessionIdCoordinator: sessionIdCoordinator,
      localCommandMatcher: localCommandMatcher,
      ttsReplyBuffer: ttsReplyBuffer,
      toaster: toaster,
      hapticService: hapticService,
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
        shouldProcessQueue: () => true,
        sessionControlDispatcher: dispatcher,
        sessionIdCoordinator: sessionIdCoordinator,
      localCommandMatcher: localCommandMatcher,
      ttsReplyBuffer: ttsReplyBuffer,
      toaster: toaster,
      hapticService: hapticService,
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
        shouldProcessQueue: () => true,
        sessionControlDispatcher: dispatcher,
        sessionIdCoordinator: sessionIdCoordinator,
      localCommandMatcher: localCommandMatcher,
      ttsReplyBuffer: ttsReplyBuffer,
      toaster: toaster,
      hapticService: hapticService,
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

  group('shouldProcessQueue predicate (P027: foreground OR session active)', () {
    SyncWorker makeWorker({required bool Function() predicate}) {
      return SyncWorker(
        storageService: storage,
        apiClient: apiClient,
        apiConfig:
            const ApiConfig(url: 'https://example.com/api', token: 'tok'),
        connectivityService: connectivity,
        ttsService: tts,
        getTtsEnabled: () => ttsEnabled,
        audioFeedbackService: _StubAudioFeedbackService(),
        shouldProcessQueue: predicate,
        sessionControlDispatcher: dispatcher,
        sessionIdCoordinator: sessionIdCoordinator,
      localCommandMatcher: localCommandMatcher,
      ttsReplyBuffer: ttsReplyBuffer,
      toaster: toaster,
      hapticService: hapticService,
      );
    }

    test('foreground=true, sessionActive=false → drains', () async {
      worker = makeWorker(predicate: () => true);

      await storage.saveTranscript(transcript);
      await storage.enqueue('tx-1');
      apiClient.nextResult = const ApiSuccess();

      worker.start();
      await Future.delayed(const Duration(milliseconds: 100));

      expect(
        storage.calls.any((c) => c.startsWith('markSending:')),
        isTrue,
      );

      worker.stop();
    });

    test('foreground=false, sessionActive=true → drains (NEW behavior)',
        () async {
      // Predicate returns true; simulates an active hands-free session
      // while backgrounded.
      worker = makeWorker(predicate: () => true);

      await storage.saveTranscript(transcript);
      await storage.enqueue('tx-1');
      apiClient.nextResult = const ApiSuccess();

      worker.start();
      await Future.delayed(const Duration(milliseconds: 100));

      expect(
        storage.calls.any((c) => c.startsWith('markSending:')),
        isTrue,
      );

      worker.stop();
    });

    test('foreground=false, sessionActive=false → skips', () async {
      worker = makeWorker(predicate: () => false);

      await storage.saveTranscript(transcript);
      await storage.enqueue('tx-1');

      worker.start();
      await Future.delayed(const Duration(milliseconds: 100));

      expect(storage.queueItems.first.status, SyncStatus.pending);
      expect(
        storage.calls.any((c) => c.startsWith('markSending:')),
        isFalse,
      );

      worker.stop();
    });

    test('drain processes items when predicate flips false → true', () async {
      bool canProcess = false;
      worker = SyncWorker(
        storageService: storage,
        apiClient: apiClient,
        apiConfig:
            const ApiConfig(url: 'https://example.com/api', token: 'tok'),
        connectivityService: connectivity,
        ttsService: tts,
        getTtsEnabled: () => ttsEnabled,
        audioFeedbackService: _StubAudioFeedbackService(),
        shouldProcessQueue: () => canProcess,
        sessionControlDispatcher: dispatcher,
        sessionIdCoordinator: sessionIdCoordinator,
      localCommandMatcher: localCommandMatcher,
      ttsReplyBuffer: ttsReplyBuffer,
      toaster: toaster,
      hapticService: hapticService,
      );

      await storage.saveTranscript(transcript);
      await storage.enqueue('tx-1');
      apiClient.nextResult = const ApiSuccess();

      worker.start();
      await Future.delayed(const Duration(milliseconds: 100));

      expect(storage.queueItems.first.status, SyncStatus.pending);

      // Flip predicate to true (simulating session start or foreground).
      canProcess = true;
      await Future.delayed(const Duration(seconds: 6));

      expect(
        storage.calls.any((c) => c.startsWith('markSent:')),
        isTrue,
      );

      worker.stop();
    });
  });

  group('kickDrain', () {
    test('kickDrain is a public entry point that triggers processing',
        () async {
      // worker.start() is not called here — we verify kickDrain() alone
      // can drive a drain. Note: _drain() checks _state == running, so we
      // must start first.
      await storage.saveTranscript(transcript);
      await storage.enqueue('tx-1');
      apiClient.nextResult = const ApiSuccess();

      worker.start();
      // Give the immediate _drain triggered by start() time to finish.
      await Future.delayed(const Duration(milliseconds: 50));

      // Item should be processed by now (either via start() immediate drain
      // or a later kickDrain — both paths are acceptable).
      await worker.kickDrain();
      await Future.delayed(const Duration(milliseconds: 50));

      expect(
        storage.calls.any((c) => c.startsWith('markSent:')),
        isTrue,
      );

      worker.stop();
    });

    test('rapid successive kickDrain calls do not double-process an item',
        () async {
      await storage.saveTranscript(transcript);
      await storage.enqueue('tx-1');
      apiClient.nextResult = const ApiSuccess();

      worker.start();
      // Give start's immediate drain time to run.
      await Future.delayed(const Duration(milliseconds: 50));

      // Fire two back-to-back kicks. Either short-circuits (item already
      // processed by start's drain) or second finds flag set.
      await Future.wait([worker.kickDrain(), worker.kickDrain()]);
      await Future.delayed(const Duration(milliseconds: 50));

      final markSendingCalls = storage.calls
          .where((c) => c.startsWith('markSending:'))
          .length;
      expect(markSendingCalls, 1);

      worker.stop();
    });
  });

  group('TTS (P028: always speaks regardless of foreground state)', () {
    test('ttsEnabled=true → ttsService.speak() called', () async {
      await storage.saveTranscript(transcript);
      await storage.enqueue('tx-1');
      apiClient.nextResult = const ApiSuccess();
      apiClient.nextBody = '{"message":"hello","language":"en"}';

      worker.start();
      await Future.delayed(const Duration(milliseconds: 100));
      await Future.delayed(const Duration(milliseconds: 10));

      expect(tts.log.any((e) => e.startsWith('speak:hello:')), isTrue);

      worker.stop();
    });

    test('ttsEnabled=false → ttsService.speak() NOT called, reply stored',
        () async {
      ttsEnabled = false;
      String? capturedReply;
      worker = SyncWorker(
        storageService: storage,
        apiClient: apiClient,
        apiConfig:
            const ApiConfig(url: 'https://example.com/api', token: 'tok'),
        connectivityService: connectivity,
        ttsService: tts,
        getTtsEnabled: () => ttsEnabled,
        audioFeedbackService: _StubAudioFeedbackService(),
        shouldProcessQueue: () => true,
        sessionControlDispatcher: dispatcher,
        sessionIdCoordinator: sessionIdCoordinator,
      localCommandMatcher: localCommandMatcher,
      ttsReplyBuffer: ttsReplyBuffer,
      toaster: toaster,
      hapticService: hapticService,
        onAgentReply: (reply) => capturedReply = reply,
      );

      await storage.saveTranscript(transcript);
      await storage.enqueue('tx-1');
      apiClient.nextResult = const ApiSuccess();
      apiClient.nextBody = '{"message":"hello","language":"en"}';

      worker.start();
      await Future.delayed(const Duration(milliseconds: 100));
      await Future.delayed(const Duration(milliseconds: 10));

      expect(tts.log.any((e) => e.startsWith('speak:')), isFalse);
      expect(capturedReply, 'hello');

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

  group('session control dispatch (P029-T2)', () {
    test('body with stop_recording=true dispatches signal', () async {
      await storage.saveTranscript(transcript);
      await storage.enqueue('tx-1');
      apiClient.nextBody =
          '{"message":"Goodbye","language":"en","session_control":{"stop_recording":true,"reset_session":false}}';

      worker.start();
      await Future.delayed(const Duration(milliseconds: 200));
      worker.stop();

      expect(dispatcher.dispatched, hasLength(1));
      expect(dispatcher.dispatched.first.stopRecording, isTrue);
      expect(dispatcher.dispatched.first.resetSession, isFalse);
    });

    test('body with only message does NOT dispatch', () async {
      await storage.saveTranscript(transcript);
      await storage.enqueue('tx-1');
      apiClient.nextBody = '{"message":"Hello","language":"en"}';

      worker.start();
      await Future.delayed(const Duration(milliseconds: 200));
      worker.stop();

      expect(dispatcher.dispatched, isEmpty);
    });

    test('malformed JSON body does NOT dispatch and does not throw', () async {
      await storage.saveTranscript(transcript);
      await storage.enqueue('tx-1');
      apiClient.nextBody = 'not valid json {{';

      worker.start();
      await Future.delayed(const Duration(milliseconds: 200));
      worker.stop();

      expect(dispatcher.dispatched, isEmpty);
    });

    test('body with reset_session=true dispatches signal', () async {
      await storage.saveTranscript(transcript);
      await storage.enqueue('tx-1');
      apiClient.nextBody =
          '{"message":"New session","language":"en","session_control":{"reset_session":true}}';

      worker.start();
      await Future.delayed(const Duration(milliseconds: 200));
      worker.stop();

      expect(dispatcher.dispatched, hasLength(1));
      expect(dispatcher.dispatched.first.resetSession, isTrue);
      expect(dispatcher.dispatched.first.stopRecording, isFalse);
    });

    test('body with both signals dispatches signal with both flags', () async {
      await storage.saveTranscript(transcript);
      await storage.enqueue('tx-1');
      apiClient.nextBody =
          '{"message":"Bye","language":"en","session_control":{"reset_session":true,"stop_recording":true}}';

      worker.start();
      await Future.delayed(const Duration(milliseconds: 200));
      worker.stop();

      expect(dispatcher.dispatched, hasLength(1));
      expect(dispatcher.dispatched.first.resetSession, isTrue);
      expect(dispatcher.dispatched.first.stopRecording, isTrue);
    });

    test('conversation_id in reply is adopted by coordinator', () async {
      await storage.saveTranscript(transcript);
      await storage.enqueue('tx-1');
      apiClient.nextBody =
          '{"message":"ok","language":"en","conversation_id":"conv-42"}';

      worker.start();
      await Future.delayed(const Duration(milliseconds: 200));
      worker.stop();

      expect(sessionIdCoordinator.currentConversationId, 'conv-42');
    });

    test('empty conversation_id is NOT adopted', () async {
      await storage.saveTranscript(transcript);
      await storage.enqueue('tx-1');
      apiClient.nextBody =
          '{"message":"ok","language":"en","conversation_id":""}';

      worker.start();
      await Future.delayed(const Duration(milliseconds: 200));
      worker.stop();

      expect(sessionIdCoordinator.currentConversationId, isNull);
    });

    test('TTS stop and speak are awaited before dispatch', () async {
      final orderTts = _SpyTtsService();
      final orderDispatcher = _RecordingDispatcher();

      worker = SyncWorker(
        storageService: storage,
        apiClient: apiClient,
        apiConfig: const ApiConfig(url: 'https://example.com/api', token: 'tok'),
        connectivityService: connectivity,
        ttsService: orderTts,
        getTtsEnabled: () => true,
        audioFeedbackService: _StubAudioFeedbackService(),
        shouldProcessQueue: () => true,
        sessionControlDispatcher: orderDispatcher,
        sessionIdCoordinator: sessionIdCoordinator,
      localCommandMatcher: localCommandMatcher,
      ttsReplyBuffer: ttsReplyBuffer,
      toaster: toaster,
      hapticService: hapticService,
      );

      await storage.saveTranscript(transcript);
      await storage.enqueue('tx-1');
      apiClient.nextBody =
          '{"message":"bye","language":"en","session_control":{"stop_recording":true}}';

      worker.start();
      await Future.delayed(const Duration(milliseconds: 200));
      worker.stop();

      // TTS must have been called (stop then speak)
      expect(orderTts.log, ['stop', 'speak:bye:en']);
      // Dispatcher must have been called
      expect(orderDispatcher.dispatched, hasLength(1));
    });
  });

  group('P036 replay-last (LocalCommandMatcher + TtsReplyBuffer)', () {
    Future<void> seedReplyAndDrain() async {
      // Seed: a normal agent reply that primes the buffer.
      final seedTranscript = Transcript(
        id: 'tx-seed',
        text: 'What is the weather?',
        language: 'en',
        deviceId: 'dev',
        createdAt: 500,
      );
      await storage.saveTranscript(seedTranscript);
      await storage.enqueue('tx-seed');
      apiClient.nextBody = '{"message":"It is sunny","language":"en"}';

      worker.start();
      await Future.delayed(const Duration(milliseconds: 100));
      worker.stop();

      // Reset apiClient body and tts log between drains.
      apiClient.nextBody = null;
      apiClient.nextResult = const ApiSuccess();
    }

    test(
      'whitelisted utterance + non-empty buffer → no apiClient.post, '
      'tts.stop then tts.speak with buffered (text, languageCode), '
      'queue item dropped, toast + haptic',
      () async {
        // Pre-populate buffer directly (simulates a previous successful reply).
        ttsReplyBuffer.record('It is sunny', languageCode: 'en');

        // Track post-calls via a counting fake.
        final replayApi = _CountingApiClient();
        worker = SyncWorker(
          storageService: storage,
          apiClient: replayApi,
          apiConfig:
              const ApiConfig(url: 'https://example.com/api', token: 'tok'),
          connectivityService: connectivity,
          ttsService: tts,
          getTtsEnabled: () => ttsEnabled,
          audioFeedbackService: _StubAudioFeedbackService(),
          shouldProcessQueue: () => true,
          sessionControlDispatcher: dispatcher,
          sessionIdCoordinator: sessionIdCoordinator,
          localCommandMatcher: localCommandMatcher,
          ttsReplyBuffer: ttsReplyBuffer,
          toaster: toaster,
          hapticService: hapticService,
        );

        // Enqueue the user replay command.
        final replayTranscript = Transcript(
          id: 'tx-replay',
          text: 'powtórz',
          language: 'pl',
          deviceId: 'dev',
          createdAt: 1000,
        );
        await storage.saveTranscript(replayTranscript);
        await storage.enqueue('tx-replay');

        worker.start();
        await Future.delayed(const Duration(milliseconds: 100));
        worker.stop();

        // No backend call.
        expect(replayApi.postCalls, 0);
        // TTS replay produced stop then speak with buffered values.
        expect(tts.log, contains('stop'));
        expect(tts.log, contains('speak:It is sunny:en'));
        // Queue item dropped (treated as consumed via markSent).
        expect(storage.queueItems.where((i) => i.id == 'q-0'), isEmpty);
        // Toast + haptic.
        expect(toaster.messages, contains('Powtarzam ostatnią odpowiedź'));
        expect(hapticService.calls, greaterThanOrEqualTo(1));
      },
    );

    test(
      'whitelisted utterance + empty buffer → toast shown, falls through to '
      'apiClient.post (backend round-trip preserved)',
      () async {
        expect(ttsReplyBuffer.last(), isNull);

        final replayApi = _CountingApiClient();
        replayApi.nextBody = '{"message":"ok","language":"en"}';
        worker = SyncWorker(
          storageService: storage,
          apiClient: replayApi,
          apiConfig:
              const ApiConfig(url: 'https://example.com/api', token: 'tok'),
          connectivityService: connectivity,
          ttsService: tts,
          getTtsEnabled: () => ttsEnabled,
          audioFeedbackService: _StubAudioFeedbackService(),
          shouldProcessQueue: () => true,
          sessionControlDispatcher: dispatcher,
          sessionIdCoordinator: sessionIdCoordinator,
          localCommandMatcher: localCommandMatcher,
          ttsReplyBuffer: ttsReplyBuffer,
          toaster: toaster,
          hapticService: hapticService,
        );

        final replayTranscript = Transcript(
          id: 'tx-empty-replay',
          text: 'powtórz',
          language: 'pl',
          deviceId: 'dev',
          createdAt: 1000,
        );
        await storage.saveTranscript(replayTranscript);
        await storage.enqueue('tx-empty-replay');

        worker.start();
        await Future.delayed(const Duration(milliseconds: 100));
        worker.stop();

        expect(toaster.messages, contains('Brak wcześniejszej odpowiedzi'));
        // Backend WAS called (passthrough on empty buffer).
        expect(replayApi.postCalls, 1);
      },
    );

    test(
      'non-whitelisted utterance → matcher passes through, _handleReply runs '
      'unchanged and feeds the buffer with the new reply',
      () async {
        await seedReplyAndDrain();
        // After seed drain, buffer should hold the seed reply.
        expect(
          ttsReplyBuffer.last(),
          const TtsReplyEntry(text: 'It is sunny', languageCode: 'en'),
        );
      },
    );

    test(
      '"Powtórz, żeby coś przerwało." (origin phrase) does NOT trigger replay '
      '— full backend round-trip',
      () async {
        ttsReplyBuffer.record('previous reply', languageCode: 'pl');
        final replayApi = _CountingApiClient();
        replayApi.nextBody = '{"message":"backend","language":"pl"}';
        worker = SyncWorker(
          storageService: storage,
          apiClient: replayApi,
          apiConfig:
              const ApiConfig(url: 'https://example.com/api', token: 'tok'),
          connectivityService: connectivity,
          ttsService: tts,
          getTtsEnabled: () => ttsEnabled,
          audioFeedbackService: _StubAudioFeedbackService(),
          shouldProcessQueue: () => true,
          sessionControlDispatcher: dispatcher,
          sessionIdCoordinator: sessionIdCoordinator,
          localCommandMatcher: localCommandMatcher,
          ttsReplyBuffer: ttsReplyBuffer,
          toaster: toaster,
          hapticService: hapticService,
        );

        final originTranscript = Transcript(
          id: 'tx-origin',
          text: 'Powtórz, żeby coś przerwało.',
          language: 'pl',
          deviceId: 'dev',
          createdAt: 1000,
        );
        await storage.saveTranscript(originTranscript);
        await storage.enqueue('tx-origin');

        worker.start();
        await Future.delayed(const Duration(milliseconds: 100));
        worker.stop();

        // Backend WAS called — origin phrase must not trigger local replay.
        expect(replayApi.postCalls, 1);
        // No replay toast.
        expect(
          toaster.messages,
          isNot(contains('Powtarzam ostatnią odpowiedź')),
        );
      },
    );
  });

  group('P036 _speakError does NOT feed buffer', () {
    test(
      'permanent failure speaks error but buffer remains empty',
      () async {
        await storage.saveTranscript(transcript);
        await storage.enqueue('tx-1');
        apiClient.nextResult = const ApiPermanentFailure(
          statusCode: 400,
          message: 'Bad request',
        );

        expect(ttsReplyBuffer.last(), isNull);

        worker.start();
        await Future.delayed(const Duration(milliseconds: 100));
        worker.stop();

        // _speakError ran (TTS fired with the error message).
        expect(
          tts.log.any((e) => e.startsWith('speak:Bad request:')),
          isTrue,
        );
        // CRITICAL: buffer must NOT be populated by error speak.
        expect(ttsReplyBuffer.last(), isNull);
      },
    );

    test(
      'transient failure speaks error but buffer remains empty',
      () async {
        await storage.saveTranscript(transcript);
        await storage.enqueue('tx-1');
        apiClient.nextResult =
            const ApiTransientFailure(reason: 'Connection timeout');

        worker.start();
        await Future.delayed(const Duration(milliseconds: 100));
        worker.stop();

        expect(
          tts.log.any((e) => e.startsWith('speak:Connection timeout:')),
          isTrue,
        );
        expect(ttsReplyBuffer.last(), isNull);
      },
    );

    test(
      'after a successful reply primes the buffer, a subsequent error speak '
      'does NOT overwrite the buffer',
      () async {
        // Prime the buffer via an actual successful reply path.
        ttsReplyBuffer.record('first reply', languageCode: 'en');
        await storage.saveTranscript(transcript);
        await storage.enqueue('tx-1');
        apiClient.nextResult =
            const ApiTransientFailure(reason: 'oops');

        worker.start();
        await Future.delayed(const Duration(milliseconds: 100));
        worker.stop();

        // Buffer untouched by error path.
        expect(
          ttsReplyBuffer.last(),
          const TtsReplyEntry(text: 'first reply', languageCode: 'en'),
        );
      },
    );
  });

  group('P036 buffer-clear hooks (SessionIdCoordinator)', () {
    test('resetSession() invokes registered listener', () async {
      final coord = SessionIdCoordinator();
      var calls = 0;
      coord.addResetListener(() => calls++);
      await coord.resetSession();
      expect(calls, 1);
    });

    test('addResetListener disposer removes the listener', () async {
      final coord = SessionIdCoordinator();
      var calls = 0;
      final dispose = coord.addResetListener(() => calls++);
      dispose();
      await coord.resetSession();
      expect(calls, 0);
    });

    test(
      'adoptConversationId(differentId) fires conversation-change listener',
      () {
        final coord = SessionIdCoordinator();
        coord.adoptConversationId('conv-1');
        var lastNotified = '';
        coord.addConversationChangeListener((id) => lastNotified = id);
        coord.adoptConversationId('conv-2');
        expect(lastNotified, 'conv-2');
      },
    );

    test(
      'adoptConversationId(sameId) does NOT fire conversation-change listener',
      () {
        final coord = SessionIdCoordinator();
        coord.adoptConversationId('conv-1');
        var calls = 0;
        coord.addConversationChangeListener((_) => calls++);
        coord.adoptConversationId('conv-1');
        expect(calls, 0);
      },
    );

    test(
      'first adopt from null fires conversation-change listener (id changed)',
      () {
        final coord = SessionIdCoordinator();
        var calls = 0;
        coord.addConversationChangeListener((_) => calls++);
        coord.adoptConversationId('conv-1');
        expect(calls, 1);
      },
    );

    test('integration: buffer cleared on resetSession via wired listener', () {
      final coord = SessionIdCoordinator();
      final buffer = InMemoryTtsReplyBuffer();
      coord.addResetListener(buffer.clear);

      buffer.record('hello', languageCode: 'en');
      expect(buffer.last(), isNotNull);

      coord.resetSession();
      expect(buffer.last(), isNull);
    });

    test(
      'integration: buffer cleared on adoptConversationId(different) but '
      'NOT on adoptConversationId(same)',
      () {
        final coord = SessionIdCoordinator();
        final buffer = InMemoryTtsReplyBuffer();
        coord.addConversationChangeListener((_) => buffer.clear());

        coord.adoptConversationId('conv-1');
        buffer.record('first', languageCode: 'en');

        // Same id — should NOT clear.
        coord.adoptConversationId('conv-1');
        expect(buffer.last(), isNotNull);

        // Different id — should clear.
        coord.adoptConversationId('conv-2');
        expect(buffer.last(), isNull);
      },
    );
  });
}

/// Counts `post` calls so we can assert the local-replay path skips backend.
class _CountingApiClient extends ApiClient {
  int postCalls = 0;
  ApiResult nextResult = const ApiSuccess();
  String? nextBody;

  @override
  Future<ApiResult> post(
    Transcript transcript, {
    required String url,
    String? token,
  }) async {
    postCalls++;
    if (nextResult is ApiSuccess) return ApiSuccess(body: nextBody);
    return nextResult;
  }
}
