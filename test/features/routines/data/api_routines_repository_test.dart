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

  group('updateOccurrenceStatus', () {
    test('sends status in body', () async {
      await repo.updateOccurrenceStatus(
          'rtn-1', 'occ-1', OccurrenceStatus.done);

      expect(client.lastPatchPath, '/routines/rtn-1/occurrences/occ-1');
      expect(client.lastPatchData, {'status': 'done'});
    });
  });

  const input = RoutineInput(
    name: 'Trening',
    rrule: 'FREQ=WEEKLY;BYDAY=MO,WE',
    startTime: '18:00',
    lastDay: '2026-12-31',
    missed: RoutineMissed.lapses,
    items: ['rozgrzewka', 'bieg'],
  );

  group('createRoutine', () {
    test('posts the form and parses the routine', () async {
      client.nextPostResult = ApiSuccess(body: _wrapData(_sampleRoutine()));

      final routine = await repo.createRoutine(input);

      expect(routine.id, 'rtn-1');
      expect(client.lastPostPath, '/routines');
      expect(client.lastPostData, {
        'name': 'Trening',
        'rrule': 'FREQ=WEEKLY;BYDAY=MO,WE',
        'start_time': '18:00',
        'last_day': '2026-12-31',
        'missed': 'lapses',
        'items': ['rozgrzewka', 'bieg'],
      });
    });

    test('shows the server message of a 409 name clash', () async {
      client.nextPostResult = ApiPermanentFailure(
        statusCode: 409,
        message: 'Conflict',
        body: jsonEncode({
          'data': {'existing_routine_id': 'rtn-0'},
          'error': {
            'code': 'routine_name_exists',
            'message': 'Rutyna o tej nazwie już istnieje',
          },
        }),
      );

      expect(
        () => repo.createRoutine(input),
        throwsA(isA<RoutineFieldException>()
            .having((e) => e.field, 'field', RoutineFormField.name)
            .having((e) => e.message, 'message',
                'Rutyna o tej nazwie już istnieje')),
      );
    });

    test('a 422 invalid_last_day names the last day and its first day',
        () async {
      client.nextPostResult = ApiPermanentFailure(
        statusCode: 422,
        message: 'Unprocessable Entity',
        body: jsonEncode({
          'data': {'first_day': '2026-11-02'},
          'error': {'code': 'invalid_last_day', 'message': 'no day'},
        }),
      );

      expect(
        () => repo.createRoutine(input),
        throwsA(isA<RoutineFieldException>()
            .having((e) => e.field, 'field', RoutineFormField.lastDay)
            .having((e) => e.firstDay, 'firstDay', '2026-11-02')
            .having((e) => e.firstDayKnown, 'firstDayKnown', isTrue)),
      );
    });

    test('a null first_day is known, a missing one is not', () async {
      client.nextPostResult = ApiPermanentFailure(
        statusCode: 422,
        message: 'Unprocessable Entity',
        body: jsonEncode({
          'data': {'first_day': null},
          'error': {'code': 'invalid_last_day', 'message': 'no day'},
        }),
      );
      await expectLater(
        () => repo.createRoutine(input),
        throwsA(isA<RoutineFieldException>()
            .having((e) => e.firstDay, 'firstDay', isNull)
            .having((e) => e.firstDayKnown, 'firstDayKnown', isTrue)),
      );

      client.nextPostResult = ApiPermanentFailure(
        statusCode: 422,
        message: 'Unprocessable Entity',
        body: jsonEncode({
          'error': {'code': 'invalid_last_day', 'message': 'no day'},
        }),
      );
      await expectLater(
        () => repo.createRoutine(input),
        throwsA(isA<RoutineFieldException>()
            .having((e) => e.firstDayKnown, 'firstDayKnown', isFalse)
            .having((e) => e.message, 'message', 'no day')),
      );
    });

    test('shows the server message of a 422', () async {
      client.nextPostResult = ApiPermanentFailure(
        statusCode: 422,
        message: 'Unprocessable Entity',
        body: jsonEncode({
          'error': {'code': 'invalid_rrule', 'message': 'Zły harmonogram'},
        }),
      );

      expect(
        () => repo.createRoutine(input),
        throwsA(isA<RoutinesGeneralException>()
            .having((e) => e.message, 'message', 'Zły harmonogram')),
      );
    });
  });

  group('editRoutine', () {
    test('posts the form with starts_on', () async {
      client.nextPostResult =
          ApiSuccess(body: _wrapData(_sampleRoutine(id: 'rtn-2')));

      final routine =
          await repo.editRoutine('rtn-1', input, startsOn: '2026-10-28');

      expect(routine.id, 'rtn-2');
      expect(client.lastPostPath, '/routines/rtn-1/edit');
      expect(client.lastPostData?['starts_on'], '2026-10-28');
      expect(client.lastPostData?['name'], 'Trening');
    });

    test('a 409 overdue_occurrence carries the owed day', () async {
      client.nextPostResult = ApiPermanentFailure(
        statusCode: 409,
        message: 'Conflict',
        body: jsonEncode({
          'data': {'routine_id': 'rtn-0', 'scheduled_for': '2026-10-10'},
          'error': {
            'code': 'overdue_occurrence',
            'message': 'Najpierw odhacz albo pomiń zaległe wystąpienie',
          },
        }),
      );

      expect(
        () => repo.editRoutine('rtn-1', input, startsOn: '2026-10-28'),
        throwsA(isA<RoutineOverdueException>()
            .having((e) => e.routineId, 'routineId', 'rtn-0')
            .having((e) => e.scheduledFor, 'scheduledFor', '2026-10-10')
            .having((e) => e.openDays, 'openDays', isNull)),
      );
    });

    test('a 409 overdue_occurrence carries open_days', () async {
      client.nextPostResult = ApiPermanentFailure(
        statusCode: 409,
        message: 'Conflict',
        body: jsonEncode({
          'data': {
            'routine_id': 'rtn-0',
            'scheduled_for': '2026-09-10',
            'open_days': 2,
          },
          'error': {'code': 'overdue_occurrence', 'message': 'owed'},
        }),
      );

      expect(
        () => repo.editRoutine('rtn-1', input, startsOn: '2026-10-28'),
        throwsA(isA<RoutineOverdueException>()
            .having((e) => e.openDays, 'openDays', 2)),
      );
    });

    test('a 422 invalid_starts_on names the start day', () async {
      client.nextPostResult = ApiPermanentFailure(
        statusCode: 422,
        message: 'Unprocessable Entity',
        body: jsonEncode({
          'error': {
            'code': 'invalid_starts_on',
            'message': 'starts_on must not be before 2026-10-28',
          },
        }),
      );

      expect(
        () => repo.editRoutine('rtn-1', input, startsOn: '2026-10-27'),
        throwsA(isA<RoutineFieldException>()
            .having((e) => e.field, 'field', RoutineFormField.startsOn)
            .having((e) => e.message, 'message',
                'starts_on must not be before 2026-10-28')),
      );
    });

    test('a 409 routine_not_active and a 422 no_change are typed (#369)',
        () async {
      client.nextPostResult = ApiPermanentFailure(
        statusCode: 409,
        message: 'Conflict',
        body: jsonEncode({
          'error': {'code': 'routine_not_active', 'message': 'resume it first'},
        }),
      );
      await expectLater(
        () => repo.editRoutine('rtn-1', input, startsOn: '2026-10-28'),
        throwsA(isA<RoutineNotActiveException>()),
      );

      client.nextPostResult = ApiPermanentFailure(
        statusCode: 422,
        message: 'Unprocessable Entity',
        body: jsonEncode({
          'error': {'code': 'no_change', 'message': 'nothing'},
        }),
      );
      await expectLater(
        () => repo.editRoutine('rtn-1', input, startsOn: '2026-10-28'),
        throwsA(isA<RoutineNoChangeException>()),
      );
    });

    test('a 409 routine_already_edited is a stale edit', () async {
      client.nextPostResult = ApiPermanentFailure(
        statusCode: 409,
        message: 'Conflict',
        body: jsonEncode({
          'error': {
            'code': 'routine_already_edited',
            'message': 'routine: already replaced by a newer version',
          },
        }),
      );

      expect(
        () => repo.editRoutine('rtn-1', input, startsOn: '2026-10-28'),
        throwsA(isA<RoutineAlreadyEditedException>()),
      );
    });
  });

  group('endRoutine', () {
    test('posts the last day', () async {
      await repo.endRoutine('rtn-1', '2026-10-26');

      expect(client.lastPostPath, '/routines/rtn-1/end');
      expect(client.lastPostData, {'last_day': '2026-10-26'});
    });
  });

  group('resolveOccurrence', () {
    test('posts the day and status', () async {
      await repo.resolveOccurrence(
          'rtn-1', '2026-10-10', OccurrenceStatus.skipped);

      expect(client.lastPostPath, '/routines/rtn-1/resolve');
      expect(client.lastPostData,
          {'scheduled_for': '2026-10-10', 'status': 'skipped'});
    });

    test('a 409 already_resolved says the day is resolved', () async {
      client.nextPostResult = ApiPermanentFailure(
        statusCode: 409,
        message: 'Conflict',
        body: jsonEncode({
          'error': {'code': 'already_resolved', 'message': 'resolved'},
        }),
      );

      expect(
        () => repo.resolveOccurrence(
            'rtn-1', '2026-10-10', OccurrenceStatus.done),
        throwsA(isA<RoutineAlreadyResolvedException>()),
      );
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
