import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/models/pin.dart';
import 'package:voice_agent/core/network/api_client.dart';
import 'package:voice_agent/features/pins/data/api_pin_writer.dart';
import 'package:voice_agent/features/pins/domain/pins_repository.dart';

class _StubApiClient extends ApiClient {
  _StubApiClient() : super(baseUrl: 'https://test.com/api/v1');

  ApiResult nextPostResult = const ApiSuccess(body: '{"data":{}}');

  String? lastPostPath;
  Map<String, dynamic>? lastPostData;

  @override
  Future<ApiResult> postJson(String path, {Map<String, dynamic>? data}) async {
    lastPostPath = path;
    lastPostData = data;
    return nextPostResult;
  }
}

String _suggestBody() => jsonEncode({
      'data': {
        'name': 'ESP32 GPIO pinout',
        'aliases': ['pinout'],
        'topic_label': 'Electronics',
        'topic_ref': 'topic-1',
      },
    });

String _createBody({bool created = true}) => jsonEncode({
      'data': {
        'pin': {
          'record_id': 'abc123',
          'pin_name': 'garage pinout',
          'topic_label': 'Electronics',
          'text': '# Pinout',
          'created_at': '2026-06-15T10:30:00Z',
        },
        'created': created,
        'superseded_record_id': '',
      },
    });

void main() {
  late _StubApiClient apiClient;
  late ApiPinWriter writer;

  setUp(() {
    apiClient = _StubApiClient();
    writer = ApiPinWriter(apiClient);
  });

  group('suggestPin', () {
    test('posts identity and parses the suggestion', () async {
      apiClient.nextPostResult = ApiSuccess(body: _suggestBody());

      final s = await writer.suggestPin('conv-1', 'event-9');

      expect(apiClient.lastPostPath, '/pins/suggest');
      expect(apiClient.lastPostData,
          {'conversation_id': 'conv-1', 'event_id': 'event-9'});
      expect(s.name, 'ESP32 GPIO pinout');
      expect(s.topicLabel, 'Electronics');
    });

    test('throws PinNotFoundException on 404', () async {
      apiClient.nextPostResult =
          const ApiPermanentFailure(statusCode: 404, message: 'gone');

      expect(
        () => writer.suggestPin('c', 'e'),
        throwsA(isA<PinNotFoundException>()),
      );
    });

    test('throws PinsGeneralException on other permanent failure', () async {
      apiClient.nextPostResult =
          const ApiPermanentFailure(statusCode: 400, message: 'bad');

      expect(
        () => writer.suggestPin('c', 'e'),
        throwsA(isA<PinsGeneralException>()
            .having((e) => e.message, 'message', contains('400'))),
      );
    });

    test('throws PinsGeneralException on transient failure', () async {
      apiClient.nextPostResult =
          const ApiTransientFailure(reason: 'Timeout: connectionTimeout');

      expect(
        () => writer.suggestPin('c', 'e'),
        throwsA(isA<PinsGeneralException>()
            .having((e) => e.message, 'message', contains('Timeout'))),
      );
    });

    test('throws PinsGeneralException on not configured', () async {
      apiClient.nextPostResult = const ApiNotConfigured();

      expect(
        () => writer.suggestPin('c', 'e'),
        throwsA(isA<PinsGeneralException>()
            .having((e) => e.message, 'message', contains('not configured'))),
      );
    });

    test('throws on missing data envelope', () async {
      apiClient.nextPostResult = const ApiSuccess(body: '{"other":1}');

      expect(
        () => writer.suggestPin('c', 'e'),
        throwsA(isA<PinsGeneralException>()),
      );
    });
  });

  group('createPin', () {
    test('posts the request body and parses the result', () async {
      apiClient.nextPostResult = ApiSuccess(body: _createBody());

      final result = await writer.createPin(const PinCreateRequest(
        conversationId: 'conv-1',
        eventId: 'event-9',
        name: 'garage pinout',
        topicLabel: 'Electronics',
      ));

      expect(apiClient.lastPostPath, '/pins');
      expect(apiClient.lastPostData, {
        'conversation_id': 'conv-1',
        'event_id': 'event-9',
        'name': 'garage pinout',
        'topic_label': 'Electronics',
      });
      expect(result.pin.recordId, 'abc123');
      expect(result.created, isTrue);
    });

    test('omits topic_label when empty', () async {
      apiClient.nextPostResult = ApiSuccess(body: _createBody());

      await writer.createPin(const PinCreateRequest(
        conversationId: 'conv-1',
        eventId: 'event-9',
        name: 'n',
      ));

      expect(apiClient.lastPostData!.containsKey('topic_label'), isFalse);
    });

    test('throws PinNotFoundException on 404', () async {
      apiClient.nextPostResult =
          const ApiPermanentFailure(statusCode: 404, message: 'gone');

      expect(
        () => writer.createPin(const PinCreateRequest(
          conversationId: 'c',
          eventId: 'e',
          name: 'n',
        )),
        throwsA(isA<PinNotFoundException>()),
      );
    });

    test('throws PinsGeneralException on 500', () async {
      apiClient.nextPostResult =
          const ApiPermanentFailure(statusCode: 500, message: 'boom');

      expect(
        () => writer.createPin(const PinCreateRequest(
          conversationId: 'c',
          eventId: 'e',
          name: 'n',
        )),
        throwsA(isA<PinsGeneralException>()
            .having((e) => e.message, 'message', contains('500'))),
      );
    });
  });
}
