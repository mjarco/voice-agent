import 'dart:convert';

import 'package:voice_agent/core/models/routine.dart';
import 'package:voice_agent/core/network/api_client.dart';
import 'package:voice_agent/features/routines/domain/routines_repository.dart';

class ApiRoutinesRepository implements RoutinesRepository {
  ApiRoutinesRepository(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<List<Routine>> fetchRoutines(RoutineStatus status) async {
    final result = await _apiClient.get(
      '/routines',
      queryParameters: {'status': status.name},
    );
    return _parseList(result, Routine.fromMap);
  }

  @override
  Future<Routine> fetchRoutineDetail(String id) async {
    final result = await _apiClient.get('/routines/$id');
    return _parseSingle(result, Routine.fromMap);
  }

  @override
  Future<List<RoutineOccurrence>> fetchOccurrences(String id) async {
    final result = await _apiClient.get('/routines/$id/occurrences');
    return _parseList(result, RoutineOccurrence.fromMap);
  }

  @override
  Future<Routine> createRoutine(RoutineInput input) async {
    final result = await _apiClient.postJson('/routines', data: input.toMap());
    return _parseSingle(result, Routine.fromMap);
  }

  @override
  Future<Routine> editRoutine(
    String id,
    RoutineInput input, {
    required String startsOn,
  }) async {
    final result = await _apiClient.postJson(
      '/routines/$id/edit',
      data: {...input.toMap(), 'starts_on': startsOn},
    );
    return _parseSingle(result, Routine.fromMap);
  }

  @override
  Future<void> endRoutine(String id, String lastDay) async {
    final result = await _apiClient.postJson(
      '/routines/$id/end',
      data: {'last_day': lastDay},
    );
    _throwOnFailure(result);
  }

  @override
  Future<void> resolveOccurrence(
    String routineId,
    String scheduledFor,
    OccurrenceStatus status,
  ) async {
    final result = await _apiClient.postJson(
      '/routines/$routineId/resolve',
      data: {'scheduled_for': scheduledFor, 'status': status.toJson()},
    );
    _throwOnFailure(result);
  }

  @override
  Future<void> activateRoutine(String id) async {
    final result = await _apiClient.postJson('/routines/$id/activate');
    _throwOnFailure(result);
  }

  @override
  Future<void> pauseRoutine(String id) async {
    final result = await _apiClient.postJson('/routines/$id/pause');
    _throwOnFailure(result);
  }

  @override
  Future<void> archiveRoutine(String id) async {
    final result = await _apiClient.postJson('/routines/$id/archive');
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

  List<T> _parseList<T>(
    ApiResult result,
    T Function(Map<String, dynamic>) fromMap,
  ) {
    switch (result) {
      case ApiSuccess(body: final body):
        if (body == null) throw RoutinesGeneralException('Empty response');
        final json = jsonDecode(body) as Map<String, dynamic>;
        final data = json['data'] as List<dynamic>?;
        if (data == null) throw RoutinesGeneralException('Missing data envelope');
        return data
            .map((e) => fromMap(e as Map<String, dynamic>))
            .toList();
      case ApiPermanentFailure(message: final msg, statusCode: final code):
        throw RoutinesGeneralException('Server error $code: $msg');
      case ApiTransientFailure(reason: final reason):
        throw RoutinesGeneralException(reason);
      case ApiNotConfigured():
        throw RoutinesGeneralException('API not configured');
    }
  }

  T _parseSingle<T>(
    ApiResult result,
    T Function(Map<String, dynamic>) fromMap,
  ) {
    switch (result) {
      case ApiSuccess(body: final body):
        if (body == null) throw RoutinesGeneralException('Empty response');
        final json = jsonDecode(body) as Map<String, dynamic>;
        final data = json['data'] as Map<String, dynamic>?;
        if (data == null) throw RoutinesGeneralException('Missing data envelope');
        return fromMap(data);
      case ApiPermanentFailure():
      case ApiTransientFailure():
      case ApiNotConfigured():
        throw _failure(result);
    }
  }

  void _throwOnFailure(ApiResult result) {
    if (result is ApiSuccess) return;
    throw _failure(result);
  }

  /// The exception for a failed write. The server's own message is shown
  /// when its error envelope has one (it names what to fix); a
  /// `409 overdue_occurrence` carries the owed day.
  RoutinesException _failure(ApiResult result) {
    switch (result) {
      case ApiPermanentFailure(statusCode: final code, body: final body):
        final envelope = _errorEnvelope(body);
        final serverMessage = envelope?.message;
        if (code == 409) {
          final data = envelope?.data;
          if (envelope?.code == 'overdue_occurrence' &&
              data?['routine_id'] is String &&
              data?['scheduled_for'] is String) {
            return RoutineOverdueException(
              serverMessage ?? 'An overdue occurrence is still open',
              routineId: data!['routine_id'] as String,
              scheduledFor: data['scheduled_for'] as String,
            );
          }
          return RoutineConflictException(
              serverMessage ?? 'Operation conflict');
        }
        return RoutinesGeneralException(
            serverMessage ?? 'Server error $code: ${result.message}');
      case ApiTransientFailure(reason: final reason):
        return RoutinesGeneralException(reason);
      case ApiNotConfigured():
        return RoutinesGeneralException('API not configured');
      case ApiSuccess():
        return RoutinesGeneralException('Unexpected success');
    }
  }

  static ({String? code, String? message, Map<String, dynamic>? data})?
      _errorEnvelope(String? body) {
    if (body == null || body.isEmpty) return null;
    try {
      final json = jsonDecode(body);
      if (json is! Map<String, dynamic>) return null;
      final error = json['error'];
      final data = json['data'];
      final code = error is Map ? error['code'] : null;
      final message = error is Map ? error['message'] : null;
      return (
        code: code is String ? code : null,
        message: message is String && message.isNotEmpty ? message : null,
        data: data is Map<String, dynamic> ? data : null,
      );
    } on FormatException {
      return null;
    }
  }
}
