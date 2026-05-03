import 'dart:convert';

import 'package:voice_agent/core/models/conversation.dart';
import 'package:voice_agent/core/models/conversation_record.dart';
import 'package:voice_agent/core/network/api_client.dart';
import 'package:voice_agent/core/network/sse_client.dart';
import 'package:voice_agent/features/chat/domain/chat_repository.dart';

class ChatException implements Exception {
  const ChatException(this.message);
  final String message;

  @override
  String toString() => message;
}

class ApiChatRepository implements ChatRepository {
  ApiChatRepository({
    required ApiClient apiClient,
    required SseClient sseClient,
  })  : _apiClient = apiClient,
        _sseClient = sseClient;

  final ApiClient _apiClient;
  final SseClient _sseClient;

  @override
  Future<List<Conversation>> listConversations() async {
    final result = await _apiClient.get('/conversations');
    final body = _unwrap(result);
    final json = jsonDecode(body) as Map<String, dynamic>;
    return (json['data'] as List)
        .map((e) => Conversation.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<ConversationEvent>> getEvents(String conversationId) async {
    final result =
        await _apiClient.get('/conversations/$conversationId/events');
    final body = _unwrap(result);
    final json = jsonDecode(body) as Map<String, dynamic>;
    return (json['data'] as List)
        .map((e) => ConversationEvent.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<ConversationRecord>> getRecords(String conversationId) async {
    final result =
        await _apiClient.get('/conversations/$conversationId/records');
    final body = _unwrap(result);
    final json = jsonDecode(body) as Map<String, dynamic>;
    return (json['data'] as List)
        .map((e) => ConversationRecord.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Stream<SseEvent> streamChat({
    required String sessionId,
    required String content,
    required String idempotencyKey,
    String? model,
    String? backend,
  }) {
    final body = <String, dynamic>{
      'session_id': sessionId,
      'content': content,
      'idempotency_key': idempotencyKey,
    };
    if (model != null) body['model'] = model;
    if (backend != null) body['backend'] = backend;
    return _sseClient.post('/chat/stream', data: body);
  }

  @override
  Future<void> cancelChat({
    required String sessionId,
    required String idempotencyKey,
  }) async {
    final result = await _apiClient.postJson('/chat/cancel', data: {
      'session_id': sessionId,
      'idempotency_key': idempotencyKey,
    });
    _throwOnFailure(result);
  }

  @override
  Future<Conversation?> getConversation(String conversationId) async {
    final conversations = await listConversations();
    try {
      return conversations.firstWhere(
        (c) => c.conversationId == conversationId,
      );
    } on StateError {
      return null;
    }
  }

  @override
  Future<List<ModelInfo>> getModels({String? backend}) async {
    final result = await _apiClient.get(
      '/chat/models',
      queryParameters: backend != null ? {'backend': backend} : null,
    );
    final body = _unwrap(result);
    final json = jsonDecode(body) as Map<String, dynamic>;
    final data = json['data'] as Map<String, dynamic>;
    return (data['models'] as List)
        .map((e) => ModelInfo.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<BackendOptions> getBackends() async {
    final result = await _apiClient.get('/chat/backends');
    final body = _unwrap(result);
    final json = jsonDecode(body) as Map<String, dynamic>;
    final data = json['data'] as Map<String, dynamic>;
    final backends = (data['backends'] as List)
        .map((e) => BackendInfo.fromMap(e as Map<String, dynamic>))
        .toList();
    return BackendOptions(
      backends: backends,
      defaultBackend: data['default_backend'] as String?,
    );
  }

  @override
  Future<bool> toggleEndorse(String recordId) async {
    final result =
        await _apiClient.postJson('/records/$recordId/endorse');
    final body = _unwrap(result);
    final json = jsonDecode(body) as Map<String, dynamic>;
    final data = json['data'] as Map<String, dynamic>;
    return data['user_endorsed'] as bool;
  }

  String _unwrap(ApiResult result) {
    return switch (result) {
      ApiSuccess(body: final b) when b != null => b,
      ApiSuccess() => throw const ChatException('Empty response'),
      ApiNotConfigured() => throw const ChatException('API not configured'),
      ApiPermanentFailure(message: final m) => throw ChatException(m),
      ApiTransientFailure(reason: final r) => throw ChatException(r),
    };
  }

  void _throwOnFailure(ApiResult result) {
    switch (result) {
      case ApiSuccess():
        return;
      case ApiNotConfigured():
        throw const ChatException('API not configured');
      case ApiPermanentFailure(message: final m):
        throw ChatException(m);
      case ApiTransientFailure(reason: final r):
        throw ChatException(r);
    }
  }
}
