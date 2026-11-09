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
  ApiResult nextDeleteResult = const ApiSuccess();

  String? lastGetPath;
  Map<String, dynamic>? lastGetParams;
  String? lastPostPath;
  Map<String, dynamic>? lastPostData;
  String? lastPatchPath;
  Map<String, dynamic>? lastPatchData;
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

Map<String, dynamic> _sampleRoutine({String id = 'rtn-1'}) => {
      'id': id,
      'name': 'Morning routine',
      'kind': 'recurring',
      'rrule': 'FREQ=DAILY',
      'due_on': null,
      'due_window': null,
      'start_time': '08:00',
      'status': 'active',
      'missed': 'lapses',
      'active_since': '2026-04-01',
      'steps': [
        {'text': 'Meditate', 'sort_order': 0},
      ],
      'ended': false,
      'last_day': null,
      'next_due': '2026-04-20',
      'resolved': null,
      'source': 'phone',
      'conversation_id': null,
      'event_id': null,
      'created_at': '2026-04-01T00:00:00Z',
      'updated_at': '2026-04-18T00:00:00Z',
    };

Map<String, dynamic> _sampleOccurrence() => {
      'id': 'occ-1',
      'routine_id': 'rtn-1',
      'scheduled_for': '2026-04-19',
      'status': 'done',
      'created_at': '2026-04-19T08:00:00Z',
      'updated_at': '2026-04-19T08:00:00Z',
    };

String _wrapData(dynamic data) => jsonEncode({'data': data});

String _error(String code, {String? message, Map<String, dynamic>? data}) =>
    jsonEncode({
      'error': {'code': code, 'message': message ?? code},
      'data': ?data,
    });

void main() {
  late _StubApiClient client;
  late ApiRoutinesRepository repo;

  setUp(() {
    client = _StubApiClient();
    repo = ApiRoutinesRepository(client);
  });

  group('fetchRoutines', () {
    test('asks for every status and parses the list', () async {
      client.nextGetResult = ApiSuccess(body: _wrapData([_sampleRoutine()]));

      final routines = await repo.fetchRoutines();

      expect(routines.single.name, 'Morning routine');
      expect(routines.single.steps.single.text, 'Meditate');
      expect(client.lastGetPath, '/routines');
      expect(client.lastGetParams, {'status': 'all'});
    });

    test('throws on transient failure and when not configured', () async {
      client.nextGetResult = const ApiTransientFailure(reason: 'timeout');
      expect(() => repo.fetchRoutines(),
          throwsA(isA<RoutinesGeneralException>()));

      client.nextGetResult = const ApiNotConfigured();
      expect(
        () => repo.fetchRoutines(),
        throwsA(isA<RoutinesGeneralException>()
            .having((e) => e.message, 'message', 'API not configured')),
      );
    });

    test('throws on a null body or a missing envelope', () async {
      client.nextGetResult = const ApiSuccess(body: null);
      expect(
        () => repo.fetchRoutines(),
        throwsA(isA<RoutinesGeneralException>()
            .having((e) => e.message, 'message', 'Empty response')),
      );
      client.nextGetResult = const ApiSuccess(body: '{"other": []}');
      expect(
        () => repo.fetchRoutines(),
        throwsA(isA<RoutinesGeneralException>()
            .having((e) => e.message, 'message', 'Missing data envelope')),
      );
    });
  });

  group('fetchRoutineDetail and fetchOccurrences', () {
    test('parse the routine and its ticks', () async {
      client.nextGetResult = ApiSuccess(body: _wrapData(_sampleRoutine()));
      final routine = await repo.fetchRoutineDetail('rtn-1');
      expect(routine.kind, RoutineKind.recurring);
      expect(client.lastGetPath, '/routines/rtn-1');

      client.nextGetResult = ApiSuccess(body: _wrapData([_sampleOccurrence()]));
      final occs = await repo.fetchOccurrences('rtn-1');
      expect(occs.single.status, OccurrenceStatus.done);
      expect(client.lastGetPath, '/routines/rtn-1/occurrences');
    });

    test('a refused detail throws', () async {
      client.nextGetResult =
          const ApiPermanentFailure(statusCode: 404, message: 'Not Found');
      expect(() => repo.fetchRoutineDetail('x'),
          throwsA(isA<RoutinesGeneralException>()));
    });
  });

  group('status changes', () {
    test('call their endpoints', () async {
      await repo.activateRoutine('rtn-1');
      expect(client.lastPostPath, '/routines/rtn-1/activate');
      await repo.pauseRoutine('rtn-1');
      expect(client.lastPostPath, '/routines/rtn-1/pause');
      await repo.archiveRoutine('rtn-1');
      expect(client.lastPostPath, '/routines/rtn-1/archive');
    });

    test('a 409 is a conflict with the server message', () async {
      client.nextPostResult = ApiPermanentFailure(
        statusCode: 409,
        message: 'Conflict',
        body: _error('invalid_lifecycle_transition',
            message: 'archived is final'),
      );
      expect(
        () => repo.activateRoutine('rtn-1'),
        throwsA(isA<RoutineConflictException>()
            .having((e) => e.message, 'message', 'archived is final')),
      );
    });
  });

  group('createRoutine', () {
    test('a recurring routine: rule with UNTIL, missed, source phone',
        () async {
      client.nextPostResult =
          ApiSuccess(body: _wrapData(_sampleRoutine()), statusCode: 201);

      await repo.createRoutine(const RoutineInput(
        name: 'Gym',
        term: RecurringTerm('FREQ=WEEKLY;BYDAY=MO,WE'),
        startTime: '07:00',
        lastDay: '2026-12-31',
        missed: RoutineMissed.waits,
        steps: ['Shoes'],
      ));

      expect(client.lastPostPath, '/routines');
      expect(client.lastPostData, {
        'name': 'Gym',
        'start_time': '07:00',
        'steps': ['Shoes'],
        'source': 'phone',
        'rrule': 'FREQ=WEEKLY;BYDAY=MO,WE;UNTIL=20261231T235959Z',
        'missed': 'waits',
      });
    });

    test('a one-off sends its day and window, no rule or missed', () async {
      client.nextPostResult = ApiSuccess(body: _wrapData(_sampleRoutine()));

      await repo.createRoutine(const RoutineInput(
        name: 'Call the plumber',
        term: OneOffTerm('2026-11-10', TimeWindow.week),
      ));

      expect(client.lastPostData, {
        'name': 'Call the plumber',
        'start_time': null,
        'steps': <String>[],
        'source': 'phone',
        'due_on': '2026-11-10',
        'due_window': 'week',
      });
    });

    test('a someday routine sends neither', () async {
      client.nextPostResult = ApiSuccess(body: _wrapData(_sampleRoutine()));

      await repo.createRoutine(
          const RoutineInput(name: 'Paint the fence', term: SomedayTerm()));

      expect(client.lastPostData!.keys,
          unorderedEquals(['name', 'start_time', 'steps', 'source']));
    });

    test('a 200 with existing is the live routine of that name', () async {
      client.nextPostResult = ApiSuccess(
          body: _wrapData({..._sampleRoutine(), 'existing': true}),
          statusCode: 200);

      final routine = await repo.createRoutine(
          const RoutineInput(name: 'Morning routine', term: SomedayTerm()));

      expect(routine.existing, isTrue);
    });

    test('a 422 shows the server message; invalid_rrule is typed', () async {
      client.nextPostResult = ApiPermanentFailure(
        statusCode: 422,
        message: 'Unprocessable',
        body: _error('invalid_request', message: 'name too long'),
      );
      expect(
        () => repo.createRoutine(
            const RoutineInput(name: 'x', term: SomedayTerm())),
        throwsA(isA<RoutinesGeneralException>()
            .having((e) => e.message, 'message', 'name too long')),
      );

      client.nextPostResult = ApiPermanentFailure(
        statusCode: 422,
        message: 'Unprocessable',
        body: _error('invalid_rrule', message: 'no day left'),
      );
      expect(
        () => repo.createRoutine(
            const RoutineInput(name: 'x', term: RecurringTerm('FREQ=DAILY'))),
        throwsA(isA<RoutineInvalidRRuleException>()),
      );
    });
  });

  group('editRoutine', () {
    test('PATCHes only the fields the patch sets', () async {
      client.nextPatchResult = ApiSuccess(body: _wrapData(_sampleRoutine()));

      await repo.editRoutine(
          'rtn-1',
          const RoutinePatch(
            name: 'Evening routine',
            startTime: (value: null),
          ));

      expect(client.lastPatchPath, '/routines/rtn-1');
      expect(client.lastPatchData,
          {'name': 'Evening routine', 'start_time': null});
      expect(client.lastPostPath, isNull);
    });

    test('end after a day is a PATCH of last_day', () async {
      client.nextPatchResult = ApiSuccess(body: _wrapData(_sampleRoutine()));

      await repo.editRoutine('rtn-1', const RoutinePatch.endAfter('2026-05-01'));

      expect(client.lastPatchData, {'last_day': '2026-05-01'});
    });

    test('a 409 overdue_occurrence carries the owed day', () async {
      client.nextPatchResult = ApiPermanentFailure(
        statusCode: 409,
        message: 'Conflict',
        body: _error('overdue_occurrence',
            message: 'Najpierw odhacz',
            data: {'routine_id': 'rtn-1', 'scheduled_for': '2026-04-10'}),
      );

      expect(
        () => repo.editRoutine(
            'rtn-1', const RoutinePatch(term: RecurringTerm('FREQ=DAILY'))),
        throwsA(isA<RoutineOverdueException>()
            .having((e) => e.routineId, 'routineId', 'rtn-1')
            .having((e) => e.scheduledFor, 'scheduledFor', '2026-04-10')
            .having((e) => e.message, 'message', 'Najpierw odhacz')),
      );
    });
  });

  test('a 409 name_taken of an edit is typed', () async {
    client.nextPatchResult = ApiPermanentFailure(
      statusCode: 409,
      message: 'Conflict',
      body: _error('name_taken', message: 'name is taken'),
    );
    expect(
      () => repo.editRoutine('rtn-1', const RoutinePatch(name: 'Gym')),
      throwsA(isA<RoutineNameTakenException>()
          .having((e) => e.message, 'message', 'name is taken')),
    );
  });

  test('a 422 invalid_occurrence_date shows the server message', () async {
    client.nextPostResult = ApiPermanentFailure(
      statusCode: 422,
      message: 'Unprocessable',
      body: _error('invalid_occurrence_date', message: 'after today'),
    );
    expect(
      () => repo.resolve('rtn-1', OccurrenceStatus.done,
          scheduledFor: '2026-12-01'),
      throwsA(isA<RoutinesGeneralException>()
          .having((e) => e.message, 'message', 'after today')),
    );
  });

  group('resolve and unresolve', () {
    test('a recurring day is posted with its date', () async {
      await repo.resolve('rtn-1', OccurrenceStatus.skipped,
          scheduledFor: '2026-04-19');

      expect(client.lastPostPath, '/routines/rtn-1/resolve');
      expect(client.lastPostData,
          {'scheduled_for': '2026-04-19', 'status': 'skipped'});
    });

    test('a one-off or someday routine is posted without a day', () async {
      await repo.resolve('rtn-2', OccurrenceStatus.done);

      expect(client.lastPostData, {'status': 'done'});
    });

    test('a 409 already_resolved and routine_not_active are typed', () async {
      client.nextPostResult = ApiPermanentFailure(
          statusCode: 409,
          message: 'Conflict',
          body: _error('already_resolved'));
      expect(() => repo.resolve('rtn-1', OccurrenceStatus.done),
          throwsA(isA<RoutineAlreadyResolvedException>()));

      client.nextPostResult = ApiPermanentFailure(
          statusCode: 409,
          message: 'Conflict',
          body: _error('routine_not_active'));
      expect(() => repo.resolve('rtn-1', OccurrenceStatus.done),
          throwsA(isA<RoutineNotActiveException>()));
    });

    test('unresolve DELETEs the tick, with the day of a recurring one',
        () async {
      await repo.unresolve('rtn-1', scheduledFor: '2026-04-19');
      expect(client.lastDeletePath,
          '/routines/rtn-1/resolve?scheduled_for=2026-04-19');

      await repo.unresolve('rtn-2');
      expect(client.lastDeletePath, '/routines/rtn-2/resolve');
    });

    test('a refused undo throws a conflict', () async {
      client.nextDeleteResult = ApiPermanentFailure(
          statusCode: 409,
          message: 'Conflict',
          body: _error('not_resolved', message: 'no tick that day'));
      expect(
        () => repo.unresolve('rtn-2'),
        throwsA(isA<RoutineConflictException>()
            .having((e) => e.message, 'message', 'no tick that day')),
      );
    });
  });
}
