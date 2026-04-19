import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/models/routine.dart';
import 'package:voice_agent/core/network/api_client.dart';
import 'package:voice_agent/features/routines/data/api_routines_repository.dart';
import 'package:voice_agent/features/routines/domain/routines_repository.dart';

class _StubApiClient extends ApiClient {
  _StubApiClient() : super(baseUrl: 'https://test.com/api/v1');

  ApiResult nextGetResult = const ApiSuccess(body: '{"data":[]}');
  ApiResult nextPostResult = const ApiSuccess();
  ApiResult nextPatchResult = const ApiSuccess();

  String? lastGetPath;
  Map<String, dynamic>? lastGetParams;
  String? lastPostPath;
  Map<String, dynamic>? lastPostData;
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
}

Map<String, dynamic> _sampleRoutine({String id = 'rtn-1'}) => {
      'id': id,
      'source_record_id': 'src-1',
      'name': 'Morning routine',
      'rrule': 'FREQ=DAILY',
      'cadence': 'daily',
      'start_time': '08:00',
      'status': 'active',
      'templates': [
        {'id': 'tpl-1', 'text': 'Meditate', 'sort_order': 1},
      ],
      'next_occurrence': {'date': '2026-04-20', 'time_window': 'day'},
      'created_at': '2026-04-01T00:00:00.000Z',
      'updated_at': '2026-04-18T00:00:00.000Z',
    };

Map<String, dynamic> _sampleOccurrence() => {
      'id': 'occ-1',
      'routine_id': 'rtn-1',
      'scheduled_for': '2026-04-19',
      'time_window': 'day',
      'status': 'pending',
      'conversation_id': null,
      'created_at': '2026-04-19T08:00:00.000Z',
      'updated_at': '2026-04-19T08:00:00.000Z',
    };

Map<String, dynamic> _sampleProposal() => {
      'id': 'prop-1',
      'topic_ref': 'topic-1',
      'name': 'Weekly review',
      'cadence': 'weekly',
      'start_time': '18:00',
      'items': [
        {'text': 'Review completed items', 'sort_order': 1},
      ],
      'confidence': 0.85,
      'conversation_id': 'conv-1',
      'created_at': '2026-04-18T00:00:00.000Z',
    };

String _wrapData(dynamic data) => jsonEncode({'data': data});

void main() {
  late _StubApiClient client;
  late ApiRoutinesRepository repo;

  setUp(() {
    client = _StubApiClient();
    repo = ApiRoutinesRepository(client);
  });

  group('fetchRoutines', () {
    test('parses list from data envelope', () async {
      client.nextGetResult =
          ApiSuccess(body: _wrapData([_sampleRoutine()]));

      final routines = await repo.fetchRoutines(RoutineStatus.active);

      expect(routines, hasLength(1));
      expect(routines.first.name, 'Morning routine');
      expect(client.lastGetPath, '/routines');
      expect(client.lastGetParams, {'status': 'active'});
    });

    test('returns empty list for empty data', () async {
      client.nextGetResult = ApiSuccess(body: _wrapData([]));

      final routines = await repo.fetchRoutines(RoutineStatus.draft);
      expect(routines, isEmpty);
    });

    test('throws on transient failure', () async {
      client.nextGetResult =
          const ApiTransientFailure(reason: 'timeout');

      expect(
        () => repo.fetchRoutines(RoutineStatus.active),
        throwsA(isA<RoutinesGeneralException>()),
      );
    });

    test('throws on not configured', () async {
      client.nextGetResult = const ApiNotConfigured();

      expect(
        () => repo.fetchRoutines(RoutineStatus.active),
        throwsA(isA<RoutinesGeneralException>().having(
          (e) => e.message,
          'message',
          'API not configured',
        )),
      );
    });
  });

  group('fetchRoutineDetail', () {
    test('parses single routine from data envelope', () async {
      client.nextGetResult =
          ApiSuccess(body: _wrapData(_sampleRoutine()));

      final routine = await repo.fetchRoutineDetail('rtn-1');

      expect(routine.id, 'rtn-1');
      expect(routine.templates, hasLength(1));
      expect(client.lastGetPath, '/routines/rtn-1');
    });

    test('throws on permanent failure', () async {
      client.nextGetResult =
          const ApiPermanentFailure(statusCode: 404, message: 'Not found');

      expect(
        () => repo.fetchRoutineDetail('bad-id'),
        throwsA(isA<RoutinesGeneralException>()),
      );
    });
  });

  group('fetchOccurrences', () {
    test('parses occurrence list', () async {
      client.nextGetResult =
          ApiSuccess(body: _wrapData([_sampleOccurrence()]));

      final occs = await repo.fetchOccurrences('rtn-1');

      expect(occs, hasLength(1));
      expect(occs.first.status, OccurrenceStatus.pending);
      expect(client.lastGetPath, '/routines/rtn-1/occurrences');
    });
  });

  group('fetchProposals', () {
    test('parses proposal list', () async {
      client.nextGetResult =
          ApiSuccess(body: _wrapData([_sampleProposal()]));

      final proposals = await repo.fetchProposals();

      expect(proposals, hasLength(1));
      expect(proposals.first.name, 'Weekly review');
      expect(proposals.first.confidence, 0.85);
      expect(client.lastGetPath, '/routine-proposals');
    });
  });

  group('activateRoutine', () {
    test('calls correct endpoint', () async {
      await repo.activateRoutine('rtn-1');
      expect(client.lastPostPath, '/routines/rtn-1/activate');
    });

    test('throws on failure', () async {
      client.nextPostResult =
          const ApiPermanentFailure(statusCode: 422, message: 'Invalid');

      expect(
        () => repo.activateRoutine('rtn-1'),
        throwsA(isA<RoutinesGeneralException>()),
      );
    });
  });

  group('pauseRoutine', () {
    test('calls correct endpoint', () async {
      await repo.pauseRoutine('rtn-1');
      expect(client.lastPostPath, '/routines/rtn-1/pause');
    });
  });

  group('archiveRoutine', () {
    test('calls correct endpoint', () async {
      await repo.archiveRoutine('rtn-1');
      expect(client.lastPostPath, '/routines/rtn-1/archive');
    });

    test('throws RoutineConflictException on 409', () async {
      client.nextPostResult =
          const ApiPermanentFailure(statusCode: 409, message: 'Already archived');

      expect(
        () => repo.archiveRoutine('rtn-1'),
        throwsA(isA<RoutineConflictException>()),
      );
    });
  });

  group('triggerRoutine', () {
    test('sends scheduled_for in body', () async {
      await repo.triggerRoutine('rtn-1', '2026-04-19');

      expect(client.lastPostPath, '/routines/rtn-1/trigger');
      expect(client.lastPostData, {'scheduled_for': '2026-04-19'});
    });

    test('throws RoutineAlreadyTriggedException on 409', () async {
      client.nextPostResult =
          const ApiPermanentFailure(statusCode: 409, message: 'Conflict');

      expect(
        () => repo.triggerRoutine('rtn-1', '2026-04-19'),
        throwsA(isA<RoutineAlreadyTriggedException>()),
      );
    });
  });

  group('updateOccurrenceStatus', () {
    test('sends status in body', () async {
      await repo.updateOccurrenceStatus(
          'rtn-1', 'occ-1', OccurrenceStatus.done);

      expect(client.lastPatchPath, '/routines/rtn-1/occurrences/occ-1');
      expect(client.lastPatchData, {'status': 'done'});
    });
  });

  group('approveProposal', () {
    test('calls correct endpoint', () async {
      await repo.approveProposal('prop-1');
      expect(client.lastPostPath, '/records/prop-1/approve-as-routine');
    });
  });

  group('rejectProposal', () {
    test('calls correct endpoint', () async {
      await repo.rejectProposal('prop-1');
      expect(client.lastPostPath, '/records/prop-1/reject');
    });
  });

  group('error handling', () {
    test('throws on null body', () async {
      client.nextGetResult = const ApiSuccess(body: null);

      expect(
        () => repo.fetchRoutines(RoutineStatus.active),
        throwsA(isA<RoutinesGeneralException>().having(
          (e) => e.message,
          'message',
          'Empty response',
        )),
      );
    });

    test('throws on missing data key', () async {
      client.nextGetResult = const ApiSuccess(body: '{"other": []}');

      expect(
        () => repo.fetchRoutines(RoutineStatus.active),
        throwsA(isA<RoutinesGeneralException>().having(
          (e) => e.message,
          'message',
          'Missing data envelope',
        )),
      );
    });
  });
}
