import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:voice_agent/core/models/agenda.dart';
import 'package:voice_agent/core/models/routine.dart';
import 'package:voice_agent/core/network/api_client.dart';
import 'package:voice_agent/features/agenda/domain/agenda_repository.dart';

class AgendaException implements Exception {
  AgendaException(this.message);
  final String message;

  @override
  String toString() => message;
}

class ApiAgendaRepository implements AgendaRepository {
  ApiAgendaRepository(this._apiClient);

  final ApiClient _apiClient;
  bool _cleanupDone = false;

  @override
  Future<AgendaResponse> fetchAgenda(String date) async {
    final result = await _apiClient.get(
      '/agenda',
      queryParameters: {'date': date, 'granularity': 'day'},
    );

    final response = switch (result) {
      ApiSuccess(body: final body) => _parseResponse(body),
      ApiPermanentFailure(message: final msg, statusCode: final code) =>
        throw AgendaException('Server error $code: $msg'),
      ApiTransientFailure(reason: final reason) =>
        throw AgendaException(reason),
      ApiNotConfigured() => throw AgendaException('API not configured'),
    };

    if (!_cleanupDone) {
      _cleanupDone = true;
      _cleanupOldCache();
    }

    return response;
  }

  AgendaResponse _parseResponse(String? body) {
    if (body == null) throw AgendaException('Empty response');
    final json = jsonDecode(body) as Map<String, dynamic>;
    final data = json['data'] as Map<String, dynamic>?;
    if (data == null) throw AgendaException('Missing data envelope');
    return AgendaResponse.fromMap(data);
  }

  @override
  Future<CachedAgenda?> getCachedAgenda(String date) async {
    try {
      final file = await _cacheFile(date);
      if (!file.existsSync()) return null;
      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      return CachedAgenda(
        response:
            AgendaResponse.fromMap(json['response'] as Map<String, dynamic>),
        fetchedAt: DateTime.parse(json['fetched_at'] as String),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> cacheAgenda(String date, AgendaResponse response) async {
    try {
      final file = await _cacheFile(date);
      final json = jsonEncode({
        'fetched_at': DateTime.now().toIso8601String(),
        'response': response.toMap(),
      });
      await file.writeAsString(json);
    } catch (_) {
      // Cache write is best-effort
    }
  }

  @override
  Future<void> markActionItemDone(String recordId) async {
    final result = await _apiClient.postJson('/records/$recordId/done');
    _throwOnFailure(result);
  }

  @override
  Future<void> updateOccurrenceStatus(
    String routineId,
    String occurrenceId,
    OccurrenceStatus status,
  ) async {
    final result = await _apiClient.patch(
      '/routines/$routineId/occurrences/$occurrenceId',
      data: {'status': status.toJson()},
    );
    _throwOnFailure(result);
  }

  void _throwOnFailure(ApiResult result) {
    switch (result) {
      case ApiSuccess():
        return;
      case ApiPermanentFailure(message: final msg, statusCode: final code):
        throw AgendaException('Server error $code: $msg');
      case ApiTransientFailure(reason: final reason):
        throw AgendaException(reason);
      case ApiNotConfigured():
        throw AgendaException('API not configured');
    }
  }

  Future<File> _cacheFile(String date) async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/agenda_cache_$date.json');
  }

  Future<void> _cleanupOldCache() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final cutoff = DateTime.now().subtract(const Duration(days: 7));
      final files = dir.listSync().whereType<File>().where(
            (f) => f.path.contains('agenda_cache_') && f.path.endsWith('.json'),
          );
      for (final file in files) {
        final dateStr = file.path
            .split('agenda_cache_')
            .last
            .replaceAll('.json', '');
        final date = DateTime.tryParse(dateStr);
        if (date != null && date.isBefore(cutoff)) {
          await file.delete();
        }
      }
    } catch (_) {
      // Cleanup is best-effort
    }
  }
}
