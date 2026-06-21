import 'dart:convert';

import 'package:voice_agent/core/models/pin.dart';
import 'package:voice_agent/core/network/api_client.dart';
import 'package:voice_agent/features/pins/domain/pins_repository.dart';

/// `ApiClient`-backed pins repository.
///
/// Unwraps the `{"data": ...}` envelope in feature code (P025 convention,
/// matching `api_agenda_repository.dart` / `api_plan_repository.dart`);
/// ADR-NET-001 governs only the dio -> [ApiResult] error classification reused
/// here, not the envelope.
class ApiPinsRepository implements PinsRepository {
  ApiPinsRepository(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<List<PinSummary>> fetchPins(PinView view) async {
    final result = await _apiClient.get(
      '/pins',
      queryParameters: {'view': view.queryValue},
    );
    return switch (result) {
      ApiSuccess(body: final body) => _parseList(body),
      ApiPermanentFailure(message: final msg, statusCode: final code) =>
        throw PinsGeneralException('Server error $code: $msg'),
      ApiTransientFailure(reason: final reason) =>
        throw PinsGeneralException(reason),
      ApiNotConfigured() => throw PinsGeneralException('API not configured'),
    };
  }

  @override
  Future<PinDetail> fetchPin(String recordId) async {
    final result = await _apiClient.get('/pins/$recordId');
    switch (result) {
      case ApiSuccess(body: final body):
        return _parseDetail(body);
      case ApiPermanentFailure(statusCode: 404):
        throw PinNotFoundException();
      case ApiPermanentFailure(message: final msg, statusCode: final code):
        throw PinsGeneralException('Server error $code: $msg');
      case ApiTransientFailure(reason: final reason):
        throw PinsGeneralException(reason);
      case ApiNotConfigured():
        throw PinsGeneralException('API not configured');
    }
  }

  @override
  Future<void> unpin(String recordId) async {
    final result = await _apiClient.delete('/pins/$recordId');
    switch (result) {
      case ApiSuccess():
        return;
      case ApiPermanentFailure(statusCode: 404):
        throw PinNotFoundException();
      case ApiPermanentFailure(message: final msg, statusCode: final code):
        throw PinsGeneralException('Server error $code: $msg');
      case ApiTransientFailure(reason: final reason):
        throw PinsGeneralException(reason);
      case ApiNotConfigured():
        throw PinsGeneralException('API not configured');
    }
  }

  List<PinSummary> _parseList(String? body) {
    if (body == null) throw PinsGeneralException('Empty response');
    final json = jsonDecode(body) as Map<String, dynamic>;
    final data = json['data'];
    if (data is! List) throw PinsGeneralException('Missing data envelope');
    return data
        .map((e) => PinSummary.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  PinDetail _parseDetail(String? body) {
    if (body == null) throw PinsGeneralException('Empty response');
    final json = jsonDecode(body) as Map<String, dynamic>;
    final data = json['data'];
    if (data is! Map<String, dynamic>) {
      throw PinsGeneralException('Missing data envelope');
    }
    return PinDetail.fromMap(data);
  }
}
