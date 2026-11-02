import 'dart:convert';

import 'package:voice_agent/core/network/api_client.dart';
import 'package:voice_agent/features/places/domain/place.dart';
import 'package:voice_agent/features/places/domain/places_ports.dart';

class ApiPlacesRepository implements PlacesRepository {
  ApiPlacesRepository(this._apiClient);

  final ApiClient _apiClient;

  static const _places = '/places';

  @override
  Future<List<Place>> fetchPlaces() async {
    final data = _data(await _apiClient.get(_places)) as Map<String, dynamic>;
    return (data['places'] as List<dynamic>)
        .map((e) => Place.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<PlaceStoreType>> fetchStoreTypes() async {
    final data =
        _data(await _apiClient.get('/shopping/store-types'))
            as Map<String, dynamic>;
    return (data['store_types'] as List<dynamic>)
        .map((e) => PlaceStoreType.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<Place> put(Place place) async {
    final body = place.toMap()..remove('id');
    final result = await _apiClient.request(
      'PUT',
      '$_places/${Uri.encodeComponent(place.id)}',
      data: body,
    );
    return Place.fromMap(_data(result) as Map<String, dynamic>);
  }

  @override
  Future<void> delete(String id) async {
    _data(await _apiClient.delete('$_places/${Uri.encodeComponent(id)}'));
  }

  Object? _data(ApiResult result) => switch (result) {
    ApiSuccess(:final body) => _envelope(body),
    ApiPermanentFailure(:final message) => throw PlacesException(
      message,
      temporary: false,
    ),
    ApiTransientFailure(:final reason) => throw PlacesException(
      reason,
      temporary: true,
    ),
    ApiNotConfigured() => throw const PlacesException(
      'Brak adresu personal-agent',
      temporary: true,
    ),
  };

  Object? _envelope(String? body) {
    if (body == null) {
      throw const PlacesException('Pusta odpowiedź', temporary: true);
    }
    return (jsonDecode(body) as Map<String, dynamic>)['data'];
  }
}
