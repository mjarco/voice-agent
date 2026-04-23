import 'dart:convert';

import 'package:voice_agent/core/network/api_client.dart';
import 'package:voice_agent/features/usage/domain/usage_summary.dart';

class UsageException implements Exception {
  UsageException(this.message);
  final String message;

  @override
  String toString() => message;
}

class UsageService {
  UsageService(this._apiClient);

  final ApiClient _apiClient;

  Future<UsageSummary> getSummary({
    required String from,
    required String to,
  }) async {
    final result = await _apiClient.get(
      '/usage/summary',
      queryParameters: {'from': from, 'to': to},
    );

    return switch (result) {
      ApiSuccess(body: final body) => _parseResponse(body),
      ApiPermanentFailure(message: final msg, statusCode: final code) =>
        throw UsageException('Server error $code: $msg'),
      ApiTransientFailure(reason: final reason) =>
        throw UsageException(reason),
      ApiNotConfigured() => throw UsageException('API not configured'),
    };
  }

  UsageSummary _parseResponse(String? body) {
    if (body == null) throw UsageException('Empty response');
    final json = jsonDecode(body) as Map<String, dynamic>;
    return UsageSummary.fromMap(json);
  }
}
