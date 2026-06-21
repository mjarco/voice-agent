import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/network/api_client.dart';
import 'package:voice_agent/features/pins/data/api_pins_repository.dart';
import 'package:voice_agent/features/pins/domain/pins_repository.dart';

class _StubApiClient extends ApiClient {
  _StubApiClient() : super(baseUrl: 'https://test.com/api/v1');

  ApiResult nextGetResult = const ApiSuccess(body: '{"data":[]}');
  ApiResult nextDeleteResult = const ApiSuccess();

  String? lastGetPath;
  Map<String, dynamic>? lastGetParams;
  String? lastDeletePath;

  @override
  Future<ApiResult> get(String path,
      {Map<String, dynamic>? queryParameters}) async {
    lastGetPath = path;
    lastGetParams = queryParameters;
    return nextGetResult;
  }

  @override
  Future<ApiResult> delete(String path) async {
    lastDeletePath = path;
    return nextDeleteResult;
  }
}

Map<String, dynamic> _summaryJson({String? topicLabel = 'Electronics'}) {
  final map = <String, dynamic>{
    'record_id': 'abc123',
    'pin_name': 'garage pinout',
    'created_at': '2026-06-15T10:30:00Z',
  };
  if (topicLabel != null) map['topic_label'] = topicLabel;
  return map;
}

Map<String, dynamic> _detailJson() => {
      'data': {
        'record_id': 'abc123',
        'pin_name': 'garage pinout',
        'topic_label': 'Electronics',
        'text': '# Pinout',
        'aliases': ['pinout'],
        'source_event_ids': ['event-456'],
        'created_at': '2026-06-15T10:30:00Z',
      },
    };

void main() {
  late _StubApiClient apiClient;
  late ApiPinsRepository repo;

  setUp(() {
    apiClient = _StubApiClient();
    repo = ApiPinsRepository(apiClient);
  });

  group('fetchPins', () {
    test('parses the list envelope', () async {
      apiClient.nextGetResult = ApiSuccess(
        body: jsonEncode({
          'data': [_summaryJson(), _summaryJson(topicLabel: null)],
        }),
      );

      final pins = await repo.fetchPins(PinView.recent);

      expect(pins, hasLength(2));
      expect(pins.first.pinName, 'garage pinout');
      expect(pins[1].topicLabel, isNull);
    });

    test('sends the view query parameter', () async {
      apiClient.nextGetResult = const ApiSuccess(body: '{"data":[]}');

      await repo.fetchPins(PinView.topic);

      expect(apiClient.lastGetPath, '/pins');
      expect(apiClient.lastGetParams, {'view': 'topic'});
    });

    test('throws on missing data envelope', () async {
      apiClient.nextGetResult = const ApiSuccess(body: '{"other":1}');

      expect(
        () => repo.fetchPins(PinView.recent),
        throwsA(isA<PinsGeneralException>()),
      );
    });

    test('throws on transient failure', () async {
      apiClient.nextGetResult =
          const ApiTransientFailure(reason: 'Timeout: connectionTimeout');

      expect(
        () => repo.fetchPins(PinView.recent),
        throwsA(isA<PinsGeneralException>()
            .having((e) => e.message, 'message', contains('Timeout'))),
      );
    });

    test('throws on not configured', () async {
      apiClient.nextGetResult = const ApiNotConfigured();

      expect(
        () => repo.fetchPins(PinView.recent),
        throwsA(isA<PinsGeneralException>()
            .having((e) => e.message, 'message', contains('not configured'))),
      );
    });
  });

  group('fetchPin', () {
    test('parses the detail envelope', () async {
      apiClient.nextGetResult = ApiSuccess(body: jsonEncode(_detailJson()));

      final pin = await repo.fetchPin('abc123');

      expect(apiClient.lastGetPath, '/pins/abc123');
      expect(pin.text, '# Pinout');
      expect(pin.aliases, ['pinout']);
    });

    test('throws PinNotFoundException on 404', () async {
      apiClient.nextGetResult =
          const ApiPermanentFailure(statusCode: 404, message: 'not found');

      expect(
        () => repo.fetchPin('missing'),
        throwsA(isA<PinNotFoundException>()),
      );
    });

    test('throws PinsGeneralException on other permanent failure', () async {
      apiClient.nextGetResult =
          const ApiPermanentFailure(statusCode: 400, message: 'bad');

      expect(
        () => repo.fetchPin('abc123'),
        throwsA(isA<PinsGeneralException>()
            .having((e) => e.message, 'message', contains('400'))),
      );
    });
  });

  group('unpin', () {
    test('sends DELETE to the pin path', () async {
      apiClient.nextDeleteResult = const ApiSuccess();

      await repo.unpin('abc123');

      expect(apiClient.lastDeletePath, '/pins/abc123');
    });

    test('throws PinNotFoundException on 404', () async {
      apiClient.nextDeleteResult =
          const ApiPermanentFailure(statusCode: 404, message: 'not found');

      expect(
        () => repo.unpin('missing'),
        throwsA(isA<PinNotFoundException>()),
      );
    });

    test('throws PinsGeneralException on transient failure', () async {
      apiClient.nextDeleteResult =
          const ApiTransientFailure(reason: 'Connection error');

      expect(
        () => repo.unpin('abc123'),
        throwsA(isA<PinsGeneralException>()),
      );
    });
  });
}
