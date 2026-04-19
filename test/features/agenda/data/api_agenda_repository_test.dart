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
  String? lastPatchPath;
  Map<String, dynamic>? lastPatchData;

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
    return nextPostResult;
  }

  @override
  Future<ApiResult> patch(String path,
      {Map<String, dynamic>? data}) async {
    lastPatchPath = path;
    lastPatchData = data;
    return nextPatchResult;
  }
}

Map<String, dynamic> _buildAgendaJson({
  List<Map<String, dynamic>>? items,
  List<Map<String, dynamic>>? routineItems,
}) {
  return {
    'data': {
      'date': '2026-04-19',
      'granularity': 'day',
      'from': '2026-04-19',
      'to': '2026-04-19',
      'items': items ?? [],
      'routine_items': routineItems ?? [],
    },
  };
}

Map<String, dynamic> _sampleActionItem() => {
      'record_id': 'rec-1',
      'text': 'Buy groceries',
      'topic_ref': null,
      'scheduled_for': '2026-04-19',
      'time_window': 'day',
      'origin_role': 'agent',
      'status': 'active',
      'linked_conversation_count': 1,
    };

Map<String, dynamic> _sampleRoutineItem() => {
      'routine_id': 'rtn-1',
      'routine_name': 'Morning routine',
      'scheduled_for': '2026-04-19',
      'start_time': '08:00',
      'overdue': false,
      'status': 'pending',
      'occurrence_id': 'occ-1',
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
          items: [_sampleActionItem()],
          routineItems: [_sampleRoutineItem()],
        )),
      );

      final response = await repo.fetchAgenda('2026-04-19');

      expect(response.date, '2026-04-19');
      expect(response.items, hasLength(1));
      expect(response.items.first.text, 'Buy groceries');
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

  group('markActionItemDone', () {
    test('sends POST to correct path', () async {
      apiClient.nextPostResult = const ApiSuccess();

      await repo.markActionItemDone('rec-1');

      expect(apiClient.lastPostPath, '/records/rec-1/done');
    });

    test('throws on failure', () async {
      apiClient.nextPostResult = const ApiPermanentFailure(
        statusCode: 404,
        message: 'Not found',
      );

      expect(
        () => repo.markActionItemDone('rec-1'),
        throwsA(isA<AgendaException>()),
      );
    });
  });

  group('updateOccurrenceStatus', () {
    test('sends PATCH with correct path and data', () async {
      apiClient.nextPatchResult = const ApiSuccess();

      await repo.updateOccurrenceStatus(
        'rtn-1',
        'occ-1',
        OccurrenceStatus.skipped,
      );

      expect(apiClient.lastPatchPath, '/routines/rtn-1/occurrences/occ-1');
      expect(apiClient.lastPatchData, {'status': 'skipped'});
    });

    test('sends done status', () async {
      apiClient.nextPatchResult = const ApiSuccess();

      await repo.updateOccurrenceStatus(
        'rtn-1',
        'occ-1',
        OccurrenceStatus.done,
      );

      expect(apiClient.lastPatchData, {'status': 'done'});
    });

    test('throws on failure', () async {
      apiClient.nextPatchResult = const ApiTransientFailure(
        reason: 'Connection error',
      );

      expect(
        () => repo.updateOccurrenceStatus(
          'rtn-1',
          'occ-1',
          OccurrenceStatus.skipped,
        ),
        throwsA(isA<AgendaException>()),
      );
    });
  });
}
