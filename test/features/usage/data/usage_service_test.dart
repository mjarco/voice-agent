import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/network/api_client.dart';
import 'package:voice_agent/features/usage/data/usage_service.dart';

class _StubApiClient extends ApiClient {
  _StubApiClient() : super(baseUrl: 'https://test.com/api/v1');

  ApiResult nextGetResult = const ApiSuccess(body: '{}');

  String? lastGetPath;
  Map<String, dynamic>? lastGetParams;

  @override
  Future<ApiResult> get(String path,
      {Map<String, dynamic>? queryParameters}) async {
    lastGetPath = path;
    lastGetParams = queryParameters;
    return nextGetResult;
  }
}

Map<String, dynamic> _sampleResponse() => {
      'period': {'from': '2026-04-01', 'to': '2026-04-23'},
      'total_cost_usd': 12.34,
      'total_cost_pln': 49.36,
      'total_input_tokens': 1234567,
      'total_output_tokens': 567890,
      'total_requests': 42,
      'daily': [
        {
          'date': '2026-04-01',
          'cost_usd': 0.56,
          'cost_pln': 2.24,
          'requests': 3,
          'models': {
            'claude-sonnet-4-20250514': {'cost_usd': 0.40},
          },
        },
      ],
    };

void main() {
  late _StubApiClient apiClient;
  late UsageService service;

  setUp(() {
    apiClient = _StubApiClient();
    service = UsageService(apiClient);
  });

  group('getSummary', () {
    test('sends correct path and query parameters', () async {
      apiClient.nextGetResult = ApiSuccess(
        body: jsonEncode(_sampleResponse()),
      );

      await service.getSummary(from: '2026-04-01', to: '2026-04-23');

      expect(apiClient.lastGetPath, '/usage/summary');
      expect(apiClient.lastGetParams, {
        'from': '2026-04-01',
        'to': '2026-04-23',
      });
    });

    test('parses successful response', () async {
      apiClient.nextGetResult = ApiSuccess(
        body: jsonEncode(_sampleResponse()),
      );

      final summary =
          await service.getSummary(from: '2026-04-01', to: '2026-04-23');

      expect(summary.periodFrom, '2026-04-01');
      expect(summary.periodTo, '2026-04-23');
      expect(summary.totalCostUsd, 12.34);
      expect(summary.totalCostPln, 49.36);
      expect(summary.totalInputTokens, 1234567);
      expect(summary.totalOutputTokens, 567890);
      expect(summary.totalRequests, 42);
      expect(summary.daily, hasLength(1));
      expect(summary.daily[0].models, hasLength(1));
    });

    test('throws on empty body', () async {
      apiClient.nextGetResult = const ApiSuccess(body: null);

      expect(
        () => service.getSummary(from: '2026-04-01', to: '2026-04-23'),
        throwsA(isA<UsageException>()),
      );
    });

    test('throws on permanent failure', () async {
      apiClient.nextGetResult = const ApiPermanentFailure(
        statusCode: 404,
        message: 'Not found',
      );

      expect(
        () => service.getSummary(from: '2026-04-01', to: '2026-04-23'),
        throwsA(
          isA<UsageException>().having(
            (e) => e.message,
            'message',
            contains('404'),
          ),
        ),
      );
    });

    test('throws on transient failure', () async {
      apiClient.nextGetResult = const ApiTransientFailure(
        reason: 'Timeout: connectionTimeout',
      );

      expect(
        () => service.getSummary(from: '2026-04-01', to: '2026-04-23'),
        throwsA(
          isA<UsageException>().having(
            (e) => e.message,
            'message',
            contains('Timeout'),
          ),
        ),
      );
    });

    test('throws on not configured', () async {
      apiClient.nextGetResult = const ApiNotConfigured();

      expect(
        () => service.getSummary(from: '2026-04-01', to: '2026-04-23'),
        throwsA(
          isA<UsageException>().having(
            (e) => e.message,
            'message',
            contains('not configured'),
          ),
        ),
      );
    });
  });
}
