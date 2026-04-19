import 'dart:convert';

import 'package:voice_agent/core/models/plan.dart';
import 'package:voice_agent/core/network/api_client.dart';
import 'package:voice_agent/features/plan/domain/plan_repository.dart';

class ApiPlanRepository implements PlanRepository {
  ApiPlanRepository(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<PlanResponse> fetchPlan() async {
    final result = await _apiClient.get('/plan');
    return switch (result) {
      ApiSuccess(body: final body) => _parsePlanResponse(body),
      ApiPermanentFailure(message: final msg, statusCode: final code) =>
        throw PlanGeneralException('Server error $code: $msg'),
      ApiTransientFailure(reason: final reason) =>
        throw PlanGeneralException(reason),
      ApiNotConfigured() => throw PlanGeneralException('API not configured'),
    };
  }

  @override
  Future<void> markDone(String id) => _postAction('/records/$id/done');

  @override
  Future<void> dismiss(String id) => _postAction('/records/$id/dismiss');

  @override
  Future<void> confirm(String id) => _postAction('/records/$id/confirm');

  @override
  Future<void> toggleEndorse(String id) =>
      _postAction('/records/$id/endorse');

  Future<void> _postAction(String path) async {
    final result = await _apiClient.postJson(path);
    switch (result) {
      case ApiSuccess():
        return;
      case ApiPermanentFailure(statusCode: 409):
        throw PlanConflictException();
      case ApiPermanentFailure(message: final msg, statusCode: final code):
        throw PlanGeneralException('Server error $code: $msg');
      case ApiTransientFailure(reason: final reason):
        throw PlanGeneralException(reason);
      case ApiNotConfigured():
        throw PlanGeneralException('API not configured');
    }
  }

  PlanResponse _parsePlanResponse(String? body) {
    if (body == null) throw PlanGeneralException('Empty response');
    final json = jsonDecode(body) as Map<String, dynamic>;
    final data = json['data'] as Map<String, dynamic>?;
    if (data == null) throw PlanGeneralException('Missing data envelope');
    return PlanResponse.fromMap(data);
  }
}
