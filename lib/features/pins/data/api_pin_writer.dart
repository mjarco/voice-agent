import 'dart:convert';

import 'package:voice_agent/core/models/pin.dart';
import 'package:voice_agent/core/network/api_client.dart';
import 'package:voice_agent/core/network/pin_writer.dart';
import 'package:voice_agent/features/pins/domain/pins_repository.dart';

/// `ApiClient`-backed [PinWriter] (proposal 046).
///
/// Mirrors `ApiPinsRepository`: unwraps the `{"data": ...}` envelope in feature
/// code (P025 convention) and reuses the dio -> [ApiResult] error
/// classification (ADR-NET-001) mapped onto the shared [PinsException]
/// hierarchy. A `404` (message/conversation gone) becomes
/// [PinNotFoundException]; everything else non-success becomes
/// [PinsGeneralException].
class ApiPinWriter implements PinWriter {
  ApiPinWriter(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<PinSuggestion> suggestPin(
    String conversationId,
    String eventId,
  ) async {
    final result = await _apiClient.postJson(
      '/pins/suggest',
      data: {'conversation_id': conversationId, 'event_id': eventId},
    );
    switch (result) {
      case ApiSuccess(body: final body):
        return PinSuggestion.fromMap(_dataMap(body));
      case ApiPermanentFailure(statusCode: 404):
        throw PinNotFoundException('Message not found');
      case ApiPermanentFailure(message: final msg, statusCode: final code):
        throw PinsGeneralException('Server error $code: $msg');
      case ApiTransientFailure(reason: final reason):
        throw PinsGeneralException(reason);
      case ApiNotConfigured():
        throw PinsGeneralException('API not configured');
    }
  }

  @override
  Future<PinCreateResult> createPin(PinCreateRequest request) async {
    final result = await _apiClient.postJson('/pins', data: request.toMap());
    switch (result) {
      case ApiSuccess(body: final body):
        return PinCreateResult.fromMap(_dataMap(body));
      case ApiPermanentFailure(statusCode: 404):
        throw PinNotFoundException('Message not found');
      case ApiPermanentFailure(message: final msg, statusCode: final code):
        throw PinsGeneralException('Server error $code: $msg');
      case ApiTransientFailure(reason: final reason):
        throw PinsGeneralException(reason);
      case ApiNotConfigured():
        throw PinsGeneralException('API not configured');
    }
  }

  Map<String, dynamic> _dataMap(String? body) {
    if (body == null) throw PinsGeneralException('Empty response');
    final json = jsonDecode(body) as Map<String, dynamic>;
    final data = json['data'];
    if (data is! Map<String, dynamic>) {
      throw PinsGeneralException('Missing data envelope');
    }
    return data;
  }
}
