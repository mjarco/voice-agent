import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/models/transcript.dart';
import 'package:voice_agent/core/network/api_client.dart';

void main() {
  late Dio dio;
  late ApiClient client;

  final transcript = Transcript(
    id: 'tx-1',
    text: 'Hello world',
    language: 'en',
    audioDurationMs: 5000,
    deviceId: 'dev-1',
    createdAt: 1710000000000,
  );

  setUp(() {
    dio = Dio();
    dio.httpClientAdapter = _MockAdapter();
    client = ApiClient(dio: dio);
  });

  group('ApiClient', () {
    test('200 response returns ApiSuccess', () async {
      _MockAdapter.nextStatusCode = 200;
      final result = await client.post(
        transcript,
        url: 'https://example.com/api',
        token: 'test-token',
      );
      expect(result, isA<ApiSuccess>());
    });

    test('201 response returns ApiSuccess', () async {
      _MockAdapter.nextStatusCode = 201;
      final result = await client.post(
        transcript,
        url: 'https://example.com/api',
      );
      expect(result, isA<ApiSuccess>());
    });

    test('400 response returns ApiPermanentFailure', () async {
      _MockAdapter.nextStatusCode = 400;
      final result = await client.post(
        transcript,
        url: 'https://example.com/api',
      );
      expect(result, isA<ApiPermanentFailure>());
      expect((result as ApiPermanentFailure).statusCode, 400);
    });

    test('401 response returns ApiPermanentFailure', () async {
      _MockAdapter.nextStatusCode = 401;
      final result = await client.post(
        transcript,
        url: 'https://example.com/api',
      );
      expect(result, isA<ApiPermanentFailure>());
    });

    test('422 response returns ApiPermanentFailure', () async {
      _MockAdapter.nextStatusCode = 422;
      final result = await client.post(
        transcript,
        url: 'https://example.com/api',
      );
      expect(result, isA<ApiPermanentFailure>());
    });

    test('500 response returns ApiTransientFailure', () async {
      _MockAdapter.nextStatusCode = 500;
      final result = await client.post(
        transcript,
        url: 'https://example.com/api',
      );
      expect(result, isA<ApiTransientFailure>());
    });

    test('503 response returns ApiTransientFailure', () async {
      _MockAdapter.nextStatusCode = 503;
      final result = await client.post(
        transcript,
        url: 'https://example.com/api',
      );
      expect(result, isA<ApiTransientFailure>());
    });

    test('429 response returns ApiTransientFailure', () async {
      _MockAdapter.nextStatusCode = 429;
      final result = await client.post(
        transcript,
        url: 'https://example.com/api',
      );
      expect(result, isA<ApiTransientFailure>());
    });

    test('connection error returns ApiTransientFailure', () async {
      _MockAdapter.shouldThrow = DioException(
        requestOptions: RequestOptions(path: '/'),
        type: DioExceptionType.connectionError,
        message: 'No internet',
      );
      final result = await client.post(
        transcript,
        url: 'https://example.com/api',
      );
      expect(result, isA<ApiTransientFailure>());
      expect(
        (result as ApiTransientFailure).reason,
        contains('Connection error'),
      );
    });

    test('timeout returns ApiTransientFailure', () async {
      _MockAdapter.shouldThrow = DioException(
        requestOptions: RequestOptions(path: '/'),
        type: DioExceptionType.connectionTimeout,
      );
      final result = await client.post(
        transcript,
        url: 'https://example.com/api',
      );
      expect(result, isA<ApiTransientFailure>());
      expect(
        (result as ApiTransientFailure).reason,
        contains('Timeout'),
      );
    });

    test('sends correct JSON body shape', () async {
      _MockAdapter.nextStatusCode = 200;
      _MockAdapter.lastRequestData = null;

      await client.post(
        transcript,
        url: 'https://example.com/api',
        token: 'my-token',
      );

      final data = _MockAdapter.lastRequestData as Map<String, dynamic>;
      expect(data['text'], 'Hello world');
      expect(data['timestamp'], isA<int>());
      expect(data['language'], 'en');
      expect(data['deviceId'], 'dev-1');
    });

    test('sends Authorization header when token provided', () async {
      _MockAdapter.nextStatusCode = 200;
      _MockAdapter.lastHeaders = null;

      await client.post(
        transcript,
        url: 'https://example.com/api',
        token: 'my-token',
      );

      expect(
        _MockAdapter.lastHeaders?['Authorization'],
        'Bearer my-token',
      );
    });

    test('omits Authorization header when token is null', () async {
      _MockAdapter.nextStatusCode = 200;
      _MockAdapter.lastHeaders = null;

      await client.post(
        transcript,
        url: 'https://example.com/api',
      );

      expect(_MockAdapter.lastHeaders?['Authorization'], isNull);
    });

    test('body in ApiSuccess is valid JSON when server returns JSON object',
        () async {
      _MockAdapter.nextStatusCode = 200;
      _MockAdapter.nextResponseBody = '{"message": "Done", "status": "ok"}';

      final result = await client.post(
        transcript,
        url: 'https://example.com/api',
      );

      expect(result, isA<ApiSuccess>());
      final body = (result as ApiSuccess).body;
      expect(body, isNotNull);
      // Must be parseable JSON — this would throw if body is Dart's Map.toString()
      final parsed = jsonDecode(body!) as Map<String, dynamic>;
      expect(parsed['message'], 'Done');
      expect(parsed['status'], 'ok');
    });

    test('body in ApiSuccess preserves message field for TTS', () async {
      _MockAdapter.nextStatusCode = 200;
      _MockAdapter.nextResponseBody =
          '{"message": "Zrozumiałem", "language": "pl"}';

      final result = await client.post(
        transcript,
        url: 'https://example.com/api',
      );

      final body = (result as ApiSuccess).body!;
      final parsed = jsonDecode(body) as Map<String, dynamic>;
      expect(parsed['message'], 'Zrozumiałem');
      expect(parsed['language'], 'pl');
    });
  });
}

class _MockAdapter implements HttpClientAdapter {
  static int nextStatusCode = 200;
  static String nextResponseBody = '{"ok":true}';
  static DioException? shouldThrow;
  static dynamic lastRequestData;
  static Map<String, dynamic>? lastHeaders;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequestData = options.data;
    lastHeaders = options.headers;

    if (shouldThrow != null) {
      final e = shouldThrow!;
      shouldThrow = null;
      throw e;
    }

    final code = nextStatusCode;
    nextStatusCode = 200; // reset

    if (code >= 400) {
      throw DioException(
        requestOptions: options,
        response: Response(
          requestOptions: options,
          statusCode: code,
          statusMessage: 'Error $code',
        ),
        type: DioExceptionType.badResponse,
      );
    }

    final body = nextResponseBody;
    nextResponseBody = '{"ok":true}'; // reset

    return ResponseBody.fromString(
      body,
      code,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
