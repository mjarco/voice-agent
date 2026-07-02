import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/models/conversation.dart';
import 'package:voice_agent/core/models/conversation_record.dart';
import 'package:voice_agent/core/models/pin.dart';
import 'package:voice_agent/core/network/api_client.dart';
import 'package:voice_agent/core/network/pin_writer.dart';
import 'package:voice_agent/core/network/sse_client.dart';
import 'package:voice_agent/features/chat/domain/chat_repository.dart';
import 'package:voice_agent/features/chat/domain/chat_state.dart';
import 'package:voice_agent/features/chat/presentation/thread_notifier.dart';

// ---------------------------------------------------------------------------
// Stub helpers
// ---------------------------------------------------------------------------

class _StubRepository implements ChatRepository {
  Conversation? conversationResult;
  List<ConversationEvent> eventsResult = [];
  List<ConversationRecord> recordsResult = [];
  List<ModelInfo> modelsResult = [];
  BackendOptions backendsResult = const BackendOptions(backends: []);
  bool toggleResult = true;

  bool throwOnLoad = false;
  bool throwOnFetchAfterResult = false;

  StreamController<SseEvent>? streamController;

  String? lastCancelSessionId;
  String? lastCancelIdempotencyKey;
  String? lastToggleRecordId;

  int getConversationCallCount = 0;

  @override
  Future<List<Conversation>> listConversations() async => [];

  @override
  Future<Conversation?> getConversation(String conversationId) async {
    getConversationCallCount++;
    if (throwOnLoad) throw Exception('load failed');
    return conversationResult;
  }

  @override
  Future<List<ConversationEvent>> getEvents(String conversationId) async {
    if (throwOnFetchAfterResult) throw Exception('fetch failed');
    return eventsResult;
  }

  @override
  Future<List<ConversationRecord>> getRecords(String conversationId) async {
    if (throwOnFetchAfterResult) throw Exception('fetch failed');
    return recordsResult;
  }

  @override
  Future<List<ModelInfo>> getModels({String? backend}) async => modelsResult;

  @override
  Future<BackendOptions> getBackends() async => backendsResult;

  @override
  Stream<SseEvent> streamChat({
    required String sessionId,
    required String content,
    required String idempotencyKey,
    String? model,
    String? backend,
  }) {
    streamController = StreamController<SseEvent>();
    return streamController!.stream;
  }

  @override
  Future<void> cancelChat({
    required String sessionId,
    required String idempotencyKey,
  }) async {
    lastCancelSessionId = sessionId;
    lastCancelIdempotencyKey = idempotencyKey;
  }

  @override
  Future<bool> toggleEndorse(String recordId) async {
    lastToggleRecordId = recordId;
    return toggleResult;
  }
}

class _FakePinWriter implements PinWriter {
  PinSuggestion suggestResult =
      const PinSuggestion(name: 'Suggested', topicLabel: 'Topic');
  Object? suggestError;
  Object? createError;

  final List<(String, String)> suggestCalls = [];
  final List<PinCreateRequest> createdRequests = [];

  @override
  Future<PinSuggestion> suggestPin(
    String conversationId,
    String eventId,
  ) async {
    suggestCalls.add((conversationId, eventId));
    if (suggestError != null) throw suggestError!;
    return suggestResult;
  }

  @override
  Future<PinCreateResult> createPin(PinCreateRequest request) async {
    createdRequests.add(request);
    if (createError != null) throw createError!;
    return PinCreateResult(
      pin: PinDetail(
        recordId: 'pin-1',
        pinName: request.name,
        topicLabel: request.topicLabel,
        text: 'body',
        createdAt: DateTime(2026, 1, 1),
      ),
      created: true,
    );
  }
}

/// Shared no-op pin writer for the pre-existing tests that never pin. Pin flow
/// tests build their own `_FakePinWriter` so they can inspect calls.
final _pinWriter = _FakePinWriter();

Conversation _conv({
  String id = 'conv-1',
  String sessionId = 'sess-1',
  ConversationStatus status = ConversationStatus.open,
  String? preview,
}) {
  return Conversation(
    conversationId: id,
    sessionId: sessionId,
    status: status,
    createdAt: DateTime(2026, 1, 1),
    eventCount: 0,
    firstMessagePreview: preview,
  );
}

ConversationEvent _event({String id = 'evt-1', EventRole role = EventRole.user}) {
  return ConversationEvent(
    eventId: id,
    conversationId: 'conv-1',
    sequence: 1,
    role: role,
    content: 'content-$id',
    receivedAt: DateTime(2026, 1, 1),
  );
}

ConversationRecord _record({String id = 'rec-1', bool endorsed = false}) {
  return ConversationRecord(
    recordId: id,
    conversationId: 'conv-1',
    recordType: RecordType.decision,
    subjectRef: 'subj-$id',
    payload: const {},
    confidence: 0.9,
    originRole: OriginRole.agent,
    assertionMode: 'assert',
    userEndorsed: endorsed,
    sourceEventRefs: const [],
  );
}

SseEvent _toolUseEvent(String tool) {
  return SseEvent(
    event: 'tool_use',
    data: '{"type":"tool_use","tool":"$tool","input":"{}"}',
  );
}

SseEvent _resultEvent({
  String conversationId = 'conv-1',
  String reply = 'Agent reply',
}) {
  return SseEvent(
    event: 'result',
    data:
        '{"conversation_id":"$conversationId","user_event_id":"ue-1","reply":"$reply"}',
  );
}

SseEvent _errorEvent(String message) {
  return SseEvent(event: 'error', data: '{"error":"$message"}');
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('ThreadNotifier — new conversation', () {
    test('transitions to empty state with generated sessionId', () async {
      final repo = _StubRepository();
      final notifier =
          ThreadNotifier(conversationId: 'new', repository: repo, pinWriter: _pinWriter);
      await Future.microtask(() {});
      await Future.microtask(() {});

      expect(notifier.state, isA<ThreadEmpty>());
      final empty = notifier.state as ThreadEmpty;
      expect(empty.sessionId, isNotEmpty);
    });

    test('selectedBackend set from defaultBackend', () async {
      final repo = _StubRepository()
        ..backendsResult = const BackendOptions(
          backends: [BackendInfo(id: 'b1', name: 'B1', available: true)],
          defaultBackend: 'b1',
        );
      final notifier =
          ThreadNotifier(conversationId: 'new', repository: repo, pinWriter: _pinWriter);
      await Future.microtask(() {});
      await Future.microtask(() {});

      final empty = notifier.state as ThreadEmpty;
      expect(empty.selectedBackend, 'b1');
    });
  });

  group('ThreadNotifier — existing conversation', () {
    test('transitions to loaded state', () async {
      final repo = _StubRepository()
        ..conversationResult = _conv()
        ..eventsResult = [_event()]
        ..recordsResult = [_record()];
      final notifier =
          ThreadNotifier(conversationId: 'conv-1', repository: repo, pinWriter: _pinWriter);
      await Future.microtask(() {});
      await Future.microtask(() {});

      expect(notifier.state, isA<ThreadLoaded>());
      final loaded = notifier.state as ThreadLoaded;
      expect(loaded.conversation.conversationId, 'conv-1');
      expect(loaded.events, hasLength(1));
      expect(loaded.records, hasLength(1));
    });

    test('emits error when getConversation returns null', () async {
      final repo = _StubRepository()..conversationResult = null;
      final notifier =
          ThreadNotifier(conversationId: 'conv-1', repository: repo, pinWriter: _pinWriter);
      await Future.microtask(() {});
      await Future.microtask(() {});

      expect(notifier.state, isA<ThreadError>());
      final error = notifier.state as ThreadError;
      expect(error.message, 'Conversation not found');
    });

    test('emits error on load failure', () async {
      final repo = _StubRepository()..throwOnLoad = true;
      final notifier =
          ThreadNotifier(conversationId: 'conv-1', repository: repo, pinWriter: _pinWriter);
      await Future.microtask(() {});
      await Future.microtask(() {});

      expect(notifier.state, isA<ThreadError>());
    });

    test('selectedBackend initialized from defaultBackend', () async {
      final repo = _StubRepository()
        ..conversationResult = _conv()
        ..backendsResult = const BackendOptions(
          backends: [BackendInfo(id: 'b2', name: 'B2', available: true)],
          defaultBackend: 'b2',
        );
      final notifier =
          ThreadNotifier(conversationId: 'conv-1', repository: repo, pinWriter: _pinWriter);
      await Future.microtask(() {});
      await Future.microtask(() {});

      final loaded = notifier.state as ThreadLoaded;
      expect(loaded.selectedBackend, 'b2');
    });
  });

  group('ThreadNotifier — send', () {
    test('is no-op when state is streaming', () async {
      final repo = _StubRepository()..conversationResult = _conv();
      final notifier =
          ThreadNotifier(conversationId: 'conv-1', repository: repo, pinWriter: _pinWriter);
      await Future.microtask(() {});
      await Future.microtask(() {});

      await notifier.send('first');
      expect(notifier.state, isA<ThreadStreaming>());

      await notifier.send('second');
      expect(notifier.state, isA<ThreadStreaming>());
    });

    test('is no-op when conversation is closed', () async {
      final repo = _StubRepository()
        ..conversationResult =
            _conv(status: ConversationStatus.closed);
      final notifier =
          ThreadNotifier(conversationId: 'conv-1', repository: repo, pinWriter: _pinWriter);
      await Future.microtask(() {});
      await Future.microtask(() {});

      await notifier.send('hello');
      expect(notifier.state, isA<ThreadLoaded>());
    });

    test('transitions loaded → streaming with pendingUserMessage', () async {
      final repo = _StubRepository()..conversationResult = _conv();
      final notifier =
          ThreadNotifier(conversationId: 'conv-1', repository: repo, pinWriter: _pinWriter);
      await Future.microtask(() {});
      await Future.microtask(() {});

      await notifier.send('hello');

      expect(notifier.state, isA<ThreadStreaming>());
      final streaming = notifier.state as ThreadStreaming;
      expect(streaming.pendingUserMessage, 'hello');
    });

    test('transitions empty → streaming for new conversation', () async {
      final repo = _StubRepository();
      final notifier =
          ThreadNotifier(conversationId: 'new', repository: repo, pinWriter: _pinWriter);
      await Future.microtask(() {});
      await Future.microtask(() {});

      await notifier.send('first message');

      expect(notifier.state, isA<ThreadStreaming>());
      final streaming = notifier.state as ThreadStreaming;
      expect(streaming.pendingUserMessage, 'first message');
      expect(streaming.conversation, isNull);
    });

    test('tool_use event updates toolProgress', () async {
      final repo = _StubRepository()..conversationResult = _conv();
      final notifier =
          ThreadNotifier(conversationId: 'conv-1', repository: repo, pinWriter: _pinWriter);
      await Future.microtask(() {});
      await Future.microtask(() {});

      await notifier.send('hello');
      repo.streamController!.add(_toolUseEvent('Bash'));
      await Future.microtask(() {});

      expect(notifier.state, isA<ThreadStreaming>());
      final streaming = notifier.state as ThreadStreaming;
      expect(streaming.toolProgress, contains('Bash'));
    });

    test('result event transitions to loaded with refreshed data', () async {
      final repo = _StubRepository()
        ..conversationResult = _conv()
        ..eventsResult = [_event(), _event(id: 'evt-2')];
      final notifier =
          ThreadNotifier(conversationId: 'conv-1', repository: repo, pinWriter: _pinWriter);
      await Future.microtask(() {});
      await Future.microtask(() {});

      await notifier.send('hello');
      repo.streamController!.add(_resultEvent());
      await repo.streamController!.close();
      await Future.microtask(() {});
      await Future.microtask(() {});
      await Future.microtask(() {});

      expect(notifier.state, isA<ThreadLoaded>());
      final loaded = notifier.state as ThreadLoaded;
      expect(loaded.events, hasLength(2));
    });

    test('SSE error event emits error with preSendState', () async {
      final repo = _StubRepository()..conversationResult = _conv();
      final notifier =
          ThreadNotifier(conversationId: 'conv-1', repository: repo, pinWriter: _pinWriter);
      await Future.microtask(() {});
      await Future.microtask(() {});

      final preSend = notifier.state;
      await notifier.send('hello');
      repo.streamController!.add(_errorEvent('backend error'));
      await Future.microtask(() {});

      expect(notifier.state, isA<ThreadError>());
      final error = notifier.state as ThreadError;
      expect(error.message, 'backend error');
      expect(error.previousState, preSend);
    });

    test('stream Dart error maps ApiNotConfigured', () async {
      final repo = _StubRepository()..conversationResult = _conv();
      final notifier =
          ThreadNotifier(conversationId: 'conv-1', repository: repo, pinWriter: _pinWriter);
      await Future.microtask(() {});
      await Future.microtask(() {});

      await notifier.send('hello');
      repo.streamController!.addError(const ApiNotConfigured());
      await Future.microtask(() {});

      expect(notifier.state, isA<ThreadError>());
      final error = notifier.state as ThreadError;
      expect(error.message, 'API not configured');
    });

    test('stream Dart error maps ApiPermanentFailure', () async {
      final repo = _StubRepository()..conversationResult = _conv();
      final notifier =
          ThreadNotifier(conversationId: 'conv-1', repository: repo, pinWriter: _pinWriter);
      await Future.microtask(() {});
      await Future.microtask(() {});

      await notifier.send('hello');
      repo.streamController!.addError(
        const ApiPermanentFailure(statusCode: 500, message: 'Server error'),
      );
      await Future.microtask(() {});

      expect(notifier.state, isA<ThreadError>());
      expect((notifier.state as ThreadError).message, 'Server error');
    });

    test('stream Dart error maps ApiTransientFailure', () async {
      final repo = _StubRepository()..conversationResult = _conv();
      final notifier =
          ThreadNotifier(conversationId: 'conv-1', repository: repo, pinWriter: _pinWriter);
      await Future.microtask(() {});
      await Future.microtask(() {});

      await notifier.send('hello');
      repo.streamController!.addError(
        const ApiTransientFailure(reason: 'timeout'),
      );
      await Future.microtask(() {});

      expect(notifier.state, isA<ThreadError>());
      expect((notifier.state as ThreadError).message, 'timeout');
    });

    test('post-result fetch failure emits error with streaming state', () async {
      final repo = _StubRepository()..conversationResult = _conv();
      final notifier =
          ThreadNotifier(conversationId: 'conv-1', repository: repo, pinWriter: _pinWriter);
      await Future.microtask(() {});
      await Future.microtask(() {});

      await notifier.send('hello');
      repo.throwOnFetchAfterResult = true;
      repo.streamController!.add(_resultEvent());
      await repo.streamController!.close();
      await Future.microtask(() {});
      await Future.microtask(() {});
      await Future.microtask(() {});

      expect(notifier.state, isA<ThreadError>());
      final error = notifier.state as ThreadError;
      expect(error.message, 'Failed to load messages');
      expect(error.previousState, isA<ThreadStreaming>());
      final prev = error.previousState as ThreadStreaming;
      expect(prev.pendingUserMessage, 'hello');
    });
  });

  group('ThreadNotifier — cancelStream', () {
    test('is no-op when not streaming', () async {
      final repo = _StubRepository()..conversationResult = _conv();
      final notifier =
          ThreadNotifier(conversationId: 'conv-1', repository: repo, pinWriter: _pinWriter);
      await Future.microtask(() {});
      await Future.microtask(() {});

      notifier.cancelStream();
      expect(notifier.state, isA<ThreadLoaded>());
    });

    test('reverts to preSendState and calls cancelChat', () async {
      final repo = _StubRepository()..conversationResult = _conv(sessionId: 'sess-abc');
      final notifier =
          ThreadNotifier(conversationId: 'conv-1', repository: repo, pinWriter: _pinWriter);
      await Future.microtask(() {});
      await Future.microtask(() {});

      final preSend = notifier.state;
      await notifier.send('hello');
      expect(notifier.state, isA<ThreadStreaming>());

      notifier.cancelStream();
      await Future.microtask(() {});

      expect(notifier.state, preSend);
      expect(repo.lastCancelSessionId, 'sess-abc');
    });
  });

  group('ThreadNotifier — toggleEndorse', () {
    test('flips userEndorsed on matching record in loaded state', () async {
      final repo = _StubRepository()
        ..conversationResult = _conv()
        ..recordsResult = [_record(id: 'rec-1', endorsed: false)]
        ..toggleResult = true;
      final notifier =
          ThreadNotifier(conversationId: 'conv-1', repository: repo, pinWriter: _pinWriter);
      await Future.microtask(() {});
      await Future.microtask(() {});

      await notifier.toggleEndorse('rec-1');

      final loaded = notifier.state as ThreadLoaded;
      expect(loaded.records.first.userEndorsed, isTrue);
    });

    test('calls repository.toggleEndorse with correct id', () async {
      final repo = _StubRepository()
        ..conversationResult = _conv()
        ..recordsResult = [_record(id: 'rec-42')];
      final notifier =
          ThreadNotifier(conversationId: 'conv-1', repository: repo, pinWriter: _pinWriter);
      await Future.microtask(() {});
      await Future.microtask(() {});

      await notifier.toggleEndorse('rec-42');

      expect(repo.lastToggleRecordId, 'rec-42');
    });
  });

  group('ThreadNotifier — selectModel / selectBackend', () {
    test('selectModel updates loaded state', () async {
      final repo = _StubRepository()..conversationResult = _conv();
      final notifier =
          ThreadNotifier(conversationId: 'conv-1', repository: repo, pinWriter: _pinWriter);
      await Future.microtask(() {});
      await Future.microtask(() {});

      notifier.selectModel('model-x');

      final loaded = notifier.state as ThreadLoaded;
      expect(loaded.selectedModel, 'model-x');
    });

    test('selectModel updates empty state', () async {
      final repo = _StubRepository();
      final notifier =
          ThreadNotifier(conversationId: 'new', repository: repo, pinWriter: _pinWriter);
      await Future.microtask(() {});
      await Future.microtask(() {});

      notifier.selectModel('model-y');

      final empty = notifier.state as ThreadEmpty;
      expect(empty.selectedModel, 'model-y');
    });

    test('selectModel during loading stores as pending', () async {
      final repo = _StubRepository()..conversationResult = _conv();
      final notifier =
          ThreadNotifier(conversationId: 'conv-1', repository: repo, pinWriter: _pinWriter);
      // Immediately after creation, state is ThreadLoading
      expect(notifier.state, isA<ThreadLoading>());

      notifier.selectModel('model-z');

      await Future.microtask(() {});
      await Future.microtask(() {});

      final loaded = notifier.state as ThreadLoaded;
      expect(loaded.selectedModel, 'model-z');
    });

    test('selectBackend updates loaded state', () async {
      final repo = _StubRepository()..conversationResult = _conv();
      final notifier =
          ThreadNotifier(conversationId: 'conv-1', repository: repo, pinWriter: _pinWriter);
      await Future.microtask(() {});
      await Future.microtask(() {});

      notifier.selectBackend('backend-a');

      final loaded = notifier.state as ThreadLoaded;
      expect(loaded.selectedBackend, 'backend-a');
    });

    test('selectBackend during loading stores as pending applied on empty',
        () async {
      final repo = _StubRepository();
      final notifier =
          ThreadNotifier(conversationId: 'new', repository: repo, pinWriter: _pinWriter);
      expect(notifier.state, isA<ThreadLoading>());

      notifier.selectBackend('backend-b');

      await Future.microtask(() {});
      await Future.microtask(() {});

      final empty = notifier.state as ThreadEmpty;
      expect(empty.selectedBackend, 'backend-b');
    });

    test('selectModel updates streaming state', () async {
      final repo = _StubRepository()..conversationResult = _conv();
      final notifier =
          ThreadNotifier(conversationId: 'conv-1', repository: repo, pinWriter: _pinWriter);
      await Future.microtask(() {});
      await Future.microtask(() {});

      await notifier.send('hello');
      expect(notifier.state, isA<ThreadStreaming>());

      notifier.selectModel('model-streaming');

      final streaming = notifier.state as ThreadStreaming;
      expect(streaming.selectedModel, 'model-streaming');
    });

    test('selectModel during error state is a no-op', () async {
      final repo = _StubRepository()..conversationResult = null;
      final notifier =
          ThreadNotifier(conversationId: 'conv-1', repository: repo, pinWriter: _pinWriter);
      await Future.microtask(() {});
      await Future.microtask(() {});

      expect(notifier.state, isA<ThreadError>());
      notifier.selectModel('model-ignored');

      expect(notifier.state, isA<ThreadError>());
    });
  });

  group('pin flow (P046)', () {
    Future<ThreadNotifier> loadedNotifier(
      _StubRepository repo,
      _FakePinWriter pin,
    ) async {
      repo.conversationResult = _conv();
      repo.eventsResult = [_event(id: 'evt-agent', role: EventRole.agent)];
      final notifier = ThreadNotifier(
        conversationId: 'conv-1',
        repository: repo,
        pinWriter: pin,
      );
      await Future.microtask(() {});
      await Future.microtask(() {});
      return notifier;
    }

    test('beginPin marks in-flight during suggest, clears when it settles',
        () async {
      final pin = _FakePinWriter();
      final notifier = await loadedNotifier(_StubRepository(), pin);

      final future = notifier.beginPin('conv-1', 'evt-agent');
      // In-flight while the suggest call is pending (drives the spinner).
      expect(notifier.isPinInFlight('evt-agent'), isTrue);

      final suggestion = await future;
      expect(suggestion?.name, 'Suggested');
      expect(pin.suggestCalls.single, ('conv-1', 'evt-agent'));
      // Cleared once suggest resolves — the dialog runs behind a modal barrier.
      expect(notifier.isPinInFlight('evt-agent'), isFalse);
    });

    test('a second beginPin while in-flight is a no-op (single-flight)',
        () async {
      final pin = _FakePinWriter();
      final notifier = await loadedNotifier(_StubRepository(), pin);

      final first = notifier.beginPin('conv-1', 'evt-agent');
      final second = await notifier.beginPin('conv-1', 'evt-agent');
      await first;

      expect(second, isNull);
      expect(pin.suggestCalls, hasLength(1));
    });

    test('beginPin clears in-flight and rethrows on suggest failure', () async {
      final pin = _FakePinWriter()..suggestError = Exception('boom');
      final notifier = await loadedNotifier(_StubRepository(), pin);

      await expectLater(
        notifier.beginPin('conv-1', 'evt-agent'),
        throwsA(isA<Exception>()),
      );
      expect(notifier.isPinInFlight('evt-agent'), isFalse);
    });

    test('confirmPin creates with the exact payload and marks pinned',
        () async {
      final pin = _FakePinWriter();
      final notifier = await loadedNotifier(_StubRepository(), pin);
      await notifier.beginPin('conv-1', 'evt-agent');

      final result = await notifier.confirmPin(
        'conv-1',
        'evt-agent',
        name: 'Garage pinout',
        topicLabel: 'Electronics',
      );

      final req = pin.createdRequests.single;
      expect(req.conversationId, 'conv-1');
      expect(req.eventId, 'evt-agent');
      expect(req.name, 'Garage pinout');
      expect(req.topicLabel, 'Electronics');
      expect(req.toMap().containsKey('aliases'), isFalse);
      expect(result.created, isTrue);
      expect(notifier.isPinned('evt-agent'), isTrue);
      expect(notifier.isPinInFlight('evt-agent'), isFalse);
    });

    test('confirmPin clears in-flight and rethrows on create failure',
        () async {
      final pin = _FakePinWriter()..createError = Exception('server 500');
      final notifier = await loadedNotifier(_StubRepository(), pin);
      await notifier.beginPin('conv-1', 'evt-agent');

      await expectLater(
        notifier.confirmPin('conv-1', 'evt-agent', name: 'n'),
        throwsA(isA<Exception>()),
      );
      expect(notifier.isPinned('evt-agent'), isFalse);
      expect(notifier.isPinInFlight('evt-agent'), isFalse);
    });

    test('cancelPin clears the in-flight mark', () async {
      final pin = _FakePinWriter();
      final notifier = await loadedNotifier(_StubRepository(), pin);
      await notifier.beginPin('conv-1', 'evt-agent');

      notifier.cancelPin('evt-agent');

      expect(notifier.isPinInFlight('evt-agent'), isFalse);
      expect(notifier.isPinned('evt-agent'), isFalse);
    });

    test('beginPin on an already-pinned event is a no-op', () async {
      final pin = _FakePinWriter();
      final notifier = await loadedNotifier(_StubRepository(), pin);
      await notifier.beginPin('conv-1', 'evt-agent');
      await notifier.confirmPin('conv-1', 'evt-agent', name: 'n');

      final again = await notifier.beginPin('conv-1', 'evt-agent');

      expect(again, isNull);
      expect(pin.suggestCalls, hasLength(1));
    });

    test('pinned state survives a send (streaming) transition', () async {
      final pin = _FakePinWriter();
      final repo = _StubRepository();
      final notifier = await loadedNotifier(repo, pin);
      await notifier.beginPin('conv-1', 'evt-agent');
      await notifier.confirmPin('conv-1', 'evt-agent', name: 'n');

      notifier.send('another message');

      expect(notifier.state, isA<ThreadStreaming>());
      expect(notifier.isPinned('evt-agent'), isTrue);
    });
  });
}
