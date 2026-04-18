import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/network/api_client.dart';
import 'package:voice_agent/core/network/sse_client.dart';

void main() {
  late Dio mockDio;
  late ApiClient apiClient;
  late SseClient sseClient;

  setUp(() {
    mockDio = Dio();
    mockDio.httpClientAdapter = _SseMockAdapter();
    apiClient = ApiClient(
      baseUrl: 'https://example.com/api/v1',
      token: 'test-token',
    );
    sseClient = SseClient(apiClient: apiClient, dio: mockDio);
  });

  group('SseClient', () {
    test('emits ApiNotConfigured when baseUrl is null', () async {
      final unconfigured = ApiClient();
      final client = SseClient(apiClient: unconfigured, dio: mockDio);

      final errors = <Object>[];
      final done = Completer<void>();

      client.post('/chat', data: {'message': 'hi'}).listen(
        (_) {},
        onError: errors.add,
        onDone: done.complete,
      );

      await done.future;

      expect(errors, hasLength(1));
      expect(errors.first, isA<ApiNotConfigured>());
    });

    test('parses single SSE event', () async {
      _SseMockAdapter.nextChunks = [
        'event: message\ndata: hello\nid: 1\n\n',
      ];

      final events =
          await sseClient.post('/chat', data: {'q': 'hi'}).toList();

      expect(events, hasLength(1));
      expect(events[0].event, 'message');
      expect(events[0].data, 'hello');
      expect(events[0].id, '1');
    });

    test('parses multiple SSE events from single chunk', () async {
      _SseMockAdapter.nextChunks = [
        'data: first\n\ndata: second\n\n',
      ];

      final events =
          await sseClient.post('/chat', data: {'q': 'hi'}).toList();

      expect(events, hasLength(2));
      expect(events[0].data, 'first');
      expect(events[1].data, 'second');
    });

    test('joins multi-line data fields', () async {
      _SseMockAdapter.nextChunks = [
        'data: line one\ndata: line two\ndata: line three\n\n',
      ];

      final events =
          await sseClient.post('/chat', data: {'q': 'hi'}).toList();

      expect(events, hasLength(1));
      expect(events[0].data, 'line one\nline two\nline three');
    });

    test('handles chunks split across boundaries', () async {
      _SseMockAdapter.nextChunks = [
        'data: hel',
        'lo\n\n',
      ];

      final events =
          await sseClient.post('/chat', data: {'q': 'hi'}).toList();

      expect(events, hasLength(1));
      expect(events[0].data, 'hello');
    });

    test('strips carriage returns', () async {
      _SseMockAdapter.nextChunks = [
        'data: hello\r\n\r\n',
      ];

      final events =
          await sseClient.post('/chat', data: {'q': 'hi'}).toList();

      expect(events, hasLength(1));
      expect(events[0].data, 'hello');
    });

    test('ignores comment lines', () async {
      _SseMockAdapter.nextChunks = [
        ': this is a comment\ndata: real data\n\n',
      ];

      final events =
          await sseClient.post('/chat', data: {'q': 'hi'}).toList();

      expect(events, hasLength(1));
      expect(events[0].data, 'real data');
    });

    test('emits trailing event without final blank line', () async {
      _SseMockAdapter.nextChunks = [
        'data: trailing\n',
      ];

      final events =
          await sseClient.post('/chat', data: {'q': 'hi'}).toList();

      expect(events, hasLength(1));
      expect(events[0].data, 'trailing');
    });

    test('event field is null when not specified', () async {
      _SseMockAdapter.nextChunks = [
        'data: no event type\n\n',
      ];

      final events =
          await sseClient.post('/chat', data: {'q': 'hi'}).toList();

      expect(events, hasLength(1));
      expect(events[0].event, isNull);
      expect(events[0].id, isNull);
    });

    test('does not emit event for empty data', () async {
      _SseMockAdapter.nextChunks = [
        'event: ping\n\n',
      ];

      final events =
          await sseClient.post('/chat', data: {'q': 'hi'}).toList();

      expect(events, isEmpty);
    });

    test('propagates DioException as classified ApiResult error', () async {
      _SseMockAdapter.shouldThrow = DioException(
        requestOptions: RequestOptions(path: '/chat'),
        type: DioExceptionType.connectionTimeout,
      );

      final errors = <Object>[];
      final done = Completer<void>();

      sseClient.post('/chat', data: {'q': 'hi'}).listen(
        (_) {},
        onError: errors.add,
        onDone: done.complete,
      );

      await done.future;

      expect(errors, hasLength(1));
      expect(errors.first, isA<ApiTransientFailure>());
    });

    test('sends Authorization header', () async {
      _SseMockAdapter.nextChunks = ['data: ok\n\n'];
      _SseMockAdapter.lastHeaders = null;

      await sseClient.post('/chat', data: {'q': 'hi'}).toList();

      expect(
        _SseMockAdapter.lastHeaders?['Authorization'],
        'Bearer test-token',
      );
    });

    test('omits Authorization when token is null', () async {
      final noTokenClient = ApiClient(
        baseUrl: 'https://example.com/api/v1',
      );
      final client = SseClient(apiClient: noTokenClient, dio: mockDio);

      _SseMockAdapter.nextChunks = ['data: ok\n\n'];
      _SseMockAdapter.lastHeaders = null;

      await client.post('/chat', data: {'q': 'hi'}).toList();

      expect(_SseMockAdapter.lastHeaders?['Authorization'], isNull);
    });

    test('sends Accept text/event-stream header', () async {
      _SseMockAdapter.nextChunks = ['data: ok\n\n'];
      _SseMockAdapter.lastHeaders = null;

      await sseClient.post('/chat', data: {'q': 'hi'}).toList();

      expect(
        _SseMockAdapter.lastHeaders?['Accept'],
        'text/event-stream',
      );
    });

    test('composes correct URL from baseUrl and path', () async {
      _SseMockAdapter.nextChunks = ['data: ok\n\n'];

      await sseClient.post('/conversations/chat', data: {'q': 'hi'}).toList();

      expect(
        _SseMockAdapter.lastRequestPath,
        'https://example.com/api/v1/conversations/chat',
      );
    });
  });
}

class _SseMockAdapter implements HttpClientAdapter {
  static List<String> nextChunks = [];
  static DioException? shouldThrow;
  static Map<String, dynamic>? lastHeaders;
  static String? lastRequestPath;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastHeaders = options.headers;
    lastRequestPath = options.path;

    if (shouldThrow != null) {
      final e = shouldThrow!;
      shouldThrow = null;
      throw e;
    }

    final chunks = nextChunks;
    nextChunks = [];

    final controller = StreamController<Uint8List>();
    Future<void>.delayed(Duration.zero, () async {
      for (final chunk in chunks) {
        controller.add(Uint8List.fromList(utf8.encode(chunk)));
      }
      await controller.close();
    });

    return ResponseBody(
      controller.stream,
      200,
      headers: {
        'content-type': ['text/event-stream'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
