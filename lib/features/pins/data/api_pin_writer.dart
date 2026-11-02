import 'dart:convert';

import 'package:voice_agent/core/models/pin.dart';
import 'package:voice_agent/core/network/api_client.dart';
import 'package:voice_agent/core/network/pin_writer.dart';
import 'package:voice_agent/features/pins/data/pin_api_failure.dart';
import 'package:voice_agent/features/pins/domain/pins_repository.dart';

/// `ApiClient`-backed [PinWriter] (proposal 046).
///
/// Mirrors `ApiPinsRepository`: unwraps the `{"data": ...}` envelope in feature
/// code (P025 convention) and reuses the dio -> [ApiResult] error
/// classification (ADR-NET-001) mapped onto the shared [PinsException]
/// hierarchy by [pinFailure].
class ApiPinWriter implements PinWriter {
  ApiPinWriter(this._apiClient);

  static const _messageNotFound = 'Message not found';

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
    if (result case ApiSuccess(body: final body)) {
      return PinSuggestion.fromMap(_dataMap(body));
    }
    throw pinFailure(result, notFoundMessage: _messageNotFound);
  }

  @override
  Future<PinCreateResult> createPin(PinCreateRequest request) async {
    final result = await _apiClient.postJson('/pins', data: request.toMap());
    if (result case ApiSuccess(body: final body)) {
      return PinCreateResult.fromMap(_dataMap(body));
    }
    throw pinFailure(result, notFoundMessage: _messageNotFound);
  }

  @override
  Future<PinSuggestion> suggestPinFromText(String text) async {
    final result = await _apiClient.postJson(
      '/pins/suggest',
      data: {'text': text},
    );
    if (result case ApiSuccess(body: final body)) {
      return PinSuggestion.fromMap(_dataMap(body));
    }
    throw pinFailure(result);
  }

  @override
  Future<PinCreateResult> createTextPin(PinTextCreateRequest request) async {
    final result = await _apiClient.postJson('/pins', data: request.toMap());
    if (result case ApiSuccess(body: final body)) {
      return PinCreateResult.fromMap(_dataMap(body));
    }
    throw pinFailure(result);
  }

  @override
  Future<PinCreateResult> editPin(
    String recordId, {
    String? name,
    String? text,
  }) async {
    final result = await _apiClient.patch(
      '/pins/$recordId',
      data: {
        'name': ?name,
        'text': ?text,
      },
    );
    if (result case ApiSuccess(body: final body)) {
      return PinCreateResult.fromMap(_dataMap(body));
    }
    throw pinFailure(result);
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
