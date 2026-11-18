import 'dart:convert';

import 'package:voice_agent/core/network/api_client.dart';
import 'package:voice_agent/features/diet/domain/diet_models.dart';
import 'package:voice_agent/features/diet/domain/diet_repository.dart';

class ApiDietRepository implements DietRepository {
  ApiDietRepository(this._api);

  final ApiClient _api;

  /// Writes from the phone are marked as the phone's, as the agenda's are.
  static const _source = 'phone';

  Object? _data(ApiResult r) {
    final body = switch (r) {
      ApiSuccess(:final body) => body,
      ApiPermanentFailure(:final statusCode, :final body, :final message) =>
        throw DietException(_message(body) ?? 'Błąd serwera $statusCode: $message'),
      ApiTransientFailure(:final reason) => throw DietException(reason),
      ApiNotConfigured() => throw DietException('Ustaw adres serwera w Ustawieniach'),
    };
    if (body == null || body.isEmpty) return null;
    final json = jsonDecode(body);
    return json is Map<String, dynamic> ? json['data'] : null;
  }

  static String? _message(String? body) {
    if (body == null) return null;
    try {
      final json = jsonDecode(body);
      final err = json is Map<String, dynamic> ? json['error'] : null;
      return err is Map<String, dynamic> ? err['message'] as String? : null;
    } on FormatException {
      return null;
    }
  }

  List<Map<String, dynamic>> _rows(Object? data) => data is List
      ? [for (final e in data) if (e is Map<String, dynamic>) e]
      : const [];

  @override
  Future<DietDay> day(String day) async {
    final data = _data(await _api.get('/diet/day', queryParameters: {'day': day}));
    if (data is! Map<String, dynamic>) throw DietException('Brak danych dnia');
    return DietDay.fromMap(data);
  }

  @override
  Future<void> editMeal(String id, {int? kcal, int? low, int? high, double? proteinG, String? day, String? time}) async {
    final body = <String, dynamic>{
      if (kcal != null)
        'estimate': {
          'kcal': kcal,
          'kcal_low': ?low,
          'kcal_high': ?high,
          'protein_g': ?proteinG,
        },
      'day': ?day,
      'time': ?time,
    };
    _data(await _api.patch('/diet/meals/$id', data: body));
  }

  @override
  Future<void> removeMeal(String id) async => _data(await _api.delete('/diet/meals/$id'));

  @override
  Future<void> eatPlanned(String menuEntryId) async =>
      _data(await _api.postJson('/diet/meals', data: {'menu_entry_id': menuEntryId, 'source': _source}));

  @override
  Future<DietMeal> eatOwnMeal(String ownMealId) async {
    final data = _data(await _api.postJson('/diet/meals', data: {'own_meal': ownMealId, 'source': _source}));
    if (data is! Map<String, dynamic>) throw DietException('Brak zapisanego posiłku');
    return DietMeal.fromMap(data);
  }

  @override
  Future<List<DietMenuEntry>> menu(String from, String to) async =>
      [for (final e in _rows(_data(await _api.get('/diet/menu', queryParameters: {'from': from, 'to': to})))) DietMenuEntry.fromMap(e)];

  @override
  Future<void> planOwnMeal({required String day, required String slot, required String ownMealId}) async =>
      _data(await _api.postJson('/diet/menu', data: {'day': day, 'slot': slot, 'own_meal': ownMealId}));

  @override
  Future<void> unplan(String id) async => _data(await _api.delete('/diet/menu/$id'));

  @override
  Future<List<DietOwnMeal>> ownMeals() async =>
      [for (final e in _rows(_data(await _api.get('/diet/own-meals')))) DietOwnMeal.fromMap(e)];

  @override
  Future<void> removeOwnMeal(String id) async => _data(await _api.delete('/diet/own-meals/$id'));

  @override
  Future<List<DietTarget>> targets() async =>
      [for (final e in _rows(_data(await _api.get('/diet/targets')))) DietTarget.fromMap(e)];

  @override
  Future<void> setTarget({required int kcalMin, required int kcalMax, int? proteinMin, int? reserveKcal, String? from}) async =>
      _data(await _api.postJson('/diet/targets', data: {
        'kcal_min': kcalMin,
        'kcal_max': kcalMax,
        'protein_min': ?proteinMin,
        'reserve_kcal': ?reserveKcal,
        'from': ?from,
        'source': _source,
      }));
}
