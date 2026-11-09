import 'dart:convert';

import 'package:voice_agent/core/models/matter.dart';
import 'package:voice_agent/core/network/api_client.dart';
import 'package:voice_agent/features/matters/domain/matters_repository.dart';

/// `ApiClient`-backed matters repository (ADR-CORE-118 of personal-agent).
///
/// Unwraps the `{"data": ...}` envelope in feature code (P025 convention, as
/// `api_pins_repository.dart` does). Every write says `source: phone`.
class ApiMattersRepository implements MattersRepository {
  ApiMattersRepository(this._apiClient);

  static const _source = 'phone';

  final ApiClient _apiClient;

  @override
  Future<List<MatterSummary>> fetchMatters({
    MatterFilter filter = MatterFilter.current,
  }) async {
    final result = await _apiClient.get(
      '/matters',
      queryParameters:
          filter == MatterFilter.current ? null : {'status': filter.name},
    );
    final data = _data(result);
    if (data is! List) throw MattersGeneralException('Missing data envelope');
    return data
        .whereType<Map<String, dynamic>>()
        .map(MatterSummary.fromMap)
        .toList();
  }

  @override
  Future<MatterDetail> fetchMatter(String id) async =>
      _detail(await _apiClient.get('/matters/$id'));

  @override
  Future<MatterDetail> createMatter({
    required String title,
    String keywords = '',
    String nextStep = '',
  }) async {
    final result = await _apiClient.postJson('/matters', data: {
      'title': title,
      if (keywords.isNotEmpty) 'keywords': keywords,
      if (nextStep.isNotEmpty) 'next_step': nextStep,
      'source': _source,
    });
    return _detail(result);
  }

  @override
  Future<MatterDetail> editMatter(
    String id, {
    String? title,
    String? keywords,
    MatterStatus? status,
    String? nextStep,
    String? waitingFor,
  }) async {
    final result = await _apiClient.patch('/matters/$id', data: {
      'title': ?title,
      'keywords': ?keywords,
      'status': ?status?.toJson(),
      'next_step': ?nextStep,
      'waiting_for': ?waitingFor,
      'source': _source,
    });
    return _detail(result);
  }

  @override
  Future<void> deleteMatter(String id) async =>
      _done(await _apiClient.delete('/matters/$id'));

  @override
  Future<MatterDetail> accept(String id, MatterStatus status) async {
    final result = await _apiClient.postJson(
      '/matters/$id/accept',
      data: {'status': status.toJson()},
    );
    return _detail(result);
  }

  @override
  Future<void> drop(String id) async =>
      _done(await _apiClient.postJson('/matters/$id/drop'));

  @override
  Future<MatterEntry> addEntry(String id, String text) async {
    final result = await _apiClient.postJson(
      '/matters/$id/entries',
      data: {'text': text, 'source': _source},
    );
    final data = _data(result);
    if (data is! Map<String, dynamic>) {
      throw MattersGeneralException('Missing data envelope');
    }
    return MatterEntry.fromMap(data);
  }

  @override
  Future<void> deleteEntry(String id, String entryId) async =>
      _done(await _apiClient.delete('/matters/$id/entries/$entryId'));

  /// `ApiClient.delete` takes no query, so the source rides in the path.
  @override
  Future<void> unlink(String id, String linkId) async => _done(
        await _apiClient.delete('/matters/$id/links/$linkId?source=$_source'),
      );

  MatterDetail _detail(ApiResult result) {
    final data = _data(result);
    if (data is! Map<String, dynamic>) {
      throw MattersGeneralException('Missing data envelope');
    }
    return MatterDetail.fromMap(data);
  }

  void _done(ApiResult result) {
    if (result is ApiSuccess) return;
    throw matterFailure(result);
  }

  dynamic _data(ApiResult result) {
    if (result is! ApiSuccess) throw matterFailure(result);
    final body = result.body;
    if (body == null) throw MattersGeneralException('Empty response');
    final json = jsonDecode(body);
    if (json is! Map<String, dynamic>) {
      throw MattersGeneralException('Missing data envelope');
    }
    return json['data'];
  }
}

/// The exception for a failed matter call: a `404` becomes
/// [MatterNotFoundException]; a refusal whose error envelope has a code and a
/// message becomes [MatterRefusedException], whose message is the server's.
MattersException matterFailure(ApiResult result) {
  switch (result) {
    case ApiPermanentFailure(
        statusCode: final code,
        message: final message,
        body: final body,
      ):
      final error = _errorOf(body);
      final refusedCode = error?['code'];
      final refusedMessage = error?['message'];
      final hasMessage = refusedMessage is String && refusedMessage.isNotEmpty;
      if (code == 404) {
        return hasMessage
            ? MatterNotFoundException(refusedMessage)
            : MatterNotFoundException();
      }
      if (refusedCode is String && hasMessage) {
        return MatterRefusedException(refusedCode, refusedMessage);
      }
      return MattersGeneralException('Server error $code: $message');
    case ApiTransientFailure(reason: final reason):
      return MattersGeneralException(reason);
    case ApiNotConfigured():
      return MattersGeneralException('API not configured');
    case ApiSuccess():
      return MattersGeneralException('Unexpected success');
  }
}

Map<String, dynamic>? _errorOf(String? body) {
  if (body == null || body.isEmpty) return null;
  try {
    final json = jsonDecode(body);
    if (json is! Map<String, dynamic>) return null;
    final error = json['error'];
    return error is Map<String, dynamic> ? error : null;
  } on FormatException {
    return null;
  }
}
