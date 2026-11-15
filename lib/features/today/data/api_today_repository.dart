import 'dart:convert';

import 'package:voice_agent/core/models/today.dart';
import 'package:voice_agent/core/network/api_client.dart';
import 'package:voice_agent/features/today/domain/today_repository.dart';

class ApiTodayRepository implements TodayRepository {
  ApiTodayRepository(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<TodayView> fetchToday() async {
    final result = await _apiClient
        .get('/today', queryParameters: {'v': '${TodayView.version}'});
    final body = _unwrap(result);
    final json = jsonDecode(body) as Map<String, dynamic>;
    final data = json['data'];
    if (data is! Map<String, dynamic>) {
      throw TodayException('Brak danych w odpowiedzi');
    }
    return TodayView.fromMap(data);
  }

  @override
  Future<void> run(TodayAction action) async {
    final uri = Uri.parse(action.apiPath);
    final result = await _apiClient.request(
      action.method,
      uri.path,
      data: action.body,
      queryParameters: uri.queryParameters.isEmpty ? null : uri.queryParameters,
    );
    _unwrap(result);
  }

  String _unwrap(ApiResult result) => switch (result) {
        ApiSuccess(:final body) => body ?? '{}',
        ApiPermanentFailure(:final statusCode, :final message) =>
          throw TodayException('Błąd serwera $statusCode: $message'),
        ApiTransientFailure(:final reason) => throw TodayException(reason),
        ApiNotConfigured() =>
          throw TodayException('Ustaw adres serwera w Ustawieniach'),
      };
}
