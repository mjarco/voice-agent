import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/network/api_client.dart';
import 'package:voice_agent/features/shopping/data/api_shopping_repository.dart';
import 'package:voice_agent/features/shopping/domain/shopping_repository.dart';
import 'package:voice_agent/features/shopping/domain/shopping_state.dart';

class _StubApiClient extends ApiClient {
  _StubApiClient() : super(baseUrl: 'https://test.com/api/v1');

  ApiResult nextResult = const ApiSuccess(body: '{"data":[]}');

  String? lastPath;
  Map<String, dynamic>? lastParams;
  Map<String, dynamic>? lastData;
  String? lastMethod;

  @override
  Future<ApiResult> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    lastMethod = 'GET';
    lastPath = path;
    lastParams = queryParameters;
    return nextResult;
  }

  @override
  Future<ApiResult> postJson(String path, {Map<String, dynamic>? data}) async {
    lastMethod = 'POST';
    lastPath = path;
    lastData = data;
    return nextResult;
  }

  @override
  Future<ApiResult> patch(String path, {Map<String, dynamic>? data}) async {
    lastMethod = 'PATCH';
    lastPath = path;
    lastData = data;
    return nextResult;
  }

  @override
  Future<ApiResult> delete(String path) async {
    lastMethod = 'DELETE';
    lastPath = path;
    return nextResult;
  }
}

String _itemBody({String? typesSource, List<String> types = const []}) =>
    jsonEncode({
      'data': {
        'id': 'i1',
        'text': 'mleko',
        'state': 'to_buy',
        'store_types': types,
        'types_source': ?typesSource,
      },
    });

void main() {
  late _StubApiClient client;
  late ApiShoppingRepository repository;

  setUp(() {
    client = _StubApiClient();
    repository = ApiShoppingRepository(client);
  });

  test('fetchCatalogue reads labels, counts and the total', () async {
    client.nextResult = ApiSuccess(
      body: jsonEncode({
        'data': {
          'store_types': [
            {'id': 'grocery', 'label': 'Spożywczy', 'count': 3},
          ],
          'total': 3,
        },
      }),
    );

    final catalogue = await repository.fetchCatalogue();

    expect(client.lastPath, '/shopping/store-types');
    expect(catalogue.total, 3);
    expect(catalogue.label('grocery'), 'Spożywczy');
    expect(catalogue.label('unknown'), 'unknown');
  });

  test('fetchItems asks for the view and the store type', () async {
    await repository.fetchItems(ShoppingView.bought, storeType: 'diy');

    expect(client.lastPath, '/shopping/items');
    expect(client.lastParams, {'state': 'bought', 'store_type': 'diy'});
  });

  test('an item without types_source is being tagged', () async {
    client.nextResult = ApiSuccess(body: _itemBody(), statusCode: 201);

    final result = await repository.addItem('mleko');

    expect(result.item.isTagging, isTrue);
  });

  test('a failed tag is not being tagged', () async {
    client.nextResult = ApiSuccess(body: _itemBody(typesSource: 'failed'));

    final item = await repository.restore('i1');

    expect(item.isTagging, isFalse);
  });

  test('addItem sends source phone and leaves out empty types', () async {
    client.nextResult = ApiSuccess(body: _itemBody(), statusCode: 201);

    await repository.addItem('mleko');

    expect(client.lastPath, '/shopping/items');
    expect(client.lastData, {'text': 'mleko', 'source': 'phone'});
  });

  test('addItem tells a new item from an existing one', () async {
    client.nextResult = ApiSuccess(body: _itemBody(), statusCode: 201);
    expect((await repository.addItem('mleko')).created, isTrue);

    client.nextResult = ApiSuccess(body: _itemBody(), statusCode: 200);
    expect((await repository.addItem('mleko')).created, isFalse);
  });

  test('markBought sends via phone and the store type', () async {
    await repository.markBought('i1', storeType: 'diy');

    expect(client.lastPath, '/shopping/items/i1/bought');
    expect(client.lastData, {'via': 'phone', 'store_type': 'diy'});
  });

  test('setTypes patches the set', () async {
    await repository.setTypes('i1', ['diy']);

    expect(client.lastMethod, 'PATCH');
    expect(client.lastData, {
      'store_types': ['diy'],
    });
  });

  test('remove deletes the item', () async {
    await repository.remove('i1');

    expect(client.lastMethod, 'DELETE');
    expect(client.lastPath, '/shopping/items/i1');
  });

  test('409 is a conflict', () async {
    client.nextResult = const ApiPermanentFailure(
      statusCode: 409,
      message: 'item_removed',
    );

    expect(
      () => repository.markBought('i1'),
      throwsA(isA<ShoppingConflictException>()),
    );
  });

  test('no connection is a general error with its reason', () async {
    client.nextResult = const ApiTransientFailure(reason: 'no route');

    expect(
      () => repository.addItem('mleko'),
      throwsA(
        isA<ShoppingGeneralException>()
            .having((e) => e.message, 'message', 'no route'),
      ),
    );
  });
}
