import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/models/shopping_proposal.dart';
import 'package:voice_agent/core/network/api_client.dart';
import 'package:voice_agent/core/network/shopping_proposals_port.dart';
import 'package:voice_agent/features/shopping/data/api_shopping_proposals.dart';

class _StubApiClient extends ApiClient {
  _StubApiClient() : super(baseUrl: 'https://test.com/api/v1');

  ApiResult nextResult = const ApiSuccess(body: '{"data":[]}');
  String? lastPath;
  Map<String, dynamic>? lastParams;

  @override
  Future<ApiResult> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    lastPath = path;
    lastParams = queryParameters;
    return nextResult;
  }

  @override
  Future<ApiResult> postJson(String path, {Map<String, dynamic>? data}) async {
    lastPath = path;
    return nextResult;
  }
}

const _proposal = {
  'id': 'p1',
  'kind': 'add',
  'text': 'filtr do wody',
  'state': 'accepted',
  'conversation_id': 'c1',
  'user_event_id': 'u1',
  'created_at': '2026-11-01T12:00:00Z',
  'resolved_at': '2026-11-01T12:05:00Z',
};

ApiResult _conflict(String code, {Object? data}) => ApiPermanentFailure(
      statusCode: 409,
      message: 'Conflict',
      body: jsonEncode({
        'data': data,
        'error': {'code': code, 'message': 'text'},
      }),
    );

void main() {
  late _StubApiClient client;
  late ApiShoppingProposals port;

  setUp(() {
    client = _StubApiClient();
    port = ApiShoppingProposals(client);
  });

  group('list', () {
    test('by conversation reads every state', () async {
      client.nextResult = ApiSuccess(
        body: jsonEncode({
          'data': [_proposal],
        }),
      );

      final rows = await port.list(conversationId: 'c1');

      expect(client.lastPath, '/shopping/proposals');
      expect(client.lastParams, {'conversation_id': 'c1'});
      expect(rows.single.state, 'accepted');
    });

    test('without one reads the waiting', () async {
      await port.list();

      expect(client.lastParams, {'state': 'waiting'});
    });

    test('a null array is an empty list', () async {
      client.nextResult = const ApiSuccess(body: '{"data":null}');

      expect(await port.list(), isEmpty);
    });

    for (final result in <ApiResult>[
      const ApiPermanentFailure(statusCode: 500, message: 'boom'),
      const ApiTransientFailure(reason: 'no route'),
      const ApiNotConfigured(),
      const ApiSuccess(body: 'not json'),
      const ApiSuccess(body: '{"data":[{"id":1}]}'),
    ]) {
      test('$result fails as the port says', () {
        client.nextResult = result;

        expect(port.list(), throwsA(isA<ShoppingProposalsException>()));
      });
    }
  });

  group('answer', () {
    test('accept posts and returns the proposal', () async {
      client.nextResult = ApiSuccess(
        body: jsonEncode({
          'data': {
            'proposal': _proposal,
            'item': {'id': 'i1'},
          },
        }),
      );

      final answer = await port.accept('p/1');

      expect(client.lastPath, '/shopping/proposals/p%2F1/accept');
      expect((answer as ProposalAnswered).proposal.state, 'accepted');
    });

    test('skip posts and returns the proposal', () async {
      client.nextResult = ApiSuccess(
        body: jsonEncode({
          'data': {'proposal': _proposal},
        }),
      );

      final answer = await port.skip('p1');

      expect(client.lastPath, '/shopping/proposals/p1/skip');
      expect(answer, isA<ProposalAnswered>());
    });

    test('proposal_not_waiting carries the state', () async {
      client.nextResult = _conflict(
        'proposal_not_waiting',
        data: {'state': 'skipped'},
      );

      final answer = await port.accept('p1');

      expect((answer as ProposalNotWaiting).state, 'skipped');
    });

    test('item_removed is its own outcome', () async {
      client.nextResult = _conflict('item_removed');

      expect(await port.accept('p1'), isA<ProposalItemRemoved>());
    });

    test('another conflict is a failure', () async {
      client.nextResult = _conflict('something_else');

      expect(await port.accept('p1'), isA<ProposalAnswerFailed>());
    });

    test('a 409 without a body is a failure', () async {
      client.nextResult =
          const ApiPermanentFailure(statusCode: 409, message: 'Conflict');

      expect(await port.accept('p1'), isA<ProposalAnswerFailed>());
    });

    test('a 404 is a failure', () async {
      client.nextResult =
          const ApiPermanentFailure(statusCode: 404, message: 'Not found');

      final answer = await port.skip('p1');

      expect(
        (answer as ProposalAnswerFailed).message,
        'Server error 404: Not found',
      );
    });

    for (final result in <ApiResult>[
      const ApiTransientFailure(reason: 'no route'),
      const ApiNotConfigured(),
      const ApiSuccess(body: 'not json'),
      const ApiSuccess(body: '{"data":{}}'),
      const ApiSuccess(),
    ]) {
      test('$result never throws', () async {
        client.nextResult = result;

        expect(await port.accept('p1'), isA<ProposalAnswerFailed>());
      });
    }
  });
}
