import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/network/api_client.dart';
import 'package:voice_agent/core/network/sse_client.dart';
import 'package:voice_agent/features/chat/data/api_chat_repository.dart';

class _StubApiClient extends ApiClient {
  _StubApiClient() : super(baseUrl: 'https://test.com/api/v1');

  ApiResult nextGetResult = const ApiSuccess(body: '{}');
  ApiResult nextPostResult = const ApiSuccess(body: '{}');

  String? lastGetPath;
  Map<String, dynamic>? lastGetParams;
  String? lastPostPath;
  Map<String, dynamic>? lastPostData;

  @override
  Future<ApiResult> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    lastGetPath = path;
    lastGetParams = queryParameters;
    return nextGetResult;
  }

  @override
  Future<ApiResult> postJson(String path, {Map<String, dynamic>? data}) async {
    lastPostPath = path;
    lastPostData = data;
    return nextPostResult;
  }
}

class _StubSseClient extends SseClient {
  _StubSseClient() : super(apiClient: ApiClient(baseUrl: null));

  Stream<SseEvent>? nextStream;
  String? lastPath;
  Map<String, dynamic>? lastData;

  @override
  Stream<SseEvent> post(String path, {required Map<String, dynamic> data}) {
    lastPath = path;
    lastData = data;
    return nextStream ?? const Stream.empty();
  }
}

Map<String, dynamic> _sampleConversation({String id = 'conv-1'}) => {
      'conversation_id': id,
      'session_id': 'sess-1',
      'status': 'open',
      'created_at': '2026-01-01T00:00:00Z',
      'event_count': 2,
      'last_event_at': '2026-01-01T01:00:00Z',
      'first_message_preview': 'Hello',
      'subject_record_id': null,
      'subject_record_text': null,
      'subject_record_status': null,
    };

Map<String, dynamic> _sampleEvent() => {
      'event_id': 'evt-1',
      'conversation_id': 'conv-1',
      'sequence': 1,
      'role': 'user',
      'content': 'Hello there',
      'occurred_at': null,
      'received_at': '2026-01-01T00:00:00Z',
    };

Map<String, dynamic> _sampleRecord() => {
      'record_id': 'rec-1',
      'conversation_id': 'conv-1',
      'record_type': 'topic',
      'subject_ref': 'meeting',
      'payload': {'text': 'Team meeting'},
      'confidence': 0.9,
      'origin_role': 'agent',
      'assertion_mode': 'assert',
      'user_endorsed': false,
      'source_event_refs': [],
    };

Map<String, dynamic> _sampleModel() => {
      'id': 'model-1',
      'label': 'GPT-4',
      'backend': 'openai',
    };

Map<String, dynamic> _sampleBackend({bool available = true}) => {
      'id': 'groq',
      'label': 'Groq',
      'available': available,
    };

void main() {
  late _StubApiClient apiClient;
  late _StubSseClient sseClient;
  late ApiChatRepository repo;

  setUp(() {
    apiClient = _StubApiClient();
    sseClient = _StubSseClient();
    repo = ApiChatRepository(apiClient: apiClient, sseClient: sseClient);
  });

  group('listConversations', () {
    test('parses conversations from data envelope', () async {
      apiClient.nextGetResult = ApiSuccess(
        body: jsonEncode({'data': [_sampleConversation()]}),
      );

      final conversations = await repo.listConversations();

      expect(conversations, hasLength(1));
      expect(conversations.first.conversationId, 'conv-1');
      expect(apiClient.lastGetPath, '/conversations');
    });

    test('returns empty list when data is empty', () async {
      apiClient.nextGetResult =
          const ApiSuccess(body: '{"data": []}');

      final conversations = await repo.listConversations();

      expect(conversations, isEmpty);
    });

    test('throws ChatException on ApiNotConfigured', () async {
      apiClient.nextGetResult = const ApiNotConfigured();

      expect(
        () => repo.listConversations(),
        throwsA(
          isA<ChatException>().having(
            (e) => e.message,
            'message',
            contains('not configured'),
          ),
        ),
      );
    });

    test('throws ChatException on ApiPermanentFailure', () async {
      apiClient.nextGetResult = const ApiPermanentFailure(
        statusCode: 500,
        message: 'Internal error',
      );

      expect(
        () => repo.listConversations(),
        throwsA(isA<ChatException>()),
      );
    });

    test('throws ChatException on ApiTransientFailure', () async {
      apiClient.nextGetResult = const ApiTransientFailure(
        reason: 'Timeout',
      );

      expect(
        () => repo.listConversations(),
        throwsA(isA<ChatException>()),
      );
    });
  });

  group('getEvents', () {
    test('fetches events for conversation', () async {
      apiClient.nextGetResult = ApiSuccess(
        body: jsonEncode({'data': [_sampleEvent()]}),
      );

      final events = await repo.getEvents('conv-1');

      expect(events, hasLength(1));
      expect(events.first.eventId, 'evt-1');
      expect(apiClient.lastGetPath, '/conversations/conv-1/events');
    });

    test('throws on failure', () async {
      apiClient.nextGetResult = const ApiNotConfigured();

      expect(() => repo.getEvents('conv-1'), throwsA(isA<ChatException>()));
    });
  });

  group('getRecords', () {
    test('fetches records for conversation', () async {
      apiClient.nextGetResult = ApiSuccess(
        body: jsonEncode({'data': [_sampleRecord()]}),
      );

      final records = await repo.getRecords('conv-1');

      expect(records, hasLength(1));
      expect(records.first.recordId, 'rec-1');
      expect(apiClient.lastGetPath, '/conversations/conv-1/records');
    });

    test('throws on failure', () async {
      apiClient.nextGetResult = const ApiTransientFailure(reason: 'error');

      expect(() => repo.getRecords('conv-1'), throwsA(isA<ChatException>()));
    });
  });

  group('getConversation', () {
    test('returns matching conversation by id', () async {
      apiClient.nextGetResult = ApiSuccess(
        body: jsonEncode({
          'data': [
            _sampleConversation(id: 'conv-1'),
            _sampleConversation(id: 'conv-2'),
          ],
        }),
      );

      final conv = await repo.getConversation('conv-2');

      expect(conv, isNotNull);
      expect(conv!.conversationId, 'conv-2');
    });

    test('returns null when id not found', () async {
      apiClient.nextGetResult = ApiSuccess(
        body: jsonEncode({'data': [_sampleConversation(id: 'conv-1')]}),
      );

      final conv = await repo.getConversation('conv-999');

      expect(conv, isNull);
    });
  });

  group('getModels', () {
    test('fetches models from data envelope', () async {
      apiClient.nextGetResult = ApiSuccess(
        body: jsonEncode({
          'data': {
            'models': [_sampleModel()],
          },
        }),
      );

      final models = await repo.getModels();

      expect(models, hasLength(1));
      expect(models.first.id, 'model-1');
      expect(models.first.backendId, 'openai');
      expect(apiClient.lastGetPath, '/chat/models');
    });

    test('sends backend query parameter when specified', () async {
      apiClient.nextGetResult = ApiSuccess(
        body: jsonEncode({
          'data': {'models': []},
        }),
      );

      await repo.getModels(backend: 'groq');

      expect(apiClient.lastGetParams, {'backend': 'groq'});
    });

    test('omits backend query parameter when null', () async {
      apiClient.nextGetResult = ApiSuccess(
        body: jsonEncode({
          'data': {'models': []},
        }),
      );

      await repo.getModels();

      expect(apiClient.lastGetParams, isNull);
    });

    test('throws on failure', () async {
      apiClient.nextGetResult = const ApiNotConfigured();

      expect(() => repo.getModels(), throwsA(isA<ChatException>()));
    });
  });

  group('getBackends', () {
    test('parses backends and defaultBackend from data envelope', () async {
      apiClient.nextGetResult = ApiSuccess(
        body: jsonEncode({
          'data': {
            'backends': [_sampleBackend()],
            'default_backend': 'groq',
          },
        }),
      );

      final options = await repo.getBackends();

      expect(options.backends, hasLength(1));
      expect(options.backends.first.id, 'groq');
      expect(options.defaultBackend, 'groq');
    });

    test('handles null default_backend', () async {
      apiClient.nextGetResult = ApiSuccess(
        body: jsonEncode({
          'data': {
            'backends': [_sampleBackend()],
            'default_backend': null,
          },
        }),
      );

      final options = await repo.getBackends();

      expect(options.defaultBackend, isNull);
    });

    test('parses available flag', () async {
      apiClient.nextGetResult = ApiSuccess(
        body: jsonEncode({
          'data': {
            'backends': [_sampleBackend(available: false)],
            'default_backend': null,
          },
        }),
      );

      final options = await repo.getBackends();

      expect(options.backends.first.available, isFalse);
    });

    test('throws on failure', () async {
      apiClient.nextGetResult = const ApiNotConfigured();

      expect(() => repo.getBackends(), throwsA(isA<ChatException>()));
    });
  });

  group('toggleEndorse', () {
    test('returns true when endorsed', () async {
      apiClient.nextPostResult = const ApiSuccess(
        body: '{"data": {"user_endorsed": true}}',
      );

      final result = await repo.toggleEndorse('rec-1');

      expect(result, isTrue);
      expect(apiClient.lastPostPath, '/records/rec-1/endorse');
    });

    test('returns false when unendorsed', () async {
      apiClient.nextPostResult = const ApiSuccess(
        body: '{"data": {"user_endorsed": false}}',
      );

      final result = await repo.toggleEndorse('rec-1');

      expect(result, isFalse);
    });

    test('throws on failure', () async {
      apiClient.nextPostResult = const ApiPermanentFailure(
        statusCode: 404,
        message: 'Not found',
      );

      expect(
        () => repo.toggleEndorse('rec-1'),
        throwsA(isA<ChatException>()),
      );
    });
  });

  group('streamChat', () {
    test('calls sseClient.post with correct path and required fields', () async {
      final events = [
        const SseEvent(event: 'result', data: '{"done": true}'),
      ];
      sseClient.nextStream = Stream.fromIterable(events);

      final stream = repo.streamChat(
        sessionId: 'sess-1',
        content: 'Hello',
        idempotencyKey: 'key-1',
      );

      await stream.drain<void>();

      expect(sseClient.lastPath, '/chat/stream');
      expect(sseClient.lastData!['session_id'], 'sess-1');
      expect(sseClient.lastData!['content'], 'Hello');
      expect(sseClient.lastData!['idempotency_key'], 'key-1');
    });

    test('includes model and backend when specified', () async {
      sseClient.nextStream = const Stream.empty();

      repo.streamChat(
        sessionId: 'sess-1',
        content: 'Hello',
        idempotencyKey: 'key-1',
        model: 'gpt-4',
        backend: 'openai',
      );

      expect(sseClient.lastData!['model'], 'gpt-4');
      expect(sseClient.lastData!['backend'], 'openai');
    });

    test('omits model and backend when null', () async {
      sseClient.nextStream = const Stream.empty();

      repo.streamChat(
        sessionId: 'sess-1',
        content: 'Hello',
        idempotencyKey: 'key-1',
      );

      expect(sseClient.lastData!.containsKey('model'), isFalse);
      expect(sseClient.lastData!.containsKey('backend'), isFalse);
    });

    test('returns events from sseClient stream', () async {
      final events = [
        const SseEvent(event: 'tool_use', data: '{"tool": "bash"}'),
        const SseEvent(event: 'result', data: '{"reply": "done"}'),
      ];
      sseClient.nextStream = Stream.fromIterable(events);

      final received = await repo
          .streamChat(
            sessionId: 'sess-1',
            content: 'Hello',
            idempotencyKey: 'key-1',
          )
          .toList();

      expect(received, hasLength(2));
      expect(received.first.event, 'tool_use');
      expect(received.last.event, 'result');
    });
  });

  group('cancelChat', () {
    test('posts to correct path with session and idempotency key', () async {
      apiClient.nextPostResult = const ApiSuccess(body: '{"cancelled": true}');

      await repo.cancelChat(
        sessionId: 'sess-1',
        idempotencyKey: 'key-1',
      );

      expect(apiClient.lastPostPath, '/chat/cancel');
      expect(apiClient.lastPostData, {
        'session_id': 'sess-1',
        'idempotency_key': 'key-1',
      });
    });

    test('throws on failure', () async {
      apiClient.nextPostResult = const ApiNotConfigured();

      expect(
        () => repo.cancelChat(sessionId: 'sess-1', idempotencyKey: 'key-1'),
        throwsA(isA<ChatException>()),
      );
    });
  });

  group('ChatException', () {
    test('toString returns message', () {
      const e = ChatException('API not configured');
      expect(e.toString(), 'API not configured');
    });
  });
}
