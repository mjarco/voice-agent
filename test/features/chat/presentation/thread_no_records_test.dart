import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/models/pin.dart';
import 'package:voice_agent/core/network/api_client.dart';
import 'package:voice_agent/core/network/pin_writer.dart';
import 'package:voice_agent/core/network/sse_client.dart';
import 'package:voice_agent/features/chat/data/api_chat_repository.dart';
import 'package:voice_agent/features/chat/domain/chat_state.dart';
import 'package:voice_agent/features/chat/presentation/thread_notifier.dart';

import '../../../core/network/fake_shopping_proposals.dart';

/// Answers each GET by its path and records every path asked for.
class _PathApiClient extends ApiClient {
  _PathApiClient() : super(baseUrl: 'https://test.com/api/v1');

  final List<String> getPaths = [];

  @override
  Future<ApiResult> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    getPaths.add(path);
    final body = switch (path) {
      '/conversations' => {
          'data': [
            {
              'conversation_id': 'conv-1',
              'session_id': 'sess-1',
              'status': 'open',
              'created_at': '2026-11-09T10:00:00Z',
              'event_count': 1,
            },
          ],
        },
      '/conversations/conv-1/events' => {
          'data': [
            {
              'event_id': 'evt-1',
              'conversation_id': 'conv-1',
              'sequence': 1,
              'role': 'user',
              'content': 'hello',
              'received_at': '2026-11-09T10:00:00Z',
            },
          ],
        },
      '/chat/models' => {
          'data': {'models': <Object>[]},
        },
      '/chat/backends' => {
          'data': {'backends': <Object>[]},
        },
      _ => null,
    };
    if (body == null) {
      return const ApiPermanentFailure(statusCode: 404, message: 'Not Found');
    }
    return ApiSuccess(body: jsonEncode(body));
  }
}

class _NoPinWriter implements PinWriter {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();

  @override
  Future<PinSuggestion> suggestPin(String conversationId, String eventId) =>
      throw UnimplementedError();
}

void main() {
  // personal-agent R2 (ADR-CORE-117) keeps knowledge records nowhere: the
  // thread is read from the conversation and its events alone.
  test('an existing thread loads without asking for /records', () async {
    final api = _PathApiClient();
    final repo = ApiChatRepository(
      apiClient: api,
      sseClient: SseClient(apiClient: api),
    );
    final notifier = ThreadNotifier(
      conversationId: 'conv-1',
      repository: repo,
      pinWriter: _NoPinWriter(),
      proposals: FakeShoppingProposals(),
    );

    for (var i = 0; i < 10 && notifier.state is! ThreadLoaded; i++) {
      await Future<void>.delayed(Duration.zero);
    }

    expect(notifier.state, isA<ThreadLoaded>());
    expect((notifier.state as ThreadLoaded).events, hasLength(1));
    expect(api.getPaths, isNotEmpty);
    expect(api.getPaths.where((p) => p.contains('records')), isEmpty);
  });
}
