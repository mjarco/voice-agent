import 'dart:convert';

import 'package:voice_agent/core/models/day_story.dart';
import 'package:voice_agent/core/network/api_client.dart';
import 'package:voice_agent/features/today/domain/day_story_repository.dart';
import 'package:voice_agent/features/today/domain/today_repository.dart';

class ApiDayStoryRepository implements DayStoryRepository {
  ApiDayStoryRepository(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<DayStory> fetch(String day, {bool narrate = true}) async {
    final result = await _apiClient.get('/day/story', queryParameters: {
      'day': day,
      if (!narrate) 'narrate': '0',
    });
    final json = jsonDecode(_unwrap(result)) as Map<String, dynamic>;
    final data = json['data'];
    if (data is! Map<String, dynamic>) throw TodayException('Brak danych w odpowiedzi');
    return DayStory.fromMap(data);
  }

  @override
  Future<void> settle(String id, int? guess) async {
    _unwrap(await _apiClient.request('POST', '/day/pending/$id/settle', data: {'guess': guess}));
  }

  String _unwrap(ApiResult result) => switch (result) {
        ApiSuccess(:final body) => body ?? '{}',
        ApiPermanentFailure(:final statusCode, :final message) =>
          throw TodayException('Błąd serwera $statusCode: $message'),
        ApiTransientFailure(:final reason) => throw TodayException(reason),
        ApiNotConfigured() => throw TodayException('Ustaw adres serwera w Ustawieniach'),
      };
}
