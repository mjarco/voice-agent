import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/network/api_client.dart';
import 'package:voice_agent/features/plan/data/api_plan_repository.dart';
import 'package:voice_agent/features/plan/domain/plan_repository.dart';

class _StubApiClient extends ApiClient {
  _StubApiClient() : super(baseUrl: 'https://test.com/api/v1');

  ApiResult nextGetResult = const ApiSuccess(body: '{"data":{}}');
  ApiResult nextPostResult = const ApiSuccess();

  String? lastGetPath;
  String? lastPostPath;

  @override
  Future<ApiResult> get(String path,
      {Map<String, dynamic>? queryParameters}) async {
    lastGetPath = path;
    return nextGetResult;
  }

  @override
  Future<ApiResult> postJson(String path,
      {Map<String, dynamic>? data}) async {
    lastPostPath = path;
    return nextPostResult;
  }
}

Map<String, dynamic> _samplePlanData() => {
      'topics': [],
      'uncategorized': [
        {
          'entry_id': 'e-1',
          'display_text': 'Do thing',
          'plan_bucket': 'committed',
          'confidence': 0.9,
          'conversation_id': 'conv-1',
          'created_at': '2026-04-18T00:00:00.000Z',
        },
      ],
      'rules': [],
      'rules_uncategorized': [],
      'completed': [],
      'completed_uncategorized': [],
      'total_count': 1,
      'observed_at': '2026-04-18T12:00:00.000Z',
    };

void main() {
  late _StubApiClient client;
  late ApiPlanRepository repo;

  setUp(() {
    client = _StubApiClient();
    repo = ApiPlanRepository(client);
  });

  group('ApiPlanRepository.fetchPlan', () {
    test('calls GET /plan', () async {
      client.nextGetResult = ApiSuccess(
        body: jsonEncode({'data': _samplePlanData()}),
      );

      await repo.fetchPlan();

      expect(client.lastGetPath, '/plan');
    });

    test('returns PlanResponse on success', () async {
      client.nextGetResult = ApiSuccess(
        body: jsonEncode({'data': _samplePlanData()}),
      );

      final result = await repo.fetchPlan();

      expect(result.uncategorized, hasLength(1));
      expect(result.totalCount, 1);
    });

    test('throws PlanGeneralException on permanent failure', () async {
      client.nextGetResult =
          const ApiPermanentFailure(statusCode: 500, message: 'Server Error');

      expect(() => repo.fetchPlan(), throwsA(isA<PlanGeneralException>()));
    });

    test('throws PlanGeneralException on transient failure', () async {
      client.nextGetResult =
          const ApiTransientFailure(reason: 'Connection timeout');

      expect(() => repo.fetchPlan(), throwsA(isA<PlanGeneralException>()));
    });

    test('throws PlanGeneralException when not configured', () async {
      client.nextGetResult = const ApiNotConfigured();

      expect(() => repo.fetchPlan(), throwsA(isA<PlanGeneralException>()));
    });

    test('throws PlanGeneralException on missing data envelope', () async {
      client.nextGetResult = const ApiSuccess(body: '{"other": {}}');

      expect(() => repo.fetchPlan(), throwsA(isA<PlanGeneralException>()));
    });
  });

  group('ApiPlanRepository actions', () {
    test('markDone posts to /records/{id}/done', () async {
      await repo.markDone('e-1');
      expect(client.lastPostPath, '/records/e-1/done');
    });

    test('dismiss posts to /records/{id}/dismiss', () async {
      await repo.dismiss('e-1');
      expect(client.lastPostPath, '/records/e-1/dismiss');
    });

    test('confirm posts to /records/{id}/confirm', () async {
      await repo.confirm('e-1');
      expect(client.lastPostPath, '/records/e-1/confirm');
    });

    test('toggleEndorse posts to /records/{id}/endorse', () async {
      await repo.toggleEndorse('e-1');
      expect(client.lastPostPath, '/records/e-1/endorse');
    });

    test('throws PlanConflictException on 409', () async {
      client.nextPostResult =
          const ApiPermanentFailure(statusCode: 409, message: 'Conflict');

      expect(
        () => repo.markDone('e-1'),
        throwsA(isA<PlanConflictException>()),
      );
    });

    test('PlanConflictException has hardcoded message', () async {
      client.nextPostResult =
          const ApiPermanentFailure(statusCode: 409, message: 'Conflict');

      try {
        await repo.markDone('e-1');
        fail('expected exception');
      } on PlanConflictException catch (e) {
        expect(e.message, 'Action not available for this item');
      }
    });

    test('throws PlanGeneralException on other permanent failure', () async {
      client.nextPostResult =
          const ApiPermanentFailure(statusCode: 500, message: 'Server Error');

      expect(
        () => repo.dismiss('e-1'),
        throwsA(isA<PlanGeneralException>()),
      );
    });

    test('throws PlanGeneralException on transient failure', () async {
      client.nextPostResult =
          const ApiTransientFailure(reason: 'Timeout');

      expect(
        () => repo.confirm('e-1'),
        throwsA(isA<PlanGeneralException>()),
      );
    });

    test('throws PlanGeneralException when not configured', () async {
      client.nextPostResult = const ApiNotConfigured();

      expect(
        () => repo.toggleEndorse('e-1'),
        throwsA(isA<PlanGeneralException>()),
      );
    });
  });
}
