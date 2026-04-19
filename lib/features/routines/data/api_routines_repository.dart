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
  Future<List<RoutineProposal>> fetchProposals() async {
    final result = await _apiClient.get('/routine-proposals');
    return _parseList(result, RoutineProposal.fromMap);
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
  Future<void> triggerRoutine(String id, String scheduledFor) async {
    final result = await _apiClient.postJson(
      '/routines/$id/trigger',
      data: {'scheduled_for': scheduledFor},
    );
    _throwOnFailure(result, is409Trigger: true);
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

  @override
  Future<void> approveProposal(String proposalId) async {
    final result =
        await _apiClient.postJson('/records/$proposalId/approve-as-routine');
    _throwOnFailure(result);
  }

  @override
  Future<void> rejectProposal(String proposalId) async {
    final result = await _apiClient.postJson('/records/$proposalId/reject');
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
      case ApiPermanentFailure(message: final msg, statusCode: final code):
        throw RoutinesGeneralException('Server error $code: $msg');
      case ApiTransientFailure(reason: final reason):
        throw RoutinesGeneralException(reason);
      case ApiNotConfigured():
        throw RoutinesGeneralException('API not configured');
    }
  }

  void _throwOnFailure(ApiResult result, {bool is409Trigger = false}) {
    switch (result) {
      case ApiSuccess():
        return;
      case ApiPermanentFailure(statusCode: 409):
        if (is409Trigger) {
          throw RoutineAlreadyTriggedException();
        }
        throw RoutineConflictException('Operation conflict');
      case ApiPermanentFailure(message: final msg, statusCode: final code):
        throw RoutinesGeneralException('Server error $code: $msg');
      case ApiTransientFailure(reason: final reason):
        throw RoutinesGeneralException(reason);
      case ApiNotConfigured():
        throw RoutinesGeneralException('API not configured');
    }
  }
}
