import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/models/routine.dart';
import 'package:voice_agent/core/network/api_client.dart';
import 'package:voice_agent/features/agenda/data/api_agenda_repository.dart';

class _StubApiClient extends ApiClient {
  _StubApiClient() : super(baseUrl: 'https://test.com/api/v1');

  ApiResult nextGetResult = const ApiSuccess(body: '{"data":{}}');
  ApiResult nextPostResult = const ApiSuccess();
  ApiResult nextPatchResult = const ApiSuccess();

  String? lastGetPath;
  Map<String, dynamic>? lastGetParams;
  String? lastPostPath;
  Map<String, dynamic>? lastPostData;
  String? lastPatchPath;
  Map<String, dynamic>? lastPatchData;
  ApiResult nextDeleteResult = const ApiSuccess();
  String? lastDeletePath;

  @override
  Future<ApiResult> get(String path,
      {Map<String, dynamic>? queryParameters}) async {
    lastGetPath = path;
    lastGetParams = queryParameters;
    return nextGetResult;
  }

  @override
  Future<ApiResult> postJson(String path,
      {Map<String, dynamic>? data}) async {
    lastPostPath = path;
    lastPostData = data;
    return nextPostResult;
  }

  @override
  Future<ApiResult> patch(String path,
      {Map<String, dynamic>? data}) async {
    lastPatchPath = path;
    lastPatchData = data;
    return nextPatchResult;
  }

  @override
  Future<ApiResult> delete(String path) async {
    lastDeletePath = path;
    return nextDeleteResult;
  }
}

Map<String, dynamic> _buildAgendaJson({
  List<Map<String, dynamic>>? routineItems,
}) {
  return {
    'data': {
      'date': '2026-04-19',
      'granularity': 'day',
      'from': '2026-04-19',
      'to': '2026-04-19',
      'routine_items': routineItems ?? [],
    },
  };
}

Map<String, dynamic> _sampleRoutineItem() => {
      'routine_id': 'rtn-1',
      'routine_name': 'Morning routine',
      'kind': 'recurring',
      'scheduled_for': '2026-04-19',
      'due_window': '',
      'start_time': '08:00',
      'overdue': false,
      'status': 'pending',
      'occurrence_id': null,
      'templates': [
        {'text': 'Meditate', 'sort_order': 0},
      ],
    };

void main() {
  late _StubApiClient apiClient;
  late ApiAgendaRepository repo;

  setUp(() {
    apiClient = _StubApiClient();
    repo = ApiAgendaRepository(apiClient);
  });

  group('fetchAgenda', () {
    test('parses successful response with data envelope', () async {
      apiClient.nextGetResult = ApiSuccess(
        body: jsonEncode(_buildAgendaJson(
          routineItems: [_sampleRoutineItem()],
        )),
      );

      final response = await repo.fetchAgenda('2026-04-19');

      expect(response.date, '2026-04-19');
      expect(response.routineItems, hasLength(1));
      expect(response.routineItems.first.routineName, 'Morning routine');
    });

    test('sends correct path and query parameters', () async {
      apiClient.nextGetResult = ApiSuccess(
        body: jsonEncode(_buildAgendaJson()),
      );

      await repo.fetchAgenda('2026-04-20');

      expect(apiClient.lastGetPath, '/agenda');
      expect(apiClient.lastGetParams, {
        'date': '2026-04-20',
        'granularity': 'day',
      });
    });

    test('throws on empty body', () async {
      apiClient.nextGetResult = const ApiSuccess(body: null);

      expect(
        () => repo.fetchAgenda('2026-04-19'),
        throwsA(isA<AgendaException>()),
      );
    });

    test('throws on missing data envelope', () async {
      apiClient.nextGetResult = const ApiSuccess(
        body: '{"other": "value"}',
      );

      expect(
        () => repo.fetchAgenda('2026-04-19'),
        throwsA(isA<AgendaException>()),
      );
    });

    test('throws on permanent failure', () async {
      apiClient.nextGetResult = const ApiPermanentFailure(
        statusCode: 404,
        message: 'Not found',
      );

      expect(
        () => repo.fetchAgenda('2026-04-19'),
        throwsA(
          isA<AgendaException>().having(
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
        () => repo.fetchAgenda('2026-04-19'),
        throwsA(
          isA<AgendaException>().having(
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
        () => repo.fetchAgenda('2026-04-19'),
        throwsA(
          isA<AgendaException>().having(
            (e) => e.message,
            'message',
            contains('not configured'),
          ),
        ),
      );
    });
  });

  group('refreshCalendars', () {
    test('sends POST /calendar/refresh without a body (#375)', () async {
      apiClient.nextPostResult = const ApiSuccess();

      await repo.refreshCalendars();

      expect(apiClient.lastPostPath, '/calendar/refresh');
      expect(apiClient.lastPostData, isNull);
    });

    test('an older personal-agent without the route throws', () async {
      apiClient.nextPostResult = const ApiPermanentFailure(
        statusCode: 404,
        message: 'Not found',
      );

      expect(
        () => repo.refreshCalendars(),
        throwsA(isA<AgendaException>()),
      );
    });
  });

  group('resolveOccurrence', () {
    test('a recurring row sends its day and the status', () async {
      await repo.resolveOccurrence(
        'rtn-1',
        OccurrenceStatus.skipped,
        scheduledFor: '2026-09-10',
      );

      expect(apiClient.lastPostPath, '/routines/rtn-1/resolve');
      expect(apiClient.lastPostData,
          {'scheduled_for': '2026-09-10', 'status': 'skipped'});
      expect(apiClient.lastPatchPath, isNull);
    });

    test('a one-off sends no day', () async {
      await repo.resolveOccurrence('rtn-2', OccurrenceStatus.done);

      expect(apiClient.lastPostData, {'status': 'done'});
    });

    test('a refusal carries the server status and code', () async {
      apiClient.nextPostResult = const ApiPermanentFailure(
        statusCode: 409,
        message: 'Conflict',
        body: '{"error":{"code":"routine_not_active","message":"paused"}}',
      );

      expect(
        () => repo.resolveOccurrence('rtn-1', OccurrenceStatus.done,
            scheduledFor: '2026-10-26'),
        throwsA(isA<AgendaException>()
            .having((e) => e.statusCode, 'statusCode', 409)
            .having((e) => e.code, 'code', 'routine_not_active')),
      );
    });

    test('a transient failure has no status', () async {
      apiClient.nextPostResult = const ApiTransientFailure(
        reason: 'Connection error',
      );

      expect(
        () => repo.resolveOccurrence('rtn-1', OccurrenceStatus.skipped,
            scheduledFor: '2026-10-26'),
        throwsA(isA<AgendaException>()
            .having((e) => e.statusCode, 'statusCode', isNull)),
      );
    });
  });

  group('unresolveOccurrence', () {
    test('a recurring row deletes the tick of its day', () async {
      await repo.unresolveOccurrence('rtn-1', scheduledFor: '2026-09-10');

      expect(apiClient.lastDeletePath,
          '/routines/rtn-1/resolve?scheduled_for=2026-09-10');
    });

    test('a one-off deletes its only tick', () async {
      await repo.unresolveOccurrence('rtn-2');

      expect(apiClient.lastDeletePath, '/routines/rtn-2/resolve');
    });

    test('a refusal throws', () async {
      apiClient.nextDeleteResult = const ApiPermanentFailure(
        statusCode: 409,
        message: 'Conflict',
        body: '{"error":{"code":"not_resolved"}}',
      );

      expect(
        () => repo.unresolveOccurrence('rtn-2'),
        throwsA(isA<AgendaException>()
            .having((e) => e.code, 'code', 'not_resolved')),
      );
    });
  });
}
