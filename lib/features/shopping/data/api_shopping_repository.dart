import 'dart:convert';

import 'package:voice_agent/core/network/api_client.dart';
import 'package:voice_agent/features/shopping/domain/shopping_models.dart';
import 'package:voice_agent/features/shopping/domain/shopping_repository.dart';
import 'package:voice_agent/features/shopping/domain/shopping_state.dart';

class ApiShoppingRepository implements ShoppingRepository {
  ApiShoppingRepository(this._apiClient);

  final ApiClient _apiClient;

  static const _items = '/shopping/items';

  @override
  Future<ShoppingCatalogue> fetchCatalogue() async {
    final result = await _apiClient.get('/shopping/store-types');
    final body = _body(result);
    return ShoppingCatalogue.fromMap(_data(body) as Map<String, dynamic>);
  }

  @override
  Future<List<ShoppingItem>> fetchItems(
    ShoppingView view, {
    String? storeType,
  }) async {
    final result = await _apiClient.get(_items, queryParameters: {
      'state': view == ShoppingView.bought ? 'bought' : 'to_buy',
      'store_type': ?storeType,
    });
    final data = _data(_body(result)) as List<dynamic>;
    return data
        .map((e) => ShoppingItem.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<ShoppingAddResult> addItem(
    String text, {
    List<String> storeTypes = const [],
  }) async {
    final result = await _apiClient.postJson(_items, data: {
      'text': text,
      'source': 'phone',
      if (storeTypes.isNotEmpty) 'store_types': storeTypes,
    });
    return ShoppingAddResult(
      item: _item(_body(result)),
      created: result is ApiSuccess && result.statusCode == 201,
    );
  }

  @override
  Future<void> edit(String id, {String? text, List<String>? storeTypes}) async {
    _body(await _apiClient.patch(
      '$_items/$id',
      data: {
        'text': ?text,
        'store_types': ?storeTypes,
      },
    ));
  }

  @override
  Future<void> markBought(String id, {String? storeType}) async {
    _body(await _apiClient.postJson('$_items/$id/bought', data: {
      'via': 'phone',
      'store_type': ?storeType,
    }));
  }

  @override
  Future<ShoppingItem> restore(String id) async {
    return _item(_body(await _apiClient.postJson('$_items/$id/restore')));
  }

  @override
  Future<void> remove(String id) async {
    _body(await _apiClient.delete('$_items/$id'));
  }

  String? _body(ApiResult result) {
    return switch (result) {
      ApiSuccess(body: final body) => body,
      ApiPermanentFailure(statusCode: 409, body: final body) =>
        throw _errorCode(body) == 'text_taken'
            ? ShoppingConflictException('Already on the list')
            : ShoppingConflictException(),
      ApiPermanentFailure(message: final msg, statusCode: final code) =>
        throw ShoppingGeneralException('Server error $code: $msg'),
      ApiTransientFailure(reason: final reason) =>
        throw ShoppingGeneralException(reason),
      ApiNotConfigured() =>
        throw ShoppingGeneralException('API not configured'),
    };
  }

  /// The `error.code` of an error envelope, null when there is none.
  static String? _errorCode(String? body) {
    if (body == null) return null;
    try {
      final json = jsonDecode(body);
      if (json is! Map<String, dynamic>) return null;
      final error = json['error'];
      return error is Map<String, dynamic> ? error['code'] as String? : null;
    } on FormatException {
      return null;
    }
  }

  dynamic _data(String? body) {
    if (body == null) throw ShoppingGeneralException('Empty response');
    final json = jsonDecode(body) as Map<String, dynamic>;
    final data = json['data'];
    if (data == null) throw ShoppingGeneralException('Missing data envelope');
    return data;
  }

  ShoppingItem _item(String? body) =>
      ShoppingItem.fromMap(_data(body) as Map<String, dynamic>);
}
