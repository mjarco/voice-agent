import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/models/matter.dart';
import 'package:voice_agent/core/network/api_client.dart';
import 'package:voice_agent/features/matters/data/api_matters_repository.dart';
import 'package:voice_agent/features/matters/domain/matters_repository.dart';

class _StubApiClient extends ApiClient {
  _StubApiClient() : super(baseUrl: 'https://test.com/api/v1');

  ApiResult next = const ApiSuccess(body: '{"data":[]}');
  final requests = <(String, String, Map<String, dynamic>?)>[];
  Map<String, dynamic>? lastQuery;

  @override
  Future<ApiResult> get(String path,
      {Map<String, dynamic>? queryParameters}) async {
    requests.add(('GET', path, null));
    lastQuery = queryParameters;
    return next;
  }

  @override
  Future<ApiResult> postJson(String path,
      {Map<String, dynamic>? data}) async {
    requests.add(('POST', path, data));
    return next;
  }

  @override
  Future<ApiResult> patch(String path, {Map<String, dynamic>? data}) async {
    requests.add(('PATCH', path, data));
    return next;
  }

  @override
  Future<ApiResult> delete(String path) async {
    requests.add(('DELETE', path, null));
    return next;
  }
}

const _detail = {
  'id': 'm1',
  'title': 'Remont',
  'keywords': '',
  'status': 'active',
  'next_step': '',
  'waiting_for': '',
  'source': 'phone',
  'standing_still': false,
  'link_count': 0,
  'created_at': '2026-11-09T10:00:00Z',
  'updated_at': '2026-11-09T10:00:00Z',
  'timeline': [
    {
      'id': 'e1',
      'kind': 'opened',
      'text': 'Remont',
      'day': '2026-11-09',
      'created_at': '2026-11-09T10:00:00Z',
    },
  ],
  'links': [],
};

ApiResult _ok(Object data) => ApiSuccess(body: jsonEncode({'data': data}));

ApiResult _refused(int status, String code, String message) =>
    ApiPermanentFailure(
      statusCode: status,
      message: 'Conflict',
      body: jsonEncode({
        'error': {'code': code, 'message': message},
      }),
    );

void main() {
  late _StubApiClient api;
  late ApiMattersRepository repo;

  setUp(() {
    api = _StubApiClient();
    repo = ApiMattersRepository(api);
  });

  group('fetchMatters', () {
    test('the default list sends no status', () async {
      api.next = _ok([
        {'id': 'm1', 'title': 'A', 'status': 'active'},
        {'id': 'm2', 'title': 'B', 'status': 'closed'},
      ]);

      final list = await repo.fetchMatters();

      expect(api.requests.single.$2, '/matters');
      expect(api.lastQuery, isNull);
      expect(list.map((m) => m.id), ['m1', 'm2']);
      expect(list.last.status, MatterStatus.closed);
    });

    test('the proposed ones are asked for by status', () async {
      api.next = _ok([]);
      await repo.fetchMatters(filter: MatterFilter.proposed);
      expect(api.lastQuery, {'status': 'proposed'});
    });

    test('a list without the envelope fails', () async {
      api.next = const ApiSuccess(body: '[]');
      expect(repo.fetchMatters(), throwsA(isA<MattersGeneralException>()));
    });
  });

  group('fetchMatter', () {
    test('parses the detail with its timeline', () async {
      api.next = _ok(_detail);
      final d = await repo.fetchMatter('m1');
      expect(api.requests.single.$2, '/matters/m1');
      expect(d.matter.title, 'Remont');
      expect(d.timeline.single.kind, MatterEntryKind.opened);
    });

    test('404 is MatterNotFoundException with the server message', () async {
      api.next = _refused(404, 'not_found', 'matter not found');
      expect(
        repo.fetchMatter('x'),
        throwsA(isA<MatterNotFoundException>()
            .having((e) => e.message, 'message', 'matter not found')),
      );
    });

    test('a transient failure is a general one', () async {
      api.next = const ApiTransientFailure(reason: 'Server error: 500');
      expect(
        repo.fetchMatter('x'),
        throwsA(isA<MattersGeneralException>()
            .having((e) => e.message, 'message', 'Server error: 500')),
      );
    });
  });

  group('writes', () {
    test('create sends the title, the fields given and source phone',
        () async {
      api.next = _ok(_detail);
      final d = await repo.createMatter(title: 'Remont', nextStep: 'wycena');
      final (method, path, body) = api.requests.single;
      expect((method, path), ('POST', '/matters'));
      expect(body, {'title': 'Remont', 'next_step': 'wycena', 'source': 'phone'});
      expect(d.id, 'm1');
    });

    test('create refused as title_taken carries the server message',
        () async {
      api.next =
          _refused(409, 'title_taken', 'Sprawa o tym tytule już istnieje');
      expect(
        repo.createMatter(title: 'Remont'),
        throwsA(isA<MatterRefusedException>()
            .having((e) => e.code, 'code', 'title_taken')
            .having((e) => e.message, 'message',
                'Sprawa o tym tytule już istnieje')),
      );
    });

    test('edit sends only the fields given; an empty one clears', () async {
      api.next = _ok(_detail);
      await repo.editMatter('m1', status: MatterStatus.paused, nextStep: '');
      final (method, path, body) = api.requests.single;
      expect((method, path), ('PATCH', '/matters/m1'));
      expect(body, {'status': 'paused', 'next_step': '', 'source': 'phone'});
    });

    test('accept sends the status', () async {
      api.next = _ok(_detail);
      await repo.accept('m1', MatterStatus.closed);
      final (method, path, body) = api.requests.single;
      expect((method, path), ('POST', '/matters/m1/accept'));
      expect(body, {'status': 'closed'});
    });

    test('accept refused as not_proposed', () async {
      api.next = _refused(409, 'not_proposed', 'matter is not proposed');
      expect(
        repo.accept('m1', MatterStatus.active),
        throwsA(isA<MatterRefusedException>()
            .having((e) => e.code, 'code', 'not_proposed')),
      );
    });

    test('drop and delete answer 204', () async {
      api.next = const ApiSuccess(statusCode: 204);
      await repo.drop('m1');
      await repo.deleteMatter('m2');
      expect(api.requests.map((r) => (r.$1, r.$2)), [
        ('POST', '/matters/m1/drop'),
        ('DELETE', '/matters/m2'),
      ]);
    });

    test('an entry is added with source phone and parsed', () async {
      api.next = _ok({
        'id': 'e9',
        'kind': 'note',
        'text': 'zadzwonił',
        'source': 'phone',
        'day': '2026-11-09',
        'created_at': '2026-11-09T10:00:00Z',
      });
      final e = await repo.addEntry('m1', 'zadzwonił');
      final (method, path, body) = api.requests.single;
      expect((method, path), ('POST', '/matters/m1/entries'));
      expect(body, {'text': 'zadzwonił', 'source': 'phone'});
      expect(e.id, 'e9');
      expect(e.kind, MatterEntryKind.note);
    });

    test('an entry and a link are removed by their paths', () async {
      api.next = const ApiSuccess(statusCode: 204);
      await repo.deleteEntry('m1', 'e1');
      await repo.unlink('m1', 'l1');
      expect(api.requests.map((r) => (r.$1, r.$2)), [
        ('DELETE', '/matters/m1/entries/e1'),
        ('DELETE', '/matters/m1/links/l1?source=phone'),
      ]);
    });

    test('a refusal without an error envelope is a general failure',
        () async {
      api.next = const ApiPermanentFailure(
        statusCode: 400,
        message: 'Bad Request',
      );
      expect(
        repo.deleteEntry('m1', 'e1'),
        throwsA(isA<MattersGeneralException>()
            .having((e) => e.message, 'message', 'Server error 400: Bad Request')),
      );
    });
  });
}
